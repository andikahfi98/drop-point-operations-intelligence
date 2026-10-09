from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
)

from pydantic import (
    BaseModel,
    Field,
)

from app.agents.operations_agent import (
    ask_operations_agent,
)
from app.api.internal_auth import require_internal_key


router = APIRouter(
    prefix="/api/agent",
    tags=["AI Agent"],
    dependencies=[Depends(require_internal_key)],
)


class AgentChatRequest(BaseModel):

    message: str = Field(
        min_length=1,
        max_length=2000,
    )


@router.post("/chat")
async def agent_chat(
    request: AgentChatRequest,
):

    try:

        answer = await ask_operations_agent(
            request.message
        )

        return {
            "message": request.message,
            "answer": answer,
        }

    except Exception as exc:

        raise HTTPException(
            status_code=500,
            detail=f"Agent failed: {str(exc)}",
        )
