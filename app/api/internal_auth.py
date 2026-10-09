"""Shared key check for trusted local automation callers."""

import hmac
import os

from fastapi import Header, HTTPException


def require_internal_key(x_internal_key: str | None = Header(default=None)) -> None:
    expected = os.getenv("SIMULATION_API_KEY")
    if not expected or not x_internal_key or not hmac.compare_digest(x_internal_key, expected):
        raise HTTPException(status_code=401, detail="Invalid internal key")
