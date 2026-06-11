"""KYC / identity verification endpoints.

Flow:
  1. User uploads CNI front, CNI back, selfie + CNI number via
     `POST /kyc/submit`. A new `IdentityVerification` row is created
     in PENDING status. `users.is_verified` is **not** flipped here.
  2. Reviewer (a user with `is_kyc_reviewer=True`) hits
     `GET /kyc/admin/pending` to see queue items, opens each via
     `GET /kyc/admin/{id}` for the docs, then calls approve/reject.
  3. On approve, `users.is_verified` flips to True. On reject, a note
     is stored and the user may resubmit.

Document files live under `uploads/kyc/<verification_id>/<role>.<ext>`
so that deleting a verification cleans them up by directory. The files
themselves are served via an admin-gated route — never publicly.
"""
from __future__ import annotations

import os
import uuid as uuidlib
from datetime import datetime, timedelta, timezone
from typing import Optional

# Minimum time a reviewer must wait between submission and decision.
# Approve/reject endpoints 400 when called before submitted_at + this delta,
# and the admin UI shows a live countdown. Tuned so a reviewer can't
# rubber-stamp without actually looking at the documents.
REVIEW_MIN_WAIT = timedelta(minutes=5)

from fastapi import (
    APIRouter, Depends, File, Form, HTTPException, UploadFile,
)
from fastapi.responses import FileResponse
from sqlalchemy import select, desc
from sqlalchemy.ext.asyncio import AsyncSession

from core.database import get_db
from core.security import get_current_user
from models.identity import IdentityVerification, VerificationStatus
from models.identity_schemas import (
    PendingListResponse, PendingVerificationOut, ReviewDecisionRequest,
    VerificationStatusOut,
)
from models.user import User

router = APIRouter(prefix="/kyc", tags=["KYC"])

UPLOAD_ROOT = "uploads/kyc"
os.makedirs(UPLOAD_ROOT, exist_ok=True)

_ALLOWED_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/heic", "image/webp"}
_MAX_BYTES = 8 * 1024 * 1024   # 8 MB per file — CNI photos can be heavy on modern phones


# ─── Helpers ──────────────────────────────────────────────────
async def _require_reviewer(
    db: AsyncSession, current_user: dict,
) -> User:
    res = await db.execute(select(User).where(User.id == current_user["user_id"]))
    me = res.scalar_one_or_none()
    if not me or not me.is_kyc_reviewer:
        raise HTTPException(status_code=403, detail="Reviewer access required")
    return me


async def _save_upload(file: UploadFile, dest_dir: str, role: str) -> str:
    """Stream-write an UploadFile to disk and return the public URL path.
    Validates MIME + size; rejects anything we don't recognise so a
    malicious client can't upload a `.exe` masquerading as a CNI."""
    if not file.content_type or file.content_type.lower() not in _ALLOWED_TYPES:
        raise HTTPException(status_code=400, detail=f"Unsupported file type for {role}")
    contents = await file.read()
    if len(contents) > _MAX_BYTES:
        raise HTTPException(status_code=400, detail=f"{role} file too large (max 8MB)")
    ext = os.path.splitext(file.filename or "")[1].lower() or ".jpg"
    os.makedirs(dest_dir, exist_ok=True)
    filename = f"{role}{ext}"
    abs_path = os.path.join(dest_dir, filename)
    with open(abs_path, "wb") as f:
        f.write(contents)
    return abs_path


def _doc_url(verification_id: str, role: str) -> str:
    return f"/api/v1/kyc/admin/{verification_id}/doc/{role}"


def _mask_cni(cni: str | None) -> str | None:
    """Mask everything except the last 4 chars. Short CNIs (≤4) are
    fully masked rather than returned as-is."""
    if not cni:
        return None
    if len(cni) <= 4:
        return "•" * len(cni)
    return "•" * (len(cni) - 4) + cni[-4:]


