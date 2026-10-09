from app.services.operational_service import (
    get_summary,
    get_drop_point,
    get_sellers_by_drop_point,
    get_parcels_by_drop_point,
    get_delivery_by_drop_point,
    get_seller_pics_by_drop_point,
    get_team_by_drop_point,
    get_responsibility_by_drop_point,
    get_operational_pulse,
)


def detect_intent(message: str) -> str:
    text = message.lower().strip()

    if any(x in text for x in ["tren", "trend", "7 hari", "14 hari", "pergerakan harian"]):
        return "trend"
    if any(x in text for x in ["hari ini", "today", "arus harian"]):
        return "daily"

    if any(x in text for x in [
        "diprioritaskan", "yang diprioritaskan", "apa prioritas",
        "prioritas apa", "prioritasnya", "prioritas tindakan",
        "prioritas action",
    ]):
        return "priority"

    if any(x in text for x in [
        "siapa yang bertanggung jawab", "siapa bertanggung jawab",
        "penanggung jawab", "tanggung jawab siapa", "responsible",
        "unit mana yang bertanggung jawab", "pic-nya siapa", "pic nya siapa",
    ]):
        return "responsibility"

    if any(x in text for x in [
        "solusi", "rekomendasi", "saran", "harus dilakukan", "action plan",
        "menurut kamu", "menurutmu", "bagaimana sebaiknya", "what should",
    ]):
        return "recommendation"

    if any(x in text for x in [
        "bandingkan", "compare", "dibanding", " vs ", " versus ",
        "skenario", "kalau naik", "kalau turun", "bagaimana kalau",
    ]):
        return "llm"

    if any(x in text for x in [
        "paling bermasalah", "paling parah", "terburuk", "paling critical",
        "paling kritis", "paling perlu perhatian",
    ]):
        return "overall_worst"

    if (
        any(x in text for x in ["kenapa", "mengapa", "kok"])
        and any(x in text for x in [
            "merah", "kuning", "critical", "kritis", "watch", "warning", "status",
        ])
    ):
        return "why_status"

    if any(x in text for x in [
        "manager", "struktur tim", "tim drop point", "unit operasional",
        "unit di drop point", "siapa pic", "daftar pic",
    ]):
        return "team"

    if any(x in text for x in [
        "pic seller", "seller pic", "pic commercial", "pic komersial",
        "pic pendapatan", "performa pic seller",
    ]):
        return "seller_pic"

    # Generic PIC questions refer to operational responsibility in the final model.
    if "pic" in text:
        return "responsibility"

    # Accept the old word outlet as a user synonym, but always answer Seller.
    if any(x in text for x in ["seller", "outlet", "merchant", "pengirim bisnis"]):
        return "seller"

    if any(x in text for x in [
        "paket", "parcel", "tertahan", "at dp", "di dp", "aging",
        "lama di dp", "paket masuk", "paket keluar",
    ]):
        return "parcel"

    if any(x in text for x in [
        "delivery", "sla", "on time", "on-time", "tepat waktu", "terlambat",
        "late", "failed delivery", "gagal kirim", "overdue", "in transit",
        "in_transit", "pengiriman", "receiver", "kurir", "return",
    ]):
        return "delivery"

    if any(x in text for x in [
        "revenue", "pendapatan", "sales", "penjualan", "achievement",
        "pencapaian", "target pendapatan", "pace",
    ]):
        return "revenue"

    if any(x in text for x in [
        "status", "merah", "kuning", "critical", "kritis", "watch",
        "warning", "normal",
    ]):
        return "status"

    return "llm"


def rupiah(value):
    if value is None:
        return "-"
    return "Rp" + f"{float(value):,.0f}".replace(",", ".")


def pct(value):
    if value is None:
        return "-"
    return f"{float(value):.2f}%"


def signed_pct(value):
    if value is None:
        return "-"
    number = float(value)
    if number > 0:
        return f"+{number:.2f}%"
    return f"{number:.2f}%"


def hours(value):
    if value is None:
        return "-"
    return f"{float(value):.2f} jam"


def status_rank(status):
    return {"CRITICAL": 1, "WATCH": 2, "NORMAL": 3}.get(
        str(status or "").upper(), 99
    )


def component_label(component):
    return {
        "REVENUE": "Pendapatan",
        "SELLER": "Seller",
        "PARCEL": "Paket",
        "DELIVERY": "Pengiriman",
    }.get(str(component or "").upper(), str(component or "-"))


def _responsibility_rows(drop_point_id):
    result = get_responsibility_by_drop_point(drop_point_id)
    if not isinstance(result, dict):
        return [], None
    return result.get("data", []), result.get("manager")


