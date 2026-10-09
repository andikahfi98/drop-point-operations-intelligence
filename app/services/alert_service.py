from sqlalchemy import text

from app.db.database import engine


CURRENT_STATUS_QUERY = text("""
    SELECT
        as_of_date,
        drop_point_id,
        drop_point_name,
        manager_staff_id,
        manager_name,
        revenue_status,
        revenue_achievement_pct,
        expected_achievement_pct,
        revenue_gap_pct,
        seller_status,
        total_monitored_seller,
        normal_seller,
        watch_seller,
        critical_seller,
        parcel_status,
        parcel_at_dp,
        parcel_over_24h,
        oldest_parcel_hours,
        avg_dp_hours,
        parcel_out_pct,
        delivery_status,
        completed_delivery,
        in_transit_delivery,
        on_time_delivery,
        late_delivery,
        failed_delivery,
        returned_delivery,
        overdue_delivery,
        on_time_rate_pct,
        delivery_sla_target_pct,
        delivery_sla_gap_pct,
        overall_status
    FROM analytics.vw_daily_operational_summary
    ORDER BY drop_point_id;
""")

RESPONSIBILITY_QUERY = text("""
    SELECT
        drop_point_id,
        component,
        status,
        responsible_unit_code,
        responsible_unit_name,
        responsible_staff_id,
        responsible_staff_name,
        manager_staff_id,
        manager_name
    FROM analytics.vw_drop_point_status_responsibility
    ORDER BY drop_point_id,
        CASE status WHEN 'CRITICAL' THEN 1 WHEN 'WATCH' THEN 2 ELSE 3 END,
        component;
""")


def _fmt_pct(value):
    if value is None:
        return "-"
    return f"{float(value):.2f}%"


def _fmt_hours(value):
    if value is None:
        return "-"
    return f"{float(value):.2f} jam"


def build_reasons(row):
    """Explain component statuses already produced by analytics."""
    reasons = []

    if row["revenue_status"] == "CRITICAL":
        reasons.append(
            "Pendapatan CRITICAL: "
            f"pencapaian {_fmt_pct(row['revenue_achievement_pct'])} "
            f"vs expected {_fmt_pct(row['expected_achievement_pct'])}; "
            f"gap {_fmt_pct(row['revenue_gap_pct'])}"
        )

    if row["seller_status"] == "CRITICAL":
        reasons.append(
            "Seller CRITICAL: "
            f"{row['critical_seller']} critical, "
            f"{row['watch_seller']} watch, "
            f"dari {row['total_monitored_seller']} Seller"
        )

    if row["parcel_status"] == "CRITICAL":
        reasons.append(
            "Paket di DP CRITICAL: "
            f"{row['parcel_at_dp']} paket masih di DP, "
            f"{row['parcel_over_24h']} >24 jam, "
            f"terlama {_fmt_hours(row['oldest_parcel_hours'])}, "
            f"rata-rata {_fmt_hours(row['avg_dp_hours'])}"
        )

    if row["delivery_status"] == "CRITICAL":
        reasons.append(
            "Pengiriman CRITICAL: "
            f"on-time {_fmt_pct(row['on_time_rate_pct'])} "
            f"vs SLA {_fmt_pct(row['delivery_sla_target_pct'])}; "
            f"gap {_fmt_pct(row['delivery_sla_gap_pct'])}; "
            f"{row['late_delivery']} late, "
            f"{row['failed_delivery']} failed, "
            f"{row['returned_delivery']} return, "
            f"{row['overdue_delivery']} overdue"
        )

    if not reasons:
        reasons.append("Overall operational status berubah menjadi CRITICAL")

    return reasons


