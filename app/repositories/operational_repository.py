from sqlalchemy import bindparam, text

from app.db.database import engine


SUMMARY_QUERY = text("""
    SELECT
        as_of_date,
        month_start,
        drop_point_id,
        drop_point_name,
        region,
        area,
        manager_staff_id,
        manager_name,
        revenue,
        revenue_target,
        revenue_achievement_pct,
        expected_achievement_pct,
        revenue_gap_pct,
        revenue_status,
        active_seller,
        active_seller_target,
        active_seller_achievement_pct,
        normal_seller,
        watch_seller,
        critical_seller,
        total_monitored_seller,
        inactive_14d_seller,
        critical_seller_pct,
        attention_seller_pct,
        seller_status,
        parcel_in_mtd,
        parcel_out_mtd,
        parcel_at_dp,
        parcel_under_6h,
        parcel_6_12h,
        parcel_12_24h,
        parcel_over_24h,
        oldest_parcel_hours,
        avg_dp_hours,
        parcel_out_pct,
        parcel_status,
        total_shipment,
        completed_delivery,
        in_transit_delivery,
        successful_delivery,
        on_time_delivery,
        late_delivery,
        failed_delivery,
        returned_delivery,
        overdue_delivery,
        on_time_rate_pct,
        delivery_success_rate_pct,
        delivery_sla_target_pct,
        delivery_sla_gap_pct,
        avg_delay_hours,
        delivery_status,
        delivery_data_status,
        overall_status
    FROM analytics.vw_daily_operational_summary
    ORDER BY
        CASE overall_status
            WHEN 'CRITICAL' THEN 1
            WHEN 'WATCH' THEN 2
            ELSE 3
        END,
        revenue_gap_pct ASC,
        drop_point_name;
""")


def get_operational_summary():
    with engine.connect() as connection:
        result = connection.execute(SUMMARY_QUERY)
        return [dict(row._mapping) for row in result]


DROP_POINTS_QUERY = text("""
    SELECT
        dp.drop_point_id,
        dp.drop_point_name,
        dp.region,
        dp.area,
        mgr.staff_id AS manager_staff_id,
        mgr.staff_name AS manager_name,
        dp.status
    FROM core.dim_drop_point dp
    LEFT JOIN core.dim_staff mgr
      ON mgr.drop_point_id = dp.drop_point_id
     AND mgr.unit_code = 'MANAGEMENT'
     AND mgr.role_code = 'MANAGER'
     AND mgr.status = 'ACTIVE'
    ORDER BY dp.drop_point_name;
""")


def get_drop_points():
    with engine.connect() as connection:
        result = connection.execute(DROP_POINTS_QUERY)
        return [dict(row._mapping) for row in result]


DROP_POINT_DETAIL_QUERY = text("""
    SELECT *
    FROM analytics.vw_daily_operational_summary
    WHERE drop_point_id = :drop_point_id;
""")


def get_drop_point_detail(drop_point_id: str):
    with engine.connect() as connection:
        row = connection.execute(
            DROP_POINT_DETAIL_QUERY,
            {"drop_point_id": drop_point_id},
        ).fetchone()
    return dict(row._mapping) if row else None


DROP_POINT_SELLERS_QUERY = text("""
    SELECT
        as_of_date,
        drop_point_id,
        drop_point_name,
        seller_id,
        seller_code,
        seller_name,
        seller_segment,
        city_area,
        seller_pic_id,
        seller_pic_name,
        last_transaction_date,
        days_since_last_transaction,
        current_month_transaction,
        current_month_revenue,
        activity_status,
        attention_status
    FROM analytics.vw_seller_attention
    WHERE drop_point_id = :drop_point_id
    ORDER BY
        CASE attention_status
            WHEN 'CRITICAL' THEN 1
            WHEN 'WATCH' THEN 2
            ELSE 3
        END,
        days_since_last_transaction DESC NULLS FIRST,
        seller_name;
""")


def get_drop_point_sellers(drop_point_id: str):
    with engine.connect() as connection:
        result = connection.execute(
            DROP_POINT_SELLERS_QUERY,
            {"drop_point_id": drop_point_id},
        )
        return [dict(row._mapping) for row in result]


DROP_POINT_PARCEL_QUERY = text("""
    SELECT
        drop_point_id,
        drop_point_name,
        parcel_in_mtd,
        parcel_out_mtd,
        parcel_in_today,
        parcel_out_today,
        parcel_at_dp,
        parcel_under_6h,
        parcel_6_12h,
        parcel_12_24h,
        parcel_over_24h,
        oldest_parcel_hours,
        avg_dp_hours,
        parcel_out_pct,
        parcel_over_24h_pct,
        parcel_status
    FROM analytics.vw_drop_point_parcel_current
    WHERE drop_point_id = :drop_point_id;
""")


