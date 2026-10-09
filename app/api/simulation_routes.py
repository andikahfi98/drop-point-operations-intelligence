import os

from fastapi import (
    APIRouter,
    Header,
    HTTPException,
)

from app.services.simulation_service import (
    execute_simulation,
    get_simulation_state,
)


router = APIRouter(
    prefix="/internal/simulation",
    tags=["Simulation"],
)


def validate_internal_key(
    x_internal_key: str | None,
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


@router.get("/state")
def simulation_state():

    return get_simulation_state()


@router.post("/run")
def simulation_run(
    x_internal_key: str | None = Header(
        default=None
    ),
):

    validate_internal_key(
        x_internal_key
    )

    try:
        return execute_simulation()

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Simulation failed: {str(exc)}",
        )