# ─── User-facing endpoints ────────────────────────────────────
@router.get("/me", response_model=VerificationStatusOut)
async def my_status(
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Returns the latest submission's state, or `unsubmitted` if none."""
    res = await db.execute(
        select(IdentityVerification)
        .where(IdentityVerification.user_id == current_user["user_id"])
        .order_by(desc(IdentityVerification.submitted_at))
        .limit(1)
    )
    v = res.scalar_one_or_none()
    if not v:
        return VerificationStatusOut(status="unsubmitted", can_resubmit=True)
    # A pending submission shouldn't be replaceable — would let a user
    # spam new ones and grow the queue.
    can_resubmit = v.status != VerificationStatus.PENDING
    return VerificationStatusOut(
        status=v.status.value,
        cni_number=_mask_cni(v.cni_number),
        submitted_at=v.submitted_at.isoformat() if v.submitted_at else None,
        reviewed_at=v.reviewed_at.isoformat() if v.reviewed_at else None,
        reviewer_notes=v.reviewer_notes,
        can_resubmit=can_resubmit,
    )


@router.post("/submit", status_code=201, response_model=VerificationStatusOut)
async def submit(
    cni_number:    str        = Form(..., min_length=3, max_length=40),
    cni_front:     UploadFile = File(...),
    cni_back:      UploadFile = File(...),
    selfie:        UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user_id = current_user["user_id"]
    cni = cni_number.strip()

    # Block resubmission while a previous one is still under review.
    existing = await db.execute(
        select(IdentityVerification)
        .where(IdentityVerification.user_id == user_id)
        .order_by(desc(IdentityVerification.submitted_at))
        .limit(1)
    )
    prev = existing.scalar_one_or_none()
    if prev and prev.status == VerificationStatus.PENDING:
        raise HTTPException(
            status_code=409,
            detail="A submission is already pending review",
        )
    if prev and prev.status == VerificationStatus.APPROVED:
        # Already verified — no need to resubmit.
        raise HTTPException(status_code=409, detail="Already verified")

    # Duplicate-CNI guard: a CNI number that's already been submitted by
    # a *different* user is locked out, regardless of that other user's
    # current status. Prevents two accounts claiming the same identity
    # and the "race to submit" trick of grabbing a known CNI.
    dup = await db.execute(
        select(IdentityVerification)
        .where(IdentityVerification.cni_number == cni)
        .where(IdentityVerification.user_id != user_id)
        .limit(1)
    )
    if dup.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=409,
            detail="This CNI is already linked to another account. "
                   "If this is a mistake, contact support.",
        )

    # Pre-allocate the ID so all three files land in the same dir.
    verification_id = uuidlib.uuid4()
    dest_dir = os.path.join(UPLOAD_ROOT, str(verification_id))

    front_path  = await _save_upload(cni_front, dest_dir, "front")
    back_path   = await _save_upload(cni_back,  dest_dir, "back")
    selfie_path = await _save_upload(selfie,    dest_dir, "selfie")

    # submitted_at is server-defaulted; we compute earliest_decision_at
    # from the same UTC clock so the gate is internally consistent even
    # if the DB clock drifts a bit.
    now = datetime.now(timezone.utc)
    row = IdentityVerification(
        id=verification_id,
        user_id=user_id,
        cni_number=cni,
        cni_front_path=front_path,
        cni_back_path=back_path,
        selfie_path=selfie_path,
        status=VerificationStatus.PENDING,
        submitted_at=now,
        earliest_decision_at=now + REVIEW_MIN_WAIT,
    )
    db.add(row)
    await db.flush()

    return VerificationStatusOut(
        status=row.status.value,
        cni_number=_mask_cni(row.cni_number),
        submitted_at=row.submitted_at.isoformat() if row.submitted_at else None,
        can_resubmit=False,
    )


# ─── Admin (reviewer) endpoints ───────────────────────────────
@router.get("/admin/pending", response_model=PendingListResponse)
async def list_pending(
    status: Optional[str] = None,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List submissions awaiting review. Pass `?status=approved` or
    `rejected` to inspect history."""
    await _require_reviewer(db, current_user)

    stmt = select(IdentityVerification)
    if status:
        try:
            target = VerificationStatus(status)
        except ValueError:
            raise HTTPException(status_code=400, detail="Unknown status filter")
        stmt = stmt.where(IdentityVerification.status == target)
    else:
        stmt = stmt.where(IdentityVerification.status == VerificationStatus.PENDING)
    stmt = stmt.order_by(IdentityVerification.submitted_at.asc())
    res = await db.execute(stmt)
    rows = list(res.scalars().all())

    users_by_id: dict[str, User] = {}
    if rows:
        u_res = await db.execute(
            select(User).where(User.id.in_([v.user_id for v in rows])))
        users_by_id = {str(u.id): u for u in u_res.scalars().all()}

    items: list[PendingVerificationOut] = []
    for v in rows:
        u = users_by_id.get(str(v.user_id))
        items.append(PendingVerificationOut(
            id=str(v.id), user_id=str(v.user_id),
            user_name=u.full_name if u else "Unknown",
            user_email=u.email if u else "",
            user_phone=u.phone if u else None,
            cni_number=v.cni_number,
            cni_front_url=_doc_url(str(v.id), "front"),
            cni_back_url=_doc_url(str(v.id), "back"),
            selfie_url=_doc_url(str(v.id), "selfie"),
            status=v.status.value,
            submitted_at=v.submitted_at.isoformat() if v.submitted_at else "",
            reviewed_at=v.reviewed_at.isoformat() if v.reviewed_at else None,
            reviewer_notes=v.reviewer_notes,
        ))
    return PendingListResponse(items=items)


@router.get(
    "/admin/{verification_id}/doc/{role}",
    include_in_schema=False,  # internal admin asset; not part of public docs
)
async def get_document(
    verification_id: str,
    role: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Serve one of the three uploaded documents to a reviewer."""
    await _require_reviewer(db, current_user)

    if role not in ("front", "back", "selfie"):
        raise HTTPException(status_code=404, detail="Unknown document role")

    res = await db.execute(
        select(IdentityVerification).where(IdentityVerification.id == verification_id)
    )
    v = res.scalar_one_or_none()
    if not v:
        raise HTTPException(status_code=404, detail="Verification not found")

    path = {
        "front":  v.cni_front_path,
        "back":   v.cni_back_path,
        "selfie": v.selfie_path,
    }[role]
    if not path or not os.path.exists(path):
        raise HTTPException(status_code=404, detail="File missing on disk")
    return FileResponse(path)


@router.post("/admin/{verification_id}/approve", response_model=VerificationStatusOut)
async def approve(
    verification_id: str,
    body: ReviewDecisionRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    reviewer = await _require_reviewer(db, current_user)

    res = await db.execute(
        select(IdentityVerification).where(IdentityVerification.id == verification_id)
    )
    v = res.scalar_one_or_none()
    if not v:
        raise HTTPException(status_code=404, detail="Verification not found")
    if v.status != VerificationStatus.PENDING:
        raise HTTPException(status_code=400, detail="Already reviewed")

    now = datetime.now(timezone.utc)
    if v.earliest_decision_at and now < v.earliest_decision_at:
        raise HTTPException(
            status_code=400,
            detail="Review minimum-wait period has not elapsed",
        )

    v.status         = VerificationStatus.APPROVED
    v.reviewer_id    = reviewer.id
    v.reviewer_notes = body.notes
    v.reviewed_at    = now

    # Flip the denormalised flag on the user so the hot-path gates can
    # read a single column without joining this table.
    u_res = await db.execute(select(User).where(User.id == v.user_id))
    user = u_res.scalar_one_or_none()
    if user:
        user.is_verified = True
    await db.flush()

    return VerificationStatusOut(
        status=v.status.value,
        cni_number=_mask_cni(v.cni_number),
        submitted_at=v.submitted_at.isoformat() if v.submitted_at else None,
        reviewed_at=v.reviewed_at.isoformat() if v.reviewed_at else None,
        reviewer_notes=v.reviewer_notes,
        can_resubmit=False,
    )


@router.post("/admin/{verification_id}/reject", response_model=VerificationStatusOut)
async def reject(
    verification_id: str,
    body: ReviewDecisionRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    reviewer = await _require_reviewer(db, current_user)

    res = await db.execute(
        select(IdentityVerification).where(IdentityVerification.id == verification_id)
    )
    v = res.scalar_one_or_none()
    if not v:
        raise HTTPException(status_code=404, detail="Verification not found")
    if v.status != VerificationStatus.PENDING:
        raise HTTPException(status_code=400, detail="Already reviewed")

    now = datetime.now(timezone.utc)
    if v.earliest_decision_at and now < v.earliest_decision_at:
        raise HTTPException(
            status_code=400,
            detail="Review minimum-wait period has not elapsed",
        )

    v.status         = VerificationStatus.REJECTED
    v.reviewer_id    = reviewer.id
    v.reviewer_notes = (body.notes or "").strip() or "Rejected without notes"
    v.reviewed_at    = now
    await db.flush()

    return VerificationStatusOut(
        status=v.status.value,
        cni_number=_mask_cni(v.cni_number),
        submitted_at=v.submitted_at.isoformat() if v.submitted_at else None,
        reviewed_at=v.reviewed_at.isoformat() if v.reviewed_at else None,
        reviewer_notes=v.reviewer_notes,
        can_resubmit=True,
    )
