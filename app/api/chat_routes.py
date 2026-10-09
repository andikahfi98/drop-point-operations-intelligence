from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
)

from pydantic import (
    BaseModel,
    Field,
)

from app.services.chat_service import (
    fast_chat,
)
from app.api.internal_auth import require_internal_key


router = APIRouter(
    prefix="/api",
    tags=["Conversation"],
    dependencies=[Depends(require_internal_key)],
)


class ChatRequest(BaseModel):

    chat_id: int

    message: str = Field(
        min_length=1,
        max_length=2000,
    )


@router.post("/chat")
async def chat(
    request: ChatRequest,
):

    try:

        return await fast_chat(
            chat_id=request.chat_id,
            message=request.message,
        )

    except Exception as exc:

        raise HTTPException(
            status_code=500,
            detail=f"Chat failed: {str(exc)}",
        )