def explain_status(dp, responsibility_rows=None):
    status = dp.get("overall_status", "UNKNOWN")
    revenue_status = dp.get("revenue_status", "NORMAL")
    seller_status = dp.get("seller_status", "NORMAL")
    parcel_status = dp.get("parcel_status", "NORMAL")
    delivery_status = dp.get("delivery_status", "NORMAL")

    reasons = []

    if revenue_status in ("WATCH", "CRITICAL"):
        reasons.append(
            f"pendapatan {revenue_status}: pencapaian "
            f"{pct(dp.get('revenue_achievement_pct'))}, expected "
            f"{pct(dp.get('expected_achievement_pct'))}, gap "
            f"{signed_pct(dp.get('revenue_gap_pct'))}"
        )

    if seller_status in ("WATCH", "CRITICAL"):
        reasons.append(
            f"seller {seller_status}: {dp.get('normal_seller', 0)} normal, "
            f"{dp.get('watch_seller', 0)} watch, "
            f"{dp.get('critical_seller', 0)} critical"
        )

    if parcel_status in ("WATCH", "CRITICAL"):
        reasons.append(
            f"paket {parcel_status}: {dp.get('parcel_at_dp', 0)} masih di DP, "
            f"{dp.get('parcel_over_24h', 0)} sudah >24 jam, "
            f"paket terlama {hours(dp.get('oldest_parcel_hours'))}"
        )

    if delivery_status in ("WATCH", "CRITICAL"):
        reasons.append(
            f"pengiriman {delivery_status}: on-time "
            f"{pct(dp.get('on_time_rate_pct'))} vs SLA "
            f"{pct(dp.get('delivery_sla_target_pct'))}, "
            f"gap {signed_pct(dp.get('delivery_sla_gap_pct'))}, "
            f"{dp.get('overdue_delivery', 0)} overdue"
        )

    if reasons:
        answer = (
            f"{dp['drop_point_name']} berstatus {status}. "
            f"Penyebab utamanya: " + "; ".join(reasons) + "."
        )
    else:
        delivery_text = (
            f"pengiriman {pct(dp.get('on_time_rate_pct'))} vs SLA "
            f"{pct(dp.get('delivery_sla_target_pct'))}"
            if dp.get("on_time_rate_pct") is not None
            else "pengiriman belum memiliki cukup completed shipment"
        )
        answer = (
            f"{dp['drop_point_name']} saat ini berstatus {status}. "
            f"Pendapatan {revenue_status}, seller {seller_status}, "
            f"paket {parcel_status}, dan {delivery_text}."
        )

    if responsibility_rows:
        parts = []
        for row in responsibility_rows:
            parts.append(
                f"{component_label(row.get('component'))} -> "
                f"{row.get('responsible_unit_name', '-')} / "
                f"{row.get('responsible_staff_name') or 'PIC belum tersedia'}"
            )
        answer += " Penanggung jawab operasional: " + "; ".join(parts) + "."

    return answer


