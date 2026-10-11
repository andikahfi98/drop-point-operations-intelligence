import asyncio
import importlib

from app.services import report_insights
from app.services.chat_router import detect_intent
from app.api import internal_report_routes


def sample_rows():
    return [
        {
            "drop_point_id": "DP-A",
            "drop_point_name": "DP A",
            "overall_status": "CRITICAL",
            "parcel_over_24h": 12,
            "mtd_on_time_rate_pct": 91.2,
            "delivery_sla_target_pct": 95,
            "mtd_overdue_delivery": 4,
            "revenue_gap_pct": -7.2,
            "watch_seller": 2,
            "critical_seller": 1,
        },
        {
            "drop_point_id": "DP-B",
            "drop_point_name": "DP B",
            "overall_status": "WATCH",
            "parcel_over_24h": 3,
            "mtd_on_time_rate_pct": 96,
            "delivery_sla_target_pct": 95,
            "mtd_overdue_delivery": 0,
            "revenue_gap_pct": 1.5,
            "watch_seller": 0,
            "critical_seller": 0,
        },
    ]


def test_daily_candidates_use_reported_metrics():
    candidates = report_insights.build_candidates(sample_rows(), "daily")
    by_id = {item["id"]: item for item in candidates}
    assert {"critical_dps", "parcel_aging", "delivery_sla", "revenue_pace", "seller_attention"} <= by_id.keys()
    assert "12 paket" in by_id["parcel_aging"]["insight"]
    assert "91.2% vs SLA 95.0%" in by_id["delivery_sla"]["insight"]
    assert "-7.2%" in by_id["revenue_pace"]["insight"]
    assert all("stok produk" not in item["action"].lower() for item in candidates)


def test_ai_selection_rejects_unknown_metrics_and_ids():
    candidates = report_insights.build_candidates(sample_rows(), "daily")
    content = '{"items":[{"id":"parcel_aging","action":"Kirim 200 paket besok."},{"id":"not_in_report","action":"Hubungi manager terkait."}]}'
    assert report_insights._parse_ai_selection(content, candidates) == []


def test_ai_selection_preserves_grounded_insight():
    candidates = report_insights.build_candidates(sample_rows(), "daily")
    content = '{"items":[{"id":"parcel_aging","action":"Tugaskan PIC terkait memeriksa antrean paket tertua."}]}'
    selected = report_insights._parse_ai_selection(content, candidates)
    assert selected[0]["insight"] == next(item["insight"] for item in candidates if item["id"] == "parcel_aging")


def test_report_falls_back_if_provider_fails(monkeypatch):
    async def unavailable(*_args):
        raise TimeoutError("provider unavailable")

    monkeypatch.setattr(report_insights, "_rank_with_ai", unavailable)
    result = asyncio.run(report_insights.analyze_report(sample_rows(), "daily"))
    assert result["mode"] == "rules_fallback"
    assert len(result["items"]) == 3
    assert all(item["insight"] and item["action"] for item in result["items"])


def test_empty_report_skips_ai(monkeypatch):
    async def should_not_run(*_args):
        raise AssertionError("AI should not run without data")

    monkeypatch.setattr(report_insights, "_rank_with_ai", should_not_run)
    assert asyncio.run(report_insights.analyze_report([], "intraday")) == {"mode": "no_data", "items": []}


def test_watch_status_is_not_described_as_normal():
    rows = [{"drop_point_id": "DP-B", "drop_point_name": "DP B", "overall_status": "WATCH"}]
    candidates = report_insights.build_candidates(rows, "intraday")
    assert candidates[0]["id"] == "watch_dps"
    assert "WATCH" in candidates[0]["insight"]


def test_telegram_report_insight_intent_and_reply():
    assert detect_intent("Beri insight dan solusi dari laporan harian") == "report_insight"
    analysis = {"mode": "rules_fallback", "items": [{
        "insight": "DP B memiliki paket tertahan.",
        "action": "Minta PIC Outbound memeriksa antrean tertua.",
    }]}
    answer = report_insights.format_report_analysis(
        analysis, period="daily", scope="DP B", business_date="2026-10-10",
    )
    assert answer.startswith("📊 Analisis Laporan Harian\nData: 10 Oktober 2026 (simulasi)\nCakupan: DP B")
    assert "Temuan: DP B memiliki paket tertahan." in answer
    assert "Langkah: Minta PIC Outbound" in answer
    assert "prioritas memakai aturan" in answer