DROP_POINT_PARCEL_ISSUES_QUERY = text("""
    SELECT
        shipment_id,
        invoice_id,
        seller_id,
        seller_code,
        seller_name,
        seller_pic_id,
        seller_pic_name,
        shipment_status,
        issue_type,
        parcel_issue_reason,
        parcel_age_hours AS issue_hours,
        received_ts,
        sorted_ts,
        left_dp_ts,
        responsible_unit_code,
        responsible_unit_name,
        responsible_staff_id,
        responsible_staff_name,
        manager_staff_id,
        manager_name
    FROM analytics.vw_parcel_issues
    WHERE drop_point_id = :drop_point_id
    ORDER BY
        parcel_age_hours DESC NULLS LAST,
        received_ts ASC NULLS LAST
    LIMIT 50;
""")


def get_drop_point_parcel(drop_point_id: str):
    with engine.connect() as connection:
        row = connection.execute(
            DROP_POINT_PARCEL_QUERY,
            {"drop_point_id": drop_point_id},
        ).fetchone()
        issues_result = connection.execute(
            DROP_POINT_PARCEL_ISSUES_QUERY,
            {"drop_point_id": drop_point_id},
        )
        issues = [dict(item._mapping) for item in issues_result]

    return {
        "summary": dict(row._mapping) if row else None,
        "issues": issues,
    }


DROP_POINT_DELIVERY_QUERY = text("""
    SELECT
        as_of_date,
        month_start,
        drop_point_id,
        drop_point_name,
        total_shipment,
        completed_delivery,
        in_transit_delivery,
        successful_delivery,
        on_time_delivery,
        late_delivery,
        failed_delivery,
        returned_delivery,
        overdue_delivery,
        on_time_rate_pct,
        delivery_success_rate_pct,
        late_rate_pct,
        failure_rate_pct,
        sla_target_pct AS delivery_sla_target_pct,
        sla_gap_pct AS delivery_sla_gap_pct,
        sla_shortfall_pct,
        avg_delivery_hours,
        avg_delay_hours,
        delivery_status,
        delivery_data_status
    FROM analytics.vw_drop_point_current_delivery_status
    WHERE drop_point_id = :drop_point_id;
""")


DROP_POINT_DELIVERY_ISSUES_QUERY = text("""
    SELECT
        shipment_id,
        invoice_id,
        seller_id,
        seller_code,
        seller_name,
        receiver_name,
        receiver_area,
        courier_id,
        courier_name,
        shipment_status,
        delivery_class,
        issue_type,
        delivery_issue_reason,
        issue_hours,
        left_dp_ts,
        target_delivery_ts,
        actual_delivery_ts,
        returned_ts,
        responsible_unit_code,
        responsible_unit_name,
        responsible_staff_id,
        responsible_staff_name,
        manager_staff_id,
        manager_name
    FROM analytics.vw_delivery_issues
    WHERE drop_point_id = :drop_point_id
    ORDER BY
        CASE issue_type
            WHEN 'OVERDUE' THEN 1
            WHEN 'FAILED' THEN 2
            WHEN 'RETURNED' THEN 3
            WHEN 'LATE' THEN 4
            ELSE 5
        END,
        issue_hours DESC NULLS LAST,
        left_dp_ts DESC NULLS LAST
    LIMIT 50;
""")


def get_drop_point_delivery(drop_point_id: str):
    with engine.connect() as connection:
        summary_row = connection.execute(
            DROP_POINT_DELIVERY_QUERY,
            {"drop_point_id": drop_point_id},
        ).fetchone()
        issues_result = connection.execute(
            DROP_POINT_DELIVERY_ISSUES_QUERY,
            {"drop_point_id": drop_point_id},
        )
        issues = [dict(row._mapping) for row in issues_result]

    return {
        "summary": dict(summary_row._mapping) if summary_row else None,
        "issues": issues,
    }


DROP_POINT_SELLER_PICS_QUERY = text("""
    SELECT
        as_of_date,
        drop_point_id,
        drop_point_name,
        staff_id,
        staff_name,
        revenue,
        revenue_target,
        revenue_achievement_pct,
        expected_achievement_pct,
        revenue_gap_pct,
        active_seller,
        active_seller_target,
        active_seller_achievement_pct,
        pic_data_status,
        pic_status
    FROM analytics.vw_seller_pic_current_performance
    WHERE drop_point_id = :drop_point_id
    ORDER BY
        CASE pic_status
            WHEN 'CRITICAL' THEN 1
            WHEN 'WATCH' THEN 2
            ELSE 3
        END,
        revenue_gap_pct ASC,
        staff_name;
""")


def get_drop_point_seller_pics(drop_point_id: str):
    with engine.connect() as connection:
        result = connection.execute(
            DROP_POINT_SELLER_PICS_QUERY,
            {"drop_point_id": drop_point_id},
        )
        return [dict(row._mapping) for row in result]


DROP_POINT_TEAM_QUERY = text("""
    SELECT
        drop_point_id,
        drop_point_name,
        region,
        staff_id,
        staff_name,
        unit_code,
        unit_name,
        role_code,
        manager_staff_id,
        manager_name,
        status
    FROM analytics.vw_drop_point_team
    WHERE drop_point_id = :drop_point_id
    ORDER BY
        CASE unit_code
            WHEN 'MANAGEMENT' THEN 1
            WHEN 'SELLER' THEN 2
            WHEN 'INBOUND' THEN 3
            WHEN 'SORTING' THEN 4
            WHEN 'OUTBOUND' THEN 5
            WHEN 'DELIVERY' THEN 6
            WHEN 'CUSTOMER_SERVICE' THEN 7
            ELSE 99
        END,
        role_code,
        staff_name;
""")