def build_priority_answer(dp, responsibility_rows=None):
    responsibility_rows = responsibility_rows or []
    resp_map = {
        str(row.get("component", "")).lower(): row
        for row in responsibility_rows
    }

    priorities = []
    components = [
        ("parcel", dp.get("parcel_status")),
        ("delivery", dp.get("delivery_status")),
        ("revenue", dp.get("revenue_status")),
        ("seller", dp.get("seller_status")),
    ]
    components.sort(key=lambda x: status_rank(x[1]))

    for component, status in components:
        if status not in ("WATCH", "CRITICAL"):
            continue

        resp = resp_map.get(component, {})
        owner = ""
        if resp:
            owner = (
                f" Penanggung jawab: {resp.get('responsible_unit_name', '-')}"
                f" / {resp.get('responsible_staff_name') or 'PIC belum tersedia'}."
            )

        if component == "parcel":
            priorities.append(
                f"Paket di DP ({status}): {dp.get('parcel_at_dp', 0)} paket masih di DP, "
                f"{dp.get('parcel_over_24h', 0)} >24 jam, "
                f"terlama {hours(dp.get('oldest_parcel_hours'))}. "
                f"Prioritaskan paket aging tertua agar segera bergerak ke tahap berikutnya."
                + owner
            )
        elif component == "delivery":
            priorities.append(
                f"Pengiriman ({status}): on-time {pct(dp.get('on_time_rate_pct'))} "
                f"vs SLA {pct(dp.get('delivery_sla_target_pct'))}, "
                f"{dp.get('overdue_delivery', 0)} overdue. "
                f"Prioritaskan shipment overdue dan penyebab keterlambatan."
                + owner
            )
        elif component == "revenue":
            priorities.append(
                f"Pendapatan ({status}): pencapaian {pct(dp.get('revenue_achievement_pct'))}, "
                f"expected {pct(dp.get('expected_achievement_pct'))}, "
                f"gap {signed_pct(dp.get('revenue_gap_pct'))}. "
                f"Prioritaskan Seller/PIC Seller yang tertinggal dari target."
                + owner
            )
        elif component == "seller":
            priorities.append(
                f"Seller ({status}): {dp.get('watch_seller', 0)} watch dan "
                f"{dp.get('critical_seller', 0)} critical. "
                f"Prioritaskan Seller CRITICAL lebih dulu."
                + owner
            )

    if not priorities:
        return (
            f"{dp['drop_point_name']} saat ini {dp.get('overall_status', 'NORMAL')}. "
            f"Tidak ada area WATCH atau CRITICAL yang memerlukan intervensi khusus. "
            f"Pantau rutin paket di DP, delivery, pendapatan, dan aktivitas Seller."
        )

    lines = [
        f"{dp['drop_point_name']} saat ini {dp.get('overall_status', '-')}. "
        f"Prioritas operasional:"
    ]
    for i, item in enumerate(priorities, start=1):
        lines.append(f"{i}. {item}")

    normal_components = [
        label
        for label, key in [
            ("Pendapatan", "revenue_status"),
            ("Seller", "seller_status"),
            ("Paket", "parcel_status"),
            ("Pengiriman", "delivery_status"),
        ]
        if dp.get(key) == "NORMAL"
    ]
    if normal_components:
        lines.append("Area yang masih NORMAL: " + ", ".join(normal_components) + ".")

    return "\n".join(lines)


def build_responsibility_answer(dp, responsibility_rows, manager):
    if not responsibility_rows:
        manager_name = (manager or {}).get("staff_name") or dp.get("manager_name") or "-"
        return (
            f"{dp['drop_point_name']} tidak memiliki komponen WATCH/CRITICAL saat ini. "
            f"Manager Drop Point: {manager_name}."
        )

    lines = [f"Penanggung jawab kondisi {dp['drop_point_name']} saat ini:"]
    for i, row in enumerate(responsibility_rows, start=1):
        lines.append(
            f"{i}. {component_label(row.get('component'))} ({row.get('status', '-')}) -> "
            f"Unit {row.get('responsible_unit_name', '-')} -> "
            f"{row.get('responsible_staff_name') or 'PIC belum tersedia'}"
        )

    manager_name = (manager or {}).get("staff_name") or dp.get("manager_name")
    if manager_name:
        lines.append(f"Eskalasi keseluruhan Drop Point: {manager_name}.")
    return "\n".join(lines)


