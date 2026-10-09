"""Report data for trusted local n8n workflows."""

from fastapi import APIRouter, Depends

from app.api.internal_auth import require_internal_key
from app.services.operational_service import get_daily_operational_report, get_summary


router = APIRouter(
    prefix="/internal/reports",
    tags=["Internal reports"],
    dependencies=[Depends(require_internal_key)],
)


@router.get("/summary")
def intraday_summary():
    return get_summary()


@router.get("/daily")
def scheduled_daily_report():
    return get_daily_operational_report()