def get_drop_point_team(drop_point_id: str):
    with engine.connect() as connection:
        result = connection.execute(
            DROP_POINT_TEAM_QUERY,
            {"drop_point_id": drop_point_id},
        )
        return [dict(row._mapping) for row in result]


DROP_POINT_RESPONSIBILITY_QUERY = text("""
    SELECT
        drop_point_id,
        drop_point_name,
        component,
        status,
        responsible_unit_code,
        responsible_unit_name,
        responsible_staff_id,
        responsible_staff_name,
        manager_staff_id,
        manager_name
    FROM analytics.vw_drop_point_status_responsibility
    WHERE drop_point_id = :drop_point_id
    ORDER BY
        CASE status
            WHEN 'CRITICAL' THEN 1
            WHEN 'WATCH' THEN 2
            ELSE 3
        END,
        CASE component
            WHEN 'PARCEL' THEN 1
            WHEN 'DELIVERY' THEN 2
            WHEN 'REVENUE' THEN 3
            WHEN 'SELLER' THEN 4
            ELSE 99
        END;
""")


def get_drop_point_responsibility(drop_point_id: str):
    with engine.connect() as connection:
        result = connection.execute(
            DROP_POINT_RESPONSIBILITY_QUERY,
            {"drop_point_id": drop_point_id},
        )
        return [dict(row._mapping) for row in result]


DAILY_REPORT_QUERY = text("""
    SELECT
        business_date,
        drop_point_id,
        drop_point_name,
        manager_staff_id,
        manager_name,
        daily_revenue,
        daily_invoice,
        daily_active_seller,
        daily_revenue_target,
        daily_revenue_achievement_pct,
        daily_parcel_in,
        daily_parcel_out,
        parcel_at_dp,
        parcel_over_24h,
        oldest_parcel_hours,
        avg_dp_hours,
        parcel_out_pct,
        parcel_status,
        daily_shipment,
        daily_completed,
        daily_in_transit,
        daily_on_time,
        daily_late,
        daily_failed,
        daily_returned,
        daily_overdue,
        daily_on_time_rate_pct,
        mtd_revenue,
        monthly_revenue_target,
        mtd_revenue_achievement_pct,
        expected_achievement_pct,
        revenue_gap_pct,
        mtd_on_time_rate_pct,
        mtd_completed_delivery,
        mtd_in_transit_delivery,
        mtd_late_delivery,
        mtd_failed_delivery,
        mtd_returned_delivery,
        mtd_overdue_delivery,
        delivery_sla_target_pct,
        delivery_status,
        normal_seller,
        watch_seller,
        critical_seller,
        seller_status,
        overall_status
    FROM analytics.vw_daily_report
    ORDER BY
        CASE overall_status
            WHEN 'CRITICAL' THEN 1
            WHEN 'WATCH' THEN 2
            ELSE 3
        END,
        daily_revenue_achievement_pct ASC,
        drop_point_name;
""")


def get_daily_report():
    with engine.connect() as connection:
        result = connection.execute(DAILY_REPORT_QUERY)
        return [dict(row._mapping) for row in result]


DAILY_PULSE_QUERY = text("""
    SELECT business_date, drop_point_id, parcel_in, parcel_out,
           revenue, invoices, delivered, on_time
    FROM analytics.vw_drop_point_daily_pulse
    WHERE drop_point_id IN :drop_point_ids
      AND business_date >= (
          SELECT MAX(business_date) - (:days - 1)
          FROM analytics.vw_drop_point_daily_pulse
      )
    ORDER BY business_date, drop_point_id
""").bindparams(bindparam("drop_point_ids", expanding=True))


def get_daily_pulse(drop_point_ids: list[str], days: int = 7):
    if not drop_point_ids:
        return []
    with engine.connect() as connection:
        result = connection.execute(
            DAILY_PULSE_QUERY,
            {"drop_point_ids": drop_point_ids, "days": days},
        )
        return [dict(row._mapping) for row in result]


PARCEL_QUEUE_QUERY = text("""
    SELECT shipment_id, invoice_id, seller_name, origin_dp_name,
           destination_dp_name, shipment_status, at_dp_since_ts,
           parcel_age_hours, parcel_issue_reason
    FROM analytics.vw_shipment_detail
    WHERE current_dp_id = :drop_point_id AND is_at_dp = TRUE
    ORDER BY parcel_age_hours DESC NULLS LAST, at_dp_since_ts ASC
    LIMIT 100
""")


def get_parcel_queue(drop_point_id: str):
    with engine.connect() as connection:
        result = connection.execute(PARCEL_QUEUE_QUERY, {"drop_point_id": drop_point_id})
        return [dict(row._mapping) for row in result]
