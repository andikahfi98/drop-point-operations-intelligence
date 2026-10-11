"""Report data for trusted local n8n workflows."""

from fastapi import APIRouter, Depends

from app.api.internal_auth import require_internal_key
from app.services.operational_service import get_daily_operational_report, get_summary
from app.services.report_insights import analyze_report


router = APIRouter(
    prefix="/internal/reports",
    tags=["Internal reports"],
    dependencies=[Depends(require_internal_key)],
)


@router.get("/summary")
async def intraday_summary(include_insights: bool = False):
    report = get_summary()
    if include_insights:
        report["analysis"] = await analyze_report(report["data"], "intraday")
    return report


@router.get("/daily")
async def scheduled_daily_report(include_insights: bool = False):
    report = get_daily_operational_report()
    if include_insights:
        report["analysis"] = await analyze_report(report["data"], "daily")
    return report
