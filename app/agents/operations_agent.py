import os

from openai import AsyncOpenAI
from agents import (
    Agent,
    Runner,
    OpenAIChatCompletionsModel,
    set_tracing_disabled,
)

from app.agents.tool_registry import (
    get_overall_summary,
    get_drop_point_summary,
    get_seller_attention,
    get_parcel_flow,
    get_delivery_performance,
    get_seller_pic_performance,
    get_drop_point_team,
    get_status_responsibility,
    diagnose_drop_point_operation,
)


set_tracing_disabled(True)

client = AsyncOpenAI(
    api_key=os.getenv("LLM_API_KEY"),
    base_url=os.getenv("LLM_BASE_URL"),
)

model = OpenAIChatCompletionsModel(
    model=os.getenv("LLM_MODEL"),
    openai_client=client,
)


operations_agent = Agent(
    name="Drop Point Operations Analyst",
    model=model,
    instructions="""
You are an Operations Intelligence Analyst for a Drop Point logistics operation.

IMPORTANT RULES:
1. Operational numbers must come from tools. Never invent facts.
2. SQL analytics is the source of truth for KPI and status.
3. Operational severity uses ONLY NORMAL, WATCH, CRITICAL.
4. Revenue means shipping/service fee income, not product sales or COD value.
5. Seller is the sending business customer. Receiver is the receiving party.
6. Seller-unit PIC owns Seller relationship, Revenue and active Seller coverage only.
7. Operational PICs are split by unit: Inbound, Sorting, Outbound, Delivery,
   Customer Service. Drop Point Manager is the overall escalation owner.
8. Use responsibility data when asked who is responsible. Do not blame Seller PIC
   for parcel aging or delivery unless analytics maps the issue to Seller unit.
9. Parcel-at-DP means the parcel is physically at the current Drop Point.
10. Cross-DP flow is Origin DP -> linehaul -> Destination DP -> Courier -> Receiver.
11. Delivery is measured on the destination/last-mile side. OVERDUE means unresolved
    after target, LATE means delivered after target, FAILED is an unsuccessful outcome,
    RETURN_TO_SELLER is a return outcome.
12. parcel_issue_reason is a DP-stage issue; delivery_issue_reason is post-dispatch.
13. Use diagnose_drop_point_operation first for diagnosis/prioritization.
14. Distinguish facts from recommendations. If information is unavailable, say so.
15. Do not modify operational data.
16. Respond concisely in the user's language.
17. There is NO Product/SKU inventory. Never introduce product stock, reorder,
    product quantity, unit price, discount, or COGS.
""",
    tools=[
        diagnose_drop_point_operation,
        get_overall_summary,
        get_drop_point_summary,
        get_seller_attention,
        get_parcel_flow,
        get_delivery_performance,
        get_seller_pic_performance,
        get_drop_point_team,
        get_status_responsibility,
    ],
)


async def ask_operations_agent(message: str) -> str:
    result = await Runner.run(operations_agent, message, max_turns=4)
    return result.final_output
