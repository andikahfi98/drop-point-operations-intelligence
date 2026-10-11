import json
import os
import re
import time

from openai import AsyncOpenAI
from sqlalchemy import text

from app.db.database import engine
from app.agents.operations_tools import diagnose_drop_point, overall_summary
from app.api.auth_routes import Principal, allowed_drop_points
from app.services.chat_router import detect_intent, build_direct_answer
from app.services.operational_service import get_summary, get_daily_operational_report
from app.services.report_insights import analyze_report, format_report_analysis


client = AsyncOpenAI(
    api_key=os.getenv("LLM_API_KEY"),
    base_url=os.getenv("LLM_BASE_URL"),
    timeout=90.0,
)

FAST_MODEL = os.getenv("LLM_FAST_MODEL", os.getenv("LLM_MODEL"))


def ensure_session(chat_id: int):
    with engine.begin() as connection:
        connection.execute(
            text("""
                INSERT INTO app.chat_session (chat_id)
                VALUES (:chat_id)
                ON CONFLICT (chat_id) DO NOTHING;
            """),
            {"chat_id": chat_id},
        )


def get_session(chat_id: int):
    with engine.connect() as connection:
        row = connection.execute(
            text("""
                SELECT chat_id, current_drop_point_id, last_topic
                FROM app.chat_session
                WHERE chat_id = :chat_id;
            """),
            {"chat_id": chat_id},
        ).mappings().one()
    return dict(row)


def update_current_drop_point(chat_id: int, drop_point_id: str | None):
    with engine.begin() as connection:
        connection.execute(
            text("""
                UPDATE app.chat_session
                SET current_drop_point_id = :drop_point_id,
                    updated_at = NOW()
                WHERE chat_id = :chat_id;
            """),
            {"chat_id": chat_id, "drop_point_id": drop_point_id},
        )


def update_last_topic(chat_id: int, last_topic: str):
    with engine.begin() as connection:
        connection.execute(
            text("""
                UPDATE app.chat_session
                SET last_topic = :last_topic,
                    updated_at = NOW()
                WHERE chat_id = :chat_id;
            """),
            {"chat_id": chat_id, "last_topic": last_topic},
        )


def get_recent_history(chat_id: int, limit: int = 4):
    with engine.connect() as connection:
        rows = connection.execute(
            text("""
                SELECT role, message
                FROM (
                    SELECT message_id, role, message
                    FROM app.chat_message
                    WHERE chat_id = :chat_id
                    ORDER BY message_id DESC
                    LIMIT :limit
                ) x
                ORDER BY message_id;
            """),
            {"chat_id": chat_id, "limit": limit},
        ).mappings().all()

    history = []
    for row in rows:
        role = row["role"]
        message = row["message"] or ""
        max_chars = 1200 if role == "assistant" else 600
        if len(message) > max_chars:
            message = message[:max_chars] + "..."
        history.append({"role": role, "content": message})
    return history


def save_message(chat_id: int, role: str, message: str):
    with engine.begin() as connection:
        connection.execute(
            text("""
                INSERT INTO app.chat_message (chat_id, role, message)
                VALUES (:chat_id, :role, :message);
            """),
            {"chat_id": chat_id, "role": role, "message": message},
        )


def resolve_drop_points(message: str):
    normalized = message.lower().replace("drop point", "").strip()
    with engine.connect() as connection:
        rows = connection.execute(
            text("""
                SELECT drop_point_id, drop_point_name
                FROM core.dim_drop_point
                WHERE UPPER(status) = 'ACTIVE';
            """)
        ).mappings().all()

    matches = []
    for row in rows:
        dp_id = row["drop_point_id"].lower()
        dp_name = row["drop_point_name"].lower().replace("drop point", "").strip()
        if dp_id in normalized or dp_name in normalized:
            matches.append(row["drop_point_id"])
    return matches


def _pick(source: dict | None, keys: list[str]):
    if not source:
        return {}
    return {key: source.get(key) for key in keys if key in source}


