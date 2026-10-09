CREATE OR REPLACE VIEW analytics.vw_daily_report AS

WITH params AS (
    SELECT
        current_business_date AS business_date
    FROM app.simulation_state
    WHERE simulation_name = 'operations_demo'
),

sales AS (
    SELECT
        f.drop_point_id,

        SUM(f.net_sales) AS daily_net_sales,

        COUNT(DISTINCT f.invoice_id)
            AS daily_invoice,

        COUNT(DISTINCT f.outlet_id)
            AS daily_active_outlet

    FROM core.fact_sales f

    CROSS JOIN params p

    WHERE f.sales_date = p.business_date

    GROUP BY
        f.drop_point_id
),

delivery AS (
    SELECT
        d.drop_point_id,

        COUNT(*) AS daily_shipment,

        COUNT(*) FILTER (
            WHERE d.delivery_class = 'ON_TIME'
        ) AS daily_on_time,

        COUNT(*) FILTER (
            WHERE d.delivery_class = 'LATE'
        ) AS daily_late,

        COUNT(*) FILTER (
            WHERE d.delivery_class = 'FAILED'
        ) AS daily_failed,

        COUNT(*) FILTER (
            WHERE d.delivery_class = 'IN_TRANSIT'
        ) AS daily_in_transit,

        COUNT(*) FILTER (
            WHERE d.delivery_class = 'IN_TRANSIT'
              AND d.is_overdue = TRUE
        ) AS daily_overdue,

        COUNT(*) FILTER (
            WHERE d.is_completed = TRUE
        ) AS daily_completed,

        COUNT(*) FILTER (
            WHERE d.is_delivered = TRUE
        ) AS daily_successful_delivery,

        ROUND(
            100.0
            * COUNT(*) FILTER (
                WHERE d.delivery_class = 'ON_TIME'
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE d.is_completed = TRUE
                ),
                0
            ),
            2
        ) AS daily_on_time_rate_pct,

        ROUND(
            100.0
            * COUNT(*) FILTER (
                WHERE d.is_delivered = TRUE
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE d.is_completed = TRUE
                ),
                0
            ),
            2
        ) AS daily_delivery_success_rate_pct

    FROM analytics.vw_delivery_detail d

    CROSS JOIN params p

    WHERE COALESCE(
        d.shipment_ts::date,
        d.order_date
    ) = p.business_date

    GROUP BY
        d.drop_point_id
),

period AS (
    SELECT
        total_working_days
    FROM analytics.vw_current_period
)

SELECT
    -- =====================================================
    -- EXISTING COLUMNS
    -- Preserve exact order for API/report compatibility
    -- =====================================================

    p.business_date,

    s.drop_point_id,
    s.drop_point_name,

    COALESCE(ds.daily_net_sales, 0::numeric)
        AS daily_net_sales,

    COALESCE(ds.daily_invoice, 0::bigint)
        AS daily_invoice,

    COALESCE(ds.daily_active_outlet, 0::bigint)
        AS daily_active_outlet,

    ROUND(
        s.sales_target
        / NULLIF(period.total_working_days, 0),
        2
    ) AS daily_sales_target,

    ROUND(
        100.0
        * COALESCE(ds.daily_net_sales, 0::numeric)
        / NULLIF(
            s.sales_target
            / NULLIF(period.total_working_days, 0),
            0
        ),
        2
    ) AS daily_sales_achievement_pct,

    COALESCE(dd.daily_shipment, 0::bigint)
        AS daily_shipment,

    COALESCE(dd.daily_on_time, 0::bigint)
        AS daily_on_time,

    COALESCE(dd.daily_late, 0::bigint)
        AS daily_late,

    COALESCE(dd.daily_failed, 0::bigint)
        AS daily_failed,

    dd.daily_on_time_rate_pct,

    s.net_sales AS mtd_net_sales,
    s.sales_target AS monthly_sales_target,
    s.sales_achievement_pct AS mtd_sales_achievement_pct,

    s.expected_achievement_pct,
    s.sales_pace_gap_pp,

    s.on_time_rate_pct AS mtd_on_time_rate_pct,
    s.delivery_sla_target_pct,

    s.critical_outlet,

    -- legacy name retained; now represents WATCH outlets
    s.warning_outlet,

    s.overall_status,

    -- =====================================================
    -- NEW DELIVERY LIFECYCLE METRICS
    -- Append only
    -- =====================================================

    COALESCE(dd.daily_completed, 0::bigint)
        AS daily_completed,

    COALESCE(dd.daily_in_transit, 0::bigint)
        AS daily_in_transit,

    COALESCE(dd.daily_overdue, 0::bigint)
        AS daily_overdue,

    COALESCE(dd.daily_successful_delivery, 0::bigint)
        AS daily_successful_delivery,

    dd.daily_delivery_success_rate_pct,

    s.completed_delivery AS mtd_completed_delivery,
    s.in_transit_delivery AS mtd_in_transit_delivery,
    s.late_delivery AS mtd_late_delivery,
    s.failed_delivery AS mtd_failed_delivery,
    s.overdue_delivery AS mtd_overdue_delivery,

    s.delivery_status,

    s.normal_outlet,
    s.watch_outlet

FROM analytics.vw_daily_operational_summary s

CROSS JOIN params p
CROSS JOIN period

LEFT JOIN sales ds
    ON s.drop_point_id = ds.drop_point_id

LEFT JOIN delivery dd
    ON s.drop_point_id = dd.drop_point_id;