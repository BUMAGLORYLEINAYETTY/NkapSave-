from unittest.mock import MagicMock, patch
import pytest
from services import momo_provider


# ── helpers ────────────────────────────────────────────────────────

def _mock_settings(monkeypatch):
    monkeypatch.setattr(momo_provider.settings, "CAMPAY_USERNAME", "user")
    monkeypatch.setattr(momo_provider.settings, "CAMPAY_PASSWORD", "pass")
    monkeypatch.setattr(momo_provider.settings, "CAMPAY_ENV", "sandbox")
    monkeypatch.setattr(momo_provider.settings, "DEFAULT_COUNTRY_CODE", "237")


def _ok_token_response():
    m = MagicMock()
    m.status_code = 200
    m.json.return_value = {"token": "tok123", "expires_in": 3300}
    return m


def _ok_transfer_response():
    m = MagicMock()
    m.status_code = 200
    m.json.return_value = {"reference": "ref-transfer-001"}
    return m


# ── transfer() tests ───────────────────────────────────────────────

def test_transfer_returns_reference(monkeypatch):
    """Happy path: transfer() returns the Campay reference string."""
    _mock_settings(monkeypatch)
    monkeypatch.setattr(momo_provider, "_token_cache", None)

    with patch("httpx.post") as mock_post:
        mock_post.side_effect = [_ok_token_response(), _ok_transfer_response()]
        ref = momo_provider.transfer(
            phone="670000000",
            amount=5000,
            external_id="ext-001",
            description="Test payout",
        )

    assert ref == "ref-transfer-001"
    transfer_call = mock_post.call_args_list[1]
    assert "/transfer/" in transfer_call.args[0]
    body = transfer_call.kwargs["json"]
    assert body["amount"] == "5000"
    assert body["to"] == "237670000000"
    assert body["external_reference"] == "ext-001"
    assert body["description"] == "Test payout"


def test_transfer_raises_on_4xx(monkeypatch):
    """Campay 4xx → MoMoApiError."""
    _mock_settings(monkeypatch)
    monkeypatch.setattr(momo_provider, "_token_cache", None)

    err_response = MagicMock()
    err_response.status_code = 400
    err_response.text = '{"message":"Bad request"}'

    with patch("httpx.post") as mock_post:
        mock_post.side_effect = [_ok_token_response(), err_response]
        with pytest.raises(momo_provider.MoMoApiError):
            momo_provider.transfer(
                phone="670000000", amount=100,
                external_id="ext-002", description="fail",
            )


def test_transfer_raises_when_reference_missing(monkeypatch):
    """Campay 200 but no 'reference' field → MoMoApiError."""
    _mock_settings(monkeypatch)
    monkeypatch.setattr(momo_provider, "_token_cache", None)

    bad_response = MagicMock()
    bad_response.status_code = 200
    bad_response.json.return_value = {}  # no "reference" key

    with patch("httpx.post") as mock_post:
        mock_post.side_effect = [_ok_token_response(), bad_response]
        with pytest.raises(momo_provider.MoMoApiError, match="missing 'reference'"):
            momo_provider.transfer(
                phone="670000000", amount=100,
                external_id="ext-003", description="fail",
            )


def test_transfer_raises_when_not_configured(monkeypatch):
    """Missing credentials → MoMoNotConfigured before any HTTP call."""
    monkeypatch.setattr(momo_provider.settings, "CAMPAY_USERNAME", None)
    monkeypatch.setattr(momo_provider.settings, "CAMPAY_PASSWORD", None)
    monkeypatch.setattr(momo_provider, "_token_cache", None)

    with pytest.raises(momo_provider.MoMoNotConfigured):
        momo_provider.transfer(
            phone="670000000", amount=100,
            external_id="ext-004", description="fail",
        )


def test_transfer_normalises_local_phone(monkeypatch):
    """9-digit local number is prefixed with country code."""
    _mock_settings(monkeypatch)
    monkeypatch.setattr(momo_provider, "_token_cache", None)

    with patch("httpx.post") as mock_post:
        mock_post.side_effect = [_ok_token_response(), _ok_transfer_response()]
        momo_provider.transfer(
            phone="670123456", amount=1000,
            external_id="ext-005", description="norm",
        )

    transfer_call = mock_post.call_args_list[1]
    assert transfer_call.kwargs["json"]["to"] == "237670123456"
