"""Rank evidence-backed insights and suggested actions for scheduled reports."""

import asyncio
import json
import logging
import os
import re

from openai import AsyncOpenAI


logger = logging.getLogger(__name__)

_BAD_ACTION_TERMS = re.compile(r"\b(?:stok|sku|diskon|cogs|harga kompetitor)\b", re.I)


def _number(value) -> float | None:
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def _integer(value) -> int:
    number = _number(value)
    return max(0, int(number)) if number is not None else 0


def _count(value) -> str:
    return f"{value:,}".replace(",", ".")


def _percent(value) -> str:
    return f"{value:.1f}%"


def _name(row) -> str:
    return str(row.get("drop_point_name") or row.get("drop_point_id") or "Drop Point")


def _names(rows) -> str:
    names = [_name(row) for row in rows[:2]]
    if len(rows) > 2:
        names.append(f"{len(rows) - 2} DP lain")
    return ", ".join(names)


def build_candidates(rows: list[dict], period: str) -> list[dict]:
    """Only report observed signals; an absent metric never becomes zero."""
    if period not in {"intraday", "daily"}:
        raise ValueError("Unsupported report period")
    if not rows:
        return []

    candidates = []
    critical = [row for row in rows if row.get("overall_status") == "CRITICAL"]
    if critical:
        candidates.append({
            "id": "critical_dps",
            "score": 80 + len(critical),
            "insight": f"{_count(len(critical))} DP berstatus CRITICAL: {_names(critical)}.",
            "action": "Minta DP Manager meninjau komponen berstatus CRITICAL dan menetapkan PIC serta tenggat tindak lanjut.",
        })

    watch = [row for row in rows if row.get("overall_status") == "WATCH"]
    if watch:
        candidates.append({
            "id": "watch_dps",
            "score": 30 + len(watch),
            "insight": f"{_count(len(watch))} DP berstatus WATCH: {_names(watch)}.",
            "action": "Minta DP Manager meninjau komponen berstatus WATCH dan mencatat tindak lanjut sebelum status memburuk.",
        })

    aging = sorted(
        [row for row in rows if _integer(row.get("parcel_over_24h")) > 0],
        key=lambda row: _integer(row.get("parcel_over_24h")),
        reverse=True,
    )
    if aging:
        top = aging[0]
        candidates.append({
            "id": "parcel_aging",
            "score": 70 + min(len(aging), 6),
            "insight": (
                f"{_count(len(aging))} DP memiliki paket tertahan >24 jam; "
                f"terbanyak di {_name(top)} ({_count(_integer(top.get('parcel_over_24h')))} paket)."
            ),
            "action": "Periksa antrean paket tertua dan hambatan proses di DP terkait, lalu eskalasi ke PIC unit yang bertanggung jawab.",
        })

    rate_key = "mtd_on_time_rate_pct" if period == "daily" else "on_time_rate_pct"
    overdue_key = "mtd_overdue_delivery" if period == "daily" else "overdue_delivery"
    delivery = []
    for row in rows:
        rate = _number(row.get(rate_key))
        target = _number(row.get("delivery_sla_target_pct"))
        overdue = _integer(row.get(overdue_key))
        if (rate is not None and target is not None and rate < target) or overdue > 0:
            delivery.append((row, rate, target, overdue))
    if delivery:
        delivery.sort(key=lambda item: (item[2] - item[1] if item[1] is not None and item[2] is not None else 0, item[3]), reverse=True)
        row, rate, target, overdue = delivery[0]
        metrics = []
        if rate is not None and target is not None:
            metrics.append(f"on-time {_percent(rate)} vs SLA {_percent(target)}")
        if overdue:
            metrics.append(f"{_count(overdue)} overdue")
        candidates.append({
            "id": "delivery_sla",
            "score": 68 + min(len(delivery), 6),
            "insight": f"Pengiriman perlu perhatian di {_count(len(delivery))} DP; {_name(row)} mencatat {' dan '.join(metrics)}.",
            "action": "Prioritaskan shipment overdue, lalu telusuri penyebab keterlambatan bersama PIC Delivery dan kurir terkait.",
        })

    revenue = sorted(
        [row for row in rows if (_number(row.get("revenue_gap_pct")) or 0) < 0],
        key=lambda row: _number(row.get("revenue_gap_pct")) or 0,
    )
    if revenue:
        top = revenue[0]
        gap = _number(top.get("revenue_gap_pct"))
        candidates.append({
            "id": "revenue_pace",
            "score": 50 + min(len(revenue), 6),
            "insight": f"Pendapatan tertinggal dari pace di {_count(len(revenue))} DP; gap terbesar {_name(top)} ({_percent(gap)}).",
            "action": "Minta PIC Seller meninjau kontribusi seller aktif dan rencana pemulihan pendapatan ongkir di DP terkait.",
        })

    sellers = sorted(
        [row for row in rows if _integer(row.get("watch_seller")) + _integer(row.get("critical_seller")) > 0],
        key=lambda row: _integer(row.get("watch_seller")) + _integer(row.get("critical_seller")),
        reverse=True,
    )
    if sellers:
        top = sellers[0]
        affected = _integer(top.get("watch_seller")) + _integer(top.get("critical_seller"))
        candidates.append({
            "id": "seller_attention",
            "score": 40 + min(len(sellers), 6),
            "insight": f"Seller membutuhkan perhatian di {_count(len(sellers))} DP; {_name(top)} memiliki {_count(affected)} seller WATCH/CRITICAL.",
            "action": "Minta PIC Seller menindaklanjuti seller bermasalah dan mencatat hambatan serta langkah pemulihannya.",
        })

    if not candidates:
        candidates.append({
            "id": "stable_operations",
            "score": 1,
            "insight": "Seluruh DP pada laporan berstatus NORMAL dan tidak ada sinyal prioritas lintas DP yang terdeteksi.",
            "action": "Lanjutkan pemantauan paket, SLA, seller, dan pendapatan pada jadwal laporan berikutnya.",
        })

    return sorted(candidates, key=lambda item: item["score"], reverse=True)


