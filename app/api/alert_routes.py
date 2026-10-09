import os

from fastapi import (
    APIRouter,
    Header,
    HTTPException,
)

from app.services.alert_service import (
    evaluate_critical_alerts,
)


router = APIRouter(
    prefix="/internal/alerts",
    tags=["Alerts"],
)


@router.post("/evaluate")
def evaluate_alerts(
    x_internal_key: str | None = Header(
        default=None
    ),
):

    expected_key = os.getenv(
        "SIMULATION_API_KEY"
    )

    if (
        not expected_key
        or x_internal_key != expected_key
    ):
        raise HTTPException(
            status_code=401,
            detail="Invalid internal key",
        )

    return evaluate_critical_alerts()