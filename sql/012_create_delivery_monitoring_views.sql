-- =========================================================
-- Drop Point Operations Intelligence
-- 012_create_delivery_monitoring_views.sql
-- DELIVERY MONITORING VIEWS
-- =========================================================


-- =========================================================
-- 1. DAILY DELIVERY TREND
-- Grain:
-- 1 row = 1 Drop Point per Order Date
-- =========================================================

CREATE OR REPLACE VIEW analytics.vw_delivery_daily_trend AS

SELECT
    order_date,

    drop_point_id,
    drop_point_name,

    COUNT(*) AS total_shipment,

    COUNT(*) FILTER (
        WHERE delivery_class = 'ON_TIME'
    ) AS on_time_delivery,

    COUNT(*) FILTER (
        WHERE delivery_class = 'LATE'
    ) AS late_delivery,

    COUNT(*) FILTER (
        WHERE delivery_class = 'FAILED'
    ) AS failed_delivery,

    COUNT(*) FILTER (
        WHERE delivery_class = 'OVERDUE'
    ) AS overdue_delivery,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE delivery_class = 'ON_TIME'
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE delivery_class IN ('ON_TIME', 'LATE')
            ),
            0
        ),
        2
    ) AS on_time_rate_pct,

    ROUND(
        AVG(delay_hours)
        FILTER (
            WHERE delivery_class = 'LATE'
        ),
        2
    ) AS avg_delay_hours

FROM analytics.vw_delivery_detail

GROUP BY
    order_date,
    drop_point_id,
    drop_point_name;


-- =========================================================
-- 2. OUTLET DELIVERY PERFORMANCE
-- Grain:
-- 1 row = 1 Outlet
-- =========================================================

CREATE OR REPLACE VIEW analytics.vw_outlet_delivery_performance AS

SELECT
    drop_point_id,
    drop_point_name,

    outlet_id,
    bp_code,
    outlet_name,

    salesperson_id,
    salesperson_name,

    COUNT(*) AS total_shipment,

    COUNT(*) FILTER (
        WHERE delivery_class = 'ON_TIME'
    ) AS on_time_delivery,

    COUNT(*) FILTER (
        WHERE delivery_class = 'LATE'
    ) AS late_delivery,

    COUNT(*) FILTER (
        WHERE delivery_class = 'FAILED'
    ) AS failed_delivery,

    COUNT(*) FILTER (
        WHERE delivery_class = 'OVERDUE'
    ) AS overdue_delivery,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE delivery_class = 'ON_TIME'
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE delivery_class IN ('ON_TIME', 'LATE')
            ),
            0
        ),
        2
    ) AS on_time_rate_pct,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE delivery_class = 'FAILED'
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS failure_rate_pct,

    ROUND(
        AVG(delay_hours)
        FILTER (
            WHERE delivery_class = 'LATE'
        ),
        2
    ) AS avg_delay_hours,

    MAX(delay_hours) AS max_delay_hours,

    MAX(order_date) AS last_order_date

FROM analytics.vw_delivery_detail

GROUP BY
    drop_point_id,
    drop_point_name,
    outlet_id,
    bp_code,
    outlet_name,
    salesperson_id,
    salesperson_name;


-- =========================================================
-- 3. DELIVERY ISSUES DETAIL
-- Only problematic shipments
-- =========================================================

CREATE OR REPLACE VIEW analytics.vw_delivery_issues AS

SELECT
    *

FROM analytics.vw_delivery_detail

WHERE delivery_class IN (
    'LATE',
    'FAILED',
    'OVERDUE'
);