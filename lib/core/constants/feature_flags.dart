/// Build-time feature flags.
///
/// Keep this file the single source of truth for "should this surface
/// even appear in the UI?" so disabling a feature is a one-line change.

/// CNI / identity verification flow.
/// Disabled while we redesign the review pipeline (the 2-day queue was
/// chasing users away). When this is `false`:
///   * the "Verify your identity" card on Profile is hidden
///   * the admin "ID Verification queue" drawer entry is hidden
///   * Njangi money actions skip the `is_verified` gate so users aren't
///     stuck behind a flow they can't complete
/// Backend `/api/v1/kyc/*` is also unregistered in `backend/main.py` while
/// this flag is off.
const bool kKycEnabled = false;