def compact_diagnosis(diagnosis: dict, message: str):
    if not diagnosis or diagnosis.get("error"):
        return diagnosis or {}

    dp = diagnosis.get("drop_point", {})
    compact = {
        "drop_point": _pick(
            dp,
            [
                "drop_point_id", "drop_point_name", "region", "area",
                "manager_staff_id", "manager_name", "overall_status",
                "revenue", "revenue_target", "revenue_achievement_pct",
                "expected_achievement_pct", "revenue_gap_pct", "revenue_status",
                "active_seller", "active_seller_target",
                "active_seller_achievement_pct", "normal_seller", "watch_seller",
                "critical_seller", "seller_status", "parcel_in_mtd",
                "parcel_out_mtd", "parcel_at_dp", "parcel_under_6h",
                "parcel_6_12h", "parcel_12_24h", "parcel_over_24h",
                "oldest_parcel_hours", "avg_dp_hours", "parcel_out_pct",
                "parcel_status", "total_shipment", "completed_delivery",
                "in_transit_delivery", "successful_delivery", "on_time_delivery",
                "late_delivery", "failed_delivery", "returned_delivery",
                "overdue_delivery", "on_time_rate_pct",
                "delivery_sla_target_pct", "delivery_sla_gap_pct", "delivery_status",
            ],
        )
    }

    parcel = diagnosis.get("parcel")
    if isinstance(parcel, dict):
        compact["parcel"] = _pick(
            parcel,
            [
                "parcel_in_mtd", "parcel_out_mtd", "parcel_in_today",
                "parcel_out_today", "parcel_at_dp", "parcel_under_6h",
                "parcel_6_12h", "parcel_12_24h", "parcel_over_24h",
                "oldest_parcel_hours", "avg_dp_hours", "parcel_out_pct",
                "parcel_over_24h_pct", "parcel_status",
            ],
        )

    parcel_issues = []
    for row in diagnosis.get("top_parcel_issues", [])[:3]:
        parcel_issues.append(
            _pick(
                row,
                [
                    "shipment_id", "seller_name", "seller_pic_name", "shipment_status",
                    "issue_type", "parcel_issue_reason", "issue_hours",
                    "responsible_unit_name", "responsible_staff_name", "manager_name",
                ],
            )
        )
    if parcel_issues:
        compact["top_parcel_issues"] = parcel_issues

    delivery_issues = []
    for row in diagnosis.get("top_delivery_issues", [])[:3]:
        delivery_issues.append(
            _pick(
                row,
                [
                    "shipment_id", "seller_name", "receiver_name", "receiver_area",
                    "courier_name", "shipment_status", "issue_type",
                    "delivery_issue_reason", "issue_hours", "target_delivery_ts",
                    "actual_delivery_ts", "returned_ts", "responsible_unit_name",
                    "responsible_staff_name", "manager_name",
                ],
            )
        )
    if delivery_issues:
        compact["top_delivery_issues"] = delivery_issues

    problem_sellers = []
    for row in diagnosis.get("top_problem_sellers", [])[:3]:
        problem_sellers.append(
            _pick(
                row,
                [
                    "seller_name", "seller_pic_name", "attention_status",
                    "activity_status", "days_since_last_transaction",
                    "current_month_transaction", "current_month_revenue",
                ],
            )
        )
    if problem_sellers:
        compact["problem_sellers"] = problem_sellers

    problem_pics = []
    for row in diagnosis.get("top_problem_seller_pics", [])[:3]:
        problem_pics.append(
            _pick(
                row,
                [
                    "staff_name", "pic_status", "revenue", "revenue_target",
                    "revenue_achievement_pct", "expected_achievement_pct",
                    "revenue_gap_pct", "active_seller", "active_seller_target",
                ],
            )
        )
    if problem_pics:
        compact["problem_seller_pics"] = problem_pics

    responsibility = []
    for row in diagnosis.get("responsibility", [])[:4]:
        responsibility.append(
            _pick(
                row,
                [
                    "component", "status", "responsible_unit_code",
                    "responsible_unit_name", "responsible_staff_id",
                    "responsible_staff_name", "manager_staff_id", "manager_name",
                ],
            )
        )
    if responsibility:
        compact["responsibility"] = responsibility

    manager = diagnosis.get("manager")
    if manager:
        compact["manager"] = manager

    return compact


def compact_overall_summary(summary: dict):
    if not isinstance(summary, dict):
        return summary

    compact_rows = []
    for row in summary.get("data", []):
        compact_rows.append(
            _pick(
                row,
                [
                    "drop_point_id", "drop_point_name", "manager_name", "overall_status",
                    "revenue_achievement_pct", "expected_achievement_pct",
                    "revenue_gap_pct", "revenue_status", "normal_seller",
                    "watch_seller", "critical_seller", "seller_status",
                    "parcel_at_dp", "parcel_over_24h", "oldest_parcel_hours",
                    "parcel_status", "completed_delivery", "in_transit_delivery",
                    "returned_delivery", "overdue_delivery", "on_time_rate_pct",
                    "delivery_sla_target_pct", "delivery_status",
                ],
            )
        )
    return {"count": len(compact_rows), "data": compact_rows}