def _parse_ai_selection(content: str, candidates: list[dict]) -> list[dict]:
    start, end = content.find("{"), content.rfind("}")
    if start < 0 or end < start:
        return []
    payload = json.loads(content[start:end + 1])
    choices = payload.get("items")
    if not isinstance(choices, list):
        return []
    by_id = {item["id"]: item for item in candidates}
    selected = []
    seen = set()
    for choice in choices[:3]:
        if not isinstance(choice, dict):
            continue
        candidate = by_id.get(choice.get("id"))
        action = choice.get("action")
        if candidate is None or candidate["id"] in seen:
            continue
        if not isinstance(action, str) or not 12 <= len(action.strip()) <= 220:
            continue
        action = " ".join(action.split())
        if re.search(r"\d|https?://", action) or _BAD_ACTION_TERMS.search(action):
            continue
        selected.append({"id": candidate["id"], "insight": candidate["insight"], "action": action})
        seen.add(candidate["id"])
    return selected


async def _rank_with_ai(candidates: list[dict], period: str) -> list[dict]:
    api_key = os.getenv("LLM_API_KEY")
    base_url = os.getenv("LLM_BASE_URL")
    model = os.getenv("LLM_FAST_MODEL") or os.getenv("LLM_MODEL")
    if not (api_key and base_url and model):
        return []

    client = AsyncOpenAI(api_key=api_key, base_url=base_url, timeout=30.0)
    prompt = (
        "Pilih maksimal tiga insight paling penting untuk laporan " + period + ". "
        "Gunakan hanya kandidat berikut. Kembalikan JSON saja: "
        '{"items":[{"id":"candidate_id","action":"saran tindakan singkat"}]}. '
        "Tindakan harus dapat ditugaskan ke manager/PIC, tidak boleh mengarang angka, "
        "akar penyebab yang belum terbukti, harga, stok produk, atau data dari web. "
        "Jangan menulis angka dalam action.\n"
        + json.dumps(
            [{"id": item["id"], "insight": item["insight"], "baseline_action": item["action"]} for item in candidates],
            ensure_ascii=False,
        )
    )
    response = await asyncio.wait_for(
        client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "Anda analis operasional regional. Prioritaskan bukti, bukan asumsi."},
                {"role": "user", "content": prompt},
            ],
            max_tokens=1024,
            reasoning_effort="low",
        ),
        timeout=35.0,
    )
    content = response.choices[0].message.content
    return _parse_ai_selection(content if isinstance(content, str) else "", candidates)


async def analyze_report(rows: list[dict], period: str) -> dict:
    candidates = build_candidates(rows, period)
    if not candidates:
        return {"mode": "no_data", "items": []}
    try:
        selected = await _rank_with_ai(candidates, period)
    except Exception as exc:
        logger.warning("Report AI ranking unavailable: %s", type(exc).__name__)
        selected = []
    if selected:
        return {"mode": "ai", "items": selected}
    return {
        "mode": "rules_fallback",
        "items": [
            {"id": item["id"], "insight": item["insight"], "action": item["action"]}
            for item in candidates[:3]
        ],
    }


def format_report_analysis(analysis: dict, *, period: str, scope: str, business_date=None) -> str:
    label = "harian" if period == "daily" else "intraday"
    date_note = f" (tanggal simulasi {business_date})" if business_date else ""
    heading = f"Insight laporan {label} untuk {scope}{date_note}:"
    items = analysis.get("items") or []
    if not items:
        return heading + "\nData laporan belum tersedia."
    lines = [heading]
    for index, item in enumerate(items[:3], start=1):
        lines.append(f"{index}. {item['insight']}")
        lines.append(f"   Tindakan: {item['action']}")
    if analysis.get("mode") == "rules_fallback":
        lines.append("Prioritas ini memakai aturan operasional karena analisis AI belum tersedia.")
    return "\n".join(lines)