def evaluate_critical_alerts():
    """
    Notify only when a Drop Point enters CRITICAL.
    CRITICAL -> CRITICAL never generates a duplicate alert.
    """
    alerts = []

    with engine.begin() as connection:
        current_rows = connection.execute(CURRENT_STATUS_QUERY).mappings().all()
        responsibility_rows = connection.execute(RESPONSIBILITY_QUERY).mappings().all()

        responsibility_map = {}
        for item in responsibility_rows:
            responsibility_map.setdefault(item["drop_point_id"], []).append(dict(item))

        state_rows = connection.execute(
            text("""
                SELECT drop_point_id, last_status
                FROM app.alert_state
                FOR UPDATE;
            """)
        ).mappings().all()

        state_map = {row["drop_point_id"]: row["last_status"] for row in state_rows}

        for row in current_rows:
            drop_point_id = row["drop_point_id"]
            current_status = row["overall_status"]
            previous_status = state_map.get(drop_point_id, "UNKNOWN")
            status_changed = current_status != previous_status
            is_new_critical = current_status == "CRITICAL" and previous_status != "CRITICAL"

            if is_new_critical:
                responsibilities = responsibility_map.get(drop_point_id, [])
                alerts.append({
                    "drop_point_id": drop_point_id,
                    "drop_point_name": row["drop_point_name"],
                    "manager_staff_id": row["manager_staff_id"],
                    "manager_name": row["manager_name"],
                    "previous_status": previous_status,
                    "current_status": current_status,
                    "revenue_status": row["revenue_status"],
                    "revenue_achievement_pct": row["revenue_achievement_pct"],
                    "expected_achievement_pct": row["expected_achievement_pct"],
                    "revenue_gap_pct": row["revenue_gap_pct"],
                    "seller_status": row["seller_status"],
                    "total_monitored_seller": row["total_monitored_seller"],
                    "normal_seller": row["normal_seller"],
                    "watch_seller": row["watch_seller"],
                    "critical_seller": row["critical_seller"],
                    "parcel_status": row["parcel_status"],
                    "parcel_at_dp": row["parcel_at_dp"],
                    "parcel_over_24h": row["parcel_over_24h"],
                    "oldest_parcel_hours": row["oldest_parcel_hours"],
                    "avg_dp_hours": row["avg_dp_hours"],
                    "parcel_out_pct": row["parcel_out_pct"],
                    "delivery_status": row["delivery_status"],
                    "completed_delivery": row["completed_delivery"],
                    "in_transit_delivery": row["in_transit_delivery"],
                    "on_time_delivery": row["on_time_delivery"],
                    "late_delivery": row["late_delivery"],
                    "failed_delivery": row["failed_delivery"],
                    "returned_delivery": row["returned_delivery"],
                    "overdue_delivery": row["overdue_delivery"],
                    "on_time_rate_pct": row["on_time_rate_pct"],
                    "delivery_sla_target_pct": row["delivery_sla_target_pct"],
                    "delivery_sla_gap_pct": row["delivery_sla_gap_pct"],
                    "responsibility": responsibilities,
                    "reasons": build_reasons(row),
                })

            if status_changed:
                connection.execute(
                    text("""
                        INSERT INTO app.alert_event_log (
                            drop_point_id, previous_status, new_status, event_type
                        )
                        VALUES (
                            :drop_point_id, :previous_status, :new_status, :event_type
                        );
                    """),
                    {
                        "drop_point_id": drop_point_id,
                        "previous_status": previous_status,
                        "new_status": current_status,
                        "event_type": "CRITICAL_ALERT" if is_new_critical else "STATUS_CHANGE",
                    },
                )

            connection.execute(
                text("""
                    INSERT INTO app.alert_state (
                        drop_point_id,
                        last_status,
                        last_alerted_at,
                        last_status_changed_at,
                        updated_at
                    )
                    VALUES (
                        :drop_point_id,
                        :status,
                        CASE WHEN :is_new_critical THEN NOW() ELSE NULL END,
                        NOW(),
                        NOW()
                    )
                    ON CONFLICT (drop_point_id)
                    DO UPDATE SET
                        last_status = EXCLUDED.last_status,
                        last_alerted_at = CASE
                            WHEN :is_new_critical THEN NOW()
                            ELSE app.alert_state.last_alerted_at
                        END,
                        last_status_changed_at = CASE
                            WHEN app.alert_state.last_status IS DISTINCT FROM EXCLUDED.last_status
                            THEN NOW()
                            ELSE app.alert_state.last_status_changed_at
                        END,
                        updated_at = NOW();
                """),
                {
                    "drop_point_id": drop_point_id,
                    "status": current_status,
                    "is_new_critical": is_new_critical,
                },
            )

    return {"count": len(alerts), "alerts": alerts}