def build_context(message: str, session: dict, explicit_dp: list[str] | None = None,
                  allowed_ids: set[str] | None = None):
    if explicit_dp is None:
        explicit_dp = resolve_drop_points(message)
    if allowed_ids is not None:
        explicit_dp = [dp for dp in explicit_dp if dp in allowed_ids]

    if explicit_dp:
        contexts = [
            compact_diagnosis(diagnose_drop_point(dp), message)
            for dp in explicit_dp[:2]
        ]
        return {
            "type": "drop_point",
            "drop_point_ids": explicit_dp[:2],
            "data": contexts,
        }

    current_dp = session.get("current_drop_point_id")
    if current_dp and (allowed_ids is None or current_dp in allowed_ids):
        return {
            "type": "drop_point",
            "drop_point_ids": [current_dp],
            "data": [compact_diagnosis(diagnose_drop_point(current_dp), message)],
        }

    summary = overall_summary()
    if allowed_ids is not None:
        summary = {"data": [row for row in summary.get("data", [])
                            if row["drop_point_id"] in allowed_ids]}
    return {"type": "overall", "data": compact_overall_summary(summary)}


def regional_telegram_scope(chat_id: int) -> list[dict] | None:
    permitted = {item.strip() for item in os.getenv("TELEGRAM_REGIONAL_CHAT_IDS", "").split(",") if item.strip()}
    if str(chat_id) not in permitted:
        return None
    user_id = os.getenv("TELEGRAM_REGIONAL_USER_ID", "").strip()
    if not user_id:
        return None
    with engine.connect() as connection:
        row = connection.execute(text("""
            SELECT u.user_id, u.full_name, u.email, u.role_code,
                   r.data_scope, u.staff_id, u.must_change_password
            FROM app.app_user u
            JOIN app.app_role r ON r.role_code = u.role_code
            WHERE u.user_id = :user_id AND u.status = 'ACTIVE'
              AND u.role_code = 'REGIONAL_MANAGER' AND r.is_active = TRUE
              AND u.must_change_password = FALSE
        """), {"user_id": user_id}).mappings().first()
    if row is None:
        return None
    return allowed_drop_points(Principal(**dict(row), token_hash=""))


