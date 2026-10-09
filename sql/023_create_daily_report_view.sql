-- =========================================================
-- 023_create_daily_report_view.sql
-- END-OF-DAY OPERATIONAL REPORT
-- =========================================================

CREATE OR REPLACE VIEW
analytics.vw_daily_report AS

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

    GROUP BY f.drop_point_id
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

        ROUND(
            100.0
            * COUNT(*) FILTER (
                WHERE d.delivery_class = 'ON_TIME'
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE d.delivery_class IN (
                        'ON_TIME',
                        'LATE'
                    )
                ),
                0
            ),
            2
        ) AS daily_on_time_rate_pct

    FROM analytics.vw_delivery_detail d

    CROSS JOIN params p

    WHERE d.order_date = p.business_date

    GROUP BY d.drop_point_id
),

period AS (

    SELECT
        total_working_days

    FROM analytics.vw_current_period
)

SELECT
    p.business_date,

    s.drop_point_id,
    s.drop_point_name,

    -- DAILY SALES
    COALESCE(ds.daily_net_sales, 0)
        AS daily_net_sales,

    COALESCE(ds.daily_invoice, 0)
        AS daily_invoice,

    COALESCE(ds.daily_active_outlet, 0)
        AS daily_active_outlet,

    ROUND(
        s.sales_target
        / NULLIF(period.total_working_days, 0),
        2
    ) AS daily_sales_target,

    ROUND(
        100.0
        * COALESCE(ds.daily_net_sales, 0)
        / NULLIF(
            s.sales_target
            / NULLIF(period.total_working_days, 0),
            0
        ),
        2
    ) AS daily_sales_achievement_pct,

    -- DAILY DELIVERY
    COALESCE(dd.daily_shipment, 0)
        AS daily_shipment,

    COALESCE(dd.daily_on_time, 0)
        AS daily_on_time,

    COALESCE(dd.daily_late, 0)
        AS daily_late,

    COALESCE(dd.daily_failed, 0)
        AS daily_failed,

    dd.daily_on_time_rate_pct,

    -- MONTH TO DATE
    s.net_sales AS mtd_net_sales,
    s.sales_target AS monthly_sales_target,
    s.sales_achievement_pct
        AS mtd_sales_achievement_pct,

    s.expected_achievement_pct,
    s.sales_pace_gap_pp,

    s.on_time_rate_pct
        AS mtd_on_time_rate_pct,

    s.delivery_sla_target_pct,

    s.critical_outlet,
    s.warning_outlet,

    s.overall_status

FROM analytics.vw_daily_operational_summary s

CROSS JOIN params p
CROSS JOIN period

LEFT JOIN sales ds
    ON s.drop_point_id = ds.drop_point_id

LEFT JOIN delivery dd
    ON s.drop_point_id = dd.drop_point_id;