def build_direct_answer(intent: str, drop_point_id: str | None,
                        allowed_ids: set[str] | None = None):
    if intent in ("daily", "trend"):
        ids = [drop_point_id] if drop_point_id else sorted(allowed_ids or [])
        if not ids:
            return "Belum ada Drop Point yang dapat ditampilkan."
        rows = get_operational_pulse(ids, 7).get("data", [])
        if not rows:
            return "Data arus harian belum tersedia."
        daily = {}
        for row in rows:
            day = str(row["business_date"])
            totals = daily.setdefault(day, {"parcel_in": 0, "parcel_out": 0,
                                            "delivered": 0, "on_time": 0, "revenue": 0})
            for key in totals:
                totals[key] += row[key] or 0
        label = get_drop_point(drop_point_id)["drop_point_name"] if drop_point_id else "seluruh DP dalam akses Anda"
        if intent == "daily":
            day, totals = list(daily.items())[-1]
            return (
                f"Arus {label} pada {day} (waktu simulasi): "
                f"{totals['parcel_in']} paket masuk, {totals['parcel_out']} keluar; "
                f"{totals['delivered']} pengiriman selesai, {totals['on_time']} tepat waktu; "
                f"pendapatan {rupiah(totals['revenue'])}."
            )
        lines = [f"Tren 7 hari {label} (waktu simulasi):"]
        for day, totals in daily.items():
            lines.append(f"{day}: masuk {totals['parcel_in']}, keluar {totals['parcel_out']}, "
                         f"selesai {totals['delivered']}, pendapatan {rupiah(totals['revenue'])}.")
        return "\n".join(lines)

    if intent == "overall_worst":
        result = get_summary()
        rows = result.get("data", []) if result else []
        if allowed_ids is not None:
            rows = [row for row in rows if row["drop_point_id"] in allowed_ids]
        if not rows:
            return "Belum ada data operasional."

        attention_rows = [
            row for row in rows
            if row.get("overall_status") in ("WATCH", "CRITICAL")
        ]
        if not attention_rows:
            return (
                "Saat ini seluruh Drop Point berstatus NORMAL. "
                "Tidak ada Drop Point berstatus WATCH atau CRITICAL."
            )

        attention_rows.sort(
            key=lambda row: (
                status_rank(row.get("overall_status")),
                -int(row.get("parcel_over_24h") or 0),
                float(row.get("delivery_sla_gap_pct") or 0),
                float(row.get("revenue_gap_pct") or 0),
            )
        )

        lines = ["Drop Point yang paling perlu perhatian:"]
        for i, row in enumerate(attention_rows[:3], start=1):
            lines.append(
                f"{i}. {row['drop_point_name']} - {row['overall_status']} "
                f"(pendapatan {row.get('revenue_status', '-')}, "
                f"seller {row.get('seller_status', '-')}, "
                f"paket {row.get('parcel_status', '-')}, "
                f"pengiriman {row.get('delivery_status', '-')})"
            )
        return "\n".join(lines)

    if not drop_point_id:
        return None

    dp = get_drop_point(drop_point_id)
    if not dp:
        return None

    if intent in ("why_status", "priority", "responsibility"):
        responsibility_rows, manager = _responsibility_rows(drop_point_id)
        if intent == "why_status":
            return explain_status(dp, responsibility_rows)
        if intent == "priority":
            return build_priority_answer(dp, responsibility_rows)
        return build_responsibility_answer(dp, responsibility_rows, manager)

    if intent == "team":
        result = get_team_by_drop_point(drop_point_id)
        rows = result.get("data", []) if result else []
        if not rows:
            return "Data tim Drop Point belum tersedia."
        lines = [f"Tim {dp['drop_point_name']}:"]
        for row in rows:
            if row.get("unit_code") == "MANAGEMENT":
                lines.append(f"Manager: {row.get('staff_name', '-')}")
            else:
                lines.append(
                    f"- {row.get('unit_name', row.get('unit_code', '-'))}: "
                    f"{row.get('staff_name', '-')}"
                )
        return "\n".join(lines)

    if intent == "status":
        delivery_rate = (
            pct(dp.get("on_time_rate_pct"))
            if dp.get("on_time_rate_pct") is not None
            else "belum dapat dihitung"
        )
        return (
            f"{dp['drop_point_name']} saat ini berstatus {dp['overall_status']}. "
            f"Manager: {dp.get('manager_name', '-')}. "
            f"Pendapatan: {rupiah(dp.get('revenue'))} dari target "
            f"{rupiah(dp.get('revenue_target'))}, pencapaian "
            f"{pct(dp.get('revenue_achievement_pct'))}, status "
            f"{dp.get('revenue_status', '-')}. "
            f"Seller: {dp.get('normal_seller', 0)} normal, "
            f"{dp.get('watch_seller', 0)} watch, "
            f"{dp.get('critical_seller', 0)} critical, status "
            f"{dp.get('seller_status', '-')}. "
            f"Paket: {dp.get('parcel_at_dp', 0)} masih di DP, "
            f"{dp.get('parcel_over_24h', 0)} >24 jam, status "
            f"{dp.get('parcel_status', '-')}. "
            f"Pengiriman: {dp.get('completed_delivery', 0)} completed, "
            f"{dp.get('in_transit_delivery', 0)} in transit, "
            f"{dp.get('returned_delivery', 0)} return, "
            f"on-time {delivery_rate} vs SLA "
            f"{pct(dp.get('delivery_sla_target_pct'))}, status "
            f"{dp.get('delivery_status', '-')} ."
        )

    if intent == "revenue":
        return (
            f"Pendapatan {dp['drop_point_name']}: "
            f"{rupiah(dp.get('revenue'))} dari target "
            f"{rupiah(dp.get('revenue_target'))}. "
            f"Pencapaian {pct(dp.get('revenue_achievement_pct'))}, "
            f"expected {pct(dp.get('expected_achievement_pct'))}, "
            f"gap {signed_pct(dp.get('revenue_gap_pct'))}, "
            f"status {dp.get('revenue_status', '-')} ."
        )

    if intent == "parcel":
        result = get_parcels_by_drop_point(drop_point_id)
        summary = result.get("data") if result else None
        if not summary:
            return "Data paket belum tersedia."
        return (
            f"Paket {dp['drop_point_name']}: "
            f"{summary.get('parcel_in_mtd', 0)} masuk MTD, "
            f"{summary.get('parcel_out_mtd', 0)} keluar MTD, "
            f"{summary.get('parcel_at_dp', 0)} masih di DP. "
            f"Aging: {summary.get('parcel_under_6h', 0)} <6 jam, "
            f"{summary.get('parcel_6_12h', 0)} 6-12 jam, "
            f"{summary.get('parcel_12_24h', 0)} 12-24 jam, "
            f"{summary.get('parcel_over_24h', 0)} >24 jam. "
            f"Paket terlama {hours(summary.get('oldest_parcel_hours'))}, "
            f"rata-rata lama di DP {hours(summary.get('avg_dp_hours'))}, "
            f"paket keluar {pct(summary.get('parcel_out_pct'))}. "
            f"Status {summary.get('parcel_status', '-')} ."
        )

    if intent == "delivery":
        result = get_delivery_by_drop_point(drop_point_id)
        summary = result.get("summary") if result else None
        if not summary:
            return "Data pengiriman belum tersedia."

        rate_text = (
            pct(summary.get("on_time_rate_pct"))
            if summary.get("on_time_rate_pct") is not None
            else "belum dapat dihitung"
        )
        success_rate_text = (
            pct(summary.get("delivery_success_rate_pct"))
            if summary.get("delivery_success_rate_pct") is not None
            else "belum dapat dihitung"
        )
        return (
            f"Pengiriman {dp['drop_point_name']}: "
            f"{summary.get('total_shipment', 0)} shipment; "
            f"{summary.get('completed_delivery', 0)} completed; "
            f"{summary.get('in_transit_delivery', 0)} in transit; "
            f"{summary.get('on_time_delivery', 0)} on-time; "
            f"{summary.get('late_delivery', 0)} late; "
            f"{summary.get('failed_delivery', 0)} failed; "
            f"{summary.get('returned_delivery', 0)} return; "
            f"{summary.get('overdue_delivery', 0)} overdue aktif. "
            f"On-time {rate_text} vs SLA "
            f"{pct(summary.get('delivery_sla_target_pct'))}, gap "
            f"{signed_pct(summary.get('delivery_sla_gap_pct'))}. "
            f"Success rate {success_rate_text}. Status "
            f"{summary.get('delivery_status', '-')} ."
        )

    if intent == "seller":
        result = get_sellers_by_drop_point(drop_point_id)
        rows = result.get("data", []) if result else []
        problems = [
            row for row in rows
            if row.get("attention_status") in ("WATCH", "CRITICAL")
        ][:5]
        if not problems:
            return (
                f"Tidak ada Seller berstatus WATCH atau CRITICAL "
                f"di {dp['drop_point_name']} saat ini."
            )

        lines = [f"Seller yang paling perlu perhatian di {dp['drop_point_name']}:"]
        for i, row in enumerate(problems, start=1):
            days = row.get("days_since_last_transaction")
            days_text = (
                f"{days} hari sejak transaksi terakhir"
                if days is not None else "belum ada riwayat transaksi"
            )
            lines.append(
                f"{i}. {row.get('seller_name', '-')} ({row.get('attention_status', '-')}) - "
                f"{days_text}; PIC Seller {row.get('seller_pic_name', '-')}"
            )
        return "\n".join(lines)

    if intent == "seller_pic":
        result = get_seller_pics_by_drop_point(drop_point_id)
        rows = result.get("data", []) if result else []
        problems = [
            row for row in rows
            if row.get("pic_status") in ("WATCH", "CRITICAL")
        ][:3]
        if not problems:
            return (
                f"Tidak ada PIC Seller berstatus WATCH atau CRITICAL "
                f"di {dp['drop_point_name']} saat ini."
            )

        lines = [f"PIC Seller yang paling perlu perhatian di {dp['drop_point_name']}:"]
        for i, row in enumerate(problems, start=1):
            lines.append(
                f"{i}. {row.get('staff_name', '-')} ({row.get('pic_status', '-')}) - "
                f"pendapatan {rupiah(row.get('revenue'))} dari target "
                f"{rupiah(row.get('revenue_target'))}, pencapaian "
                f"{pct(row.get('revenue_achievement_pct'))}, expected "
                f"{pct(row.get('expected_achievement_pct'))}, gap "
                f"{signed_pct(row.get('revenue_gap_pct'))}, Seller aktif "
                f"{row.get('active_seller', 0)}/{row.get('active_seller_target', 0)}."
            )
        return "\n".join(lines)

    return None