async def fast_chat(chat_id: int, message: str):
    allowed = regional_telegram_scope(chat_id)
    if allowed is None:
        return {"mode": "access_denied", "chat_id": chat_id,
                "answer": "Chat ini tidak terdaftar untuk akses Regional Manager."}
    allowed_ids = {row["drop_point_id"] for row in allowed}
    if not allowed_ids:
        return {"mode": "access_denied", "chat_id": chat_id,
                "answer": "Akun Regional Manager belum memiliki akses Drop Point aktif."}
    ensure_session(chat_id)
    session = get_session(chat_id)
    started_at = time.perf_counter()

    intent = detect_intent(message)
    explicit_dp = resolve_drop_points(message)
    denied = [dp for dp in explicit_dp if dp not in allowed_ids]
    if denied:
        return {"mode": "access_denied", "chat_id": chat_id,
                "answer": "Drop Point tersebut di luar akses akun Anda. Saya hanya dapat menampilkan data yang ditugaskan kepada Anda."}

    if session.get("current_drop_point_id") not in allowed_ids:
        update_current_drop_point(chat_id, None)
        session["current_drop_point_id"] = None

    if len(explicit_dp) == 1:
        update_current_drop_point(chat_id, explicit_dp[0])
        session["current_drop_point_id"] = explicit_dp[0]

    if intent == "report_insight":
        period = "daily" if any(term in message.lower() for term in ("harian", "hari ini", "daily")) else "intraday"
        report = get_daily_operational_report() if period == "daily" else get_summary()
        selected_ids = set(explicit_dp) if explicit_dp else allowed_ids
        rows = [row for row in report.get("data", []) if row["drop_point_id"] in selected_ids]
        if len(selected_ids) == 1 and rows:
            scope = rows[0]["drop_point_name"]
        elif explicit_dp:
            scope = f"{len(rows)} DP yang dipilih"
        else:
            scope = f"{len(rows)} DP dalam akses regional"
        analysis = await analyze_report(rows, period)
        answer = format_report_analysis(
            analysis, period=period, scope=scope,
            business_date=report.get("business_date") if period == "daily" else None,
        )
        save_message(chat_id, "user", message)
        save_message(chat_id, "assistant", answer)
        update_last_topic(chat_id, intent)
        return {
            "mode": "report_insight",
            "intent": intent,
            "chat_id": chat_id,
            "current_drop_point_id": session.get("current_drop_point_id"),
            "answer": answer,
            "analysis_mode": analysis["mode"],
            "timing_ms": {"total": round((time.perf_counter() - started_at) * 1000, 2)},
        }

    direct_drop_point_id = None if len(explicit_dp) > 1 else session.get("current_drop_point_id")

    direct_started = time.perf_counter()
    direct_answer = build_direct_answer(intent=intent, drop_point_id=direct_drop_point_id,
                                        allowed_ids=allowed_ids)
    direct_ms = round((time.perf_counter() - direct_started) * 1000, 2)

    if direct_answer:
        save_message(chat_id, "user", message)
        save_message(chat_id, "assistant", direct_answer)
        update_last_topic(chat_id, intent)
        return {
            "mode": "direct_fast",
            "intent": intent,
            "chat_id": chat_id,
            "current_drop_point_id": session.get("current_drop_point_id"),
            "answer": direct_answer,
            "timing_ms": {
                "direct": direct_ms,
                "total": round((time.perf_counter() - started_at) * 1000, 2),
            },
        }

    context_started = time.perf_counter()
    context = build_context(message, session, explicit_dp=explicit_dp,
                            allowed_ids=allowed_ids)
    context_ms = round((time.perf_counter() - context_started) * 1000, 2)
    history = get_recent_history(chat_id, limit=4)

    system_prompt = """
You are an Operations Intelligence Assistant for a Drop Point logistics operation.
Use CURRENT OPERATIONAL CONTEXT as the only source of operational facts.

Rules:
1. Status comes from analytics. Use only NORMAL, WATCH, CRITICAL.
2. Revenue is shipping/service fee income, not product sales or COD value.
3. Seller is the sending business customer. Receiver is the receiving party.
4. Seller-unit PIC owns Revenue and active Seller coverage only.
5. Operational responsibility is unit based: Inbound, Sorting, Outbound, Delivery,
   Customer Service. Drop Point Manager is the overall escalation owner.
6. When asked who is responsible, use the responsibility mapping in context.
7. Parcel-at-DP means physically at the current Drop Point. Cross-DP flow is
   Origin DP -> linehaul -> Destination DP -> Courier -> Receiver.
8. Delivery is destination/last-mile performance. OVERDUE is unresolved after target;
   LATE is delivered after target; FAILED is unsuccessful; RETURN_TO_SELLER is returned.
9. parcel_issue_reason and delivery_issue_reason belong to different stages. Do not mix them.
10. Explain with actual counts and targets when available. Do not recalculate severity.
11. Remember the current Drop Point and recent conversation.
12. There is NO Product/SKU inventory. Never introduce product stock, reorder,
    product quantity, unit price, discount, or COGS.
13. If information is missing, say so. Answer in the user's language and stay concise.
14. The context has already been restricted to the authorized Regional Manager account. Never
    describe, infer, or request information from a Drop Point outside that scope.
15. Reply as plain text for Telegram: no Markdown tables, HTML tags, or formatting markers.
    Keep the full reply below 3000 characters.
16. The 95% delivery SLA applies to on-time rate. Do not compare delivery success rate
    with that SLA unless a separate success-rate target is explicitly present.
17. Refer to parcels physically at a DP, never as product stock or inventory.
"""

    messages = [
        {"role": "system", "content": system_prompt},
        *history,
        {
            "role": "system",
            "content": "CURRENT OPERATIONAL CONTEXT:\n" + json.dumps(
                context,
                ensure_ascii=False,
                default=str,
                separators=(",", ":"),
            ),
        },
        {"role": "user", "content": message},
    ]

    llm_started = time.perf_counter()
    response = await client.chat.completions.create(
        model=FAST_MODEL,
        messages=messages,
        max_tokens=2048,
        reasoning_effort="low",
    )
    llm_ms = round((time.perf_counter() - llm_started) * 1000, 2)

    choice = response.choices[0]
    content = choice.message.content
    answer = content.strip() if isinstance(content, str) else ""
    answer = re.sub(r"\*\*(.*?)\*\*", r"\1", answer, flags=re.DOTALL)
    if not answer:
        answer = "Respons AI kosong. Silakan ulangi pertanyaan atau coba beberapa detik lagi."

    save_message(chat_id, "user", message)
    save_message(chat_id, "assistant", answer)
    update_last_topic(chat_id, intent)

    return {
        "mode": "llm_fast",
        "intent": intent,
        "chat_id": chat_id,
        "current_drop_point_id": session.get("current_drop_point_id"),
        "answer": answer,
        "finish_reason": choice.finish_reason,
        "timing_ms": {
            "context": context_ms,
            "llm": llm_ms,
            "total": round((time.perf_counter() - started_at) * 1000, 2),
        },
    }