def test_telegram_ai_reply_uses_clear_sections_and_full_dp_names():
    rows = [
        {"drop_point_name": "Drop Point Tangerang", "overall_status": "CRITICAL"},
        {"drop_point_name": "Drop Point Bekasi", "overall_status": "CRITICAL"},
        {"drop_point_name": "Drop Point Depok", "overall_status": "CRITICAL"},
    ]
    candidate = next(item for item in report_insights.build_candidates(rows, "daily") if item["id"] == "critical_dps")
    answer = report_insights.format_report_analysis(
        {"mode": "ai", "items": [candidate]},
        period="daily", scope="3 DP dalam akses regional", business_date="2026-10-13",
    )
    assert "Cakupan: 3 DP dalam akses regional" in answer
    assert "1. Status kritis\nTemuan:" in answer
    assert "Drop Point Tangerang, Drop Point Bekasi, Drop Point Depok" in answer
    assert "DP lain" not in answer
    assert "Langkah:" in answer
    assert "prioritas dipilih AI" in answer


def test_internal_report_keeps_existing_shape_unless_requested(monkeypatch):
    report = {"count": 1, "data": sample_rows()[:1]}
    monkeypatch.setattr(internal_report_routes, "get_summary", lambda: report.copy())

    async def fake_analysis(rows, period):
        assert rows == report["data"]
        assert period == "intraday"
        return {"mode": "rules_fallback", "items": []}

    monkeypatch.setattr(internal_report_routes, "analyze_report", fake_analysis)
    plain = asyncio.run(internal_report_routes.intraday_summary())
    enriched = asyncio.run(internal_report_routes.intraday_summary(include_insights=True))
    assert "analysis" not in plain
    assert enriched["analysis"]["mode"] == "rules_fallback"


def test_telegram_report_analysis_filters_to_regional_grants(monkeypatch):
    monkeypatch.setenv("LLM_API_KEY", "test-only-key")
    chat_service = importlib.import_module("app.services.chat_service")
    monkeypatch.setattr(chat_service, "regional_telegram_scope", lambda _chat_id: [{"drop_point_id": "DP-A"}])
    monkeypatch.setattr(chat_service, "ensure_session", lambda _chat_id: None)
    monkeypatch.setattr(chat_service, "get_session", lambda _chat_id: {"current_drop_point_id": None})
    monkeypatch.setattr(chat_service, "update_current_drop_point", lambda *_args: None)
    monkeypatch.setattr(chat_service, "resolve_drop_points", lambda _message: [])
    monkeypatch.setattr(chat_service, "get_daily_operational_report", lambda: {
        "business_date": "2026-10-10", "data": [
            {"drop_point_id": "DP-A", "drop_point_name": "DP A", "overall_status": "WATCH"},
            {"drop_point_id": "DP-B", "drop_point_name": "DP B", "overall_status": "CRITICAL"},
        ],
    })

    async def fake_analysis(rows, period):
        assert period == "daily"
        assert [row["drop_point_id"] for row in rows] == ["DP-A"]
        return {"mode": "rules_fallback", "items": [{
            "insight": "DP A berstatus WATCH.",
            "action": "Minta manager memeriksa komponen terkait.",
        }]}

    monkeypatch.setattr(chat_service, "analyze_report", fake_analysis)
    monkeypatch.setattr(chat_service, "save_message", lambda *_args: None)
    monkeypatch.setattr(chat_service, "update_last_topic", lambda *_args: None)
    result = asyncio.run(chat_service.fast_chat(1, "Beri insight dan solusi dari laporan harian"))
    assert result["mode"] == "report_insight"
    assert "Cakupan: DP A" in result["answer"]
    assert "DP A berstatus WATCH" in result["answer"]
    assert "DP B" not in result["answer"]
