-- =========================================================
-- Drop Point Operations Intelligence
-- 017_create_daily_operational_summary.sql
-- DAILY OPERATIONAL SUMMARY
-- =========================================================


-- =========================================================
-- 1. CURRENT PERIOD DELIVERY BY DROP POINT
-- Grain:
-- 1 row = 1 Drop Point
-- =========================================================

CREATE OR REPLACE VIEW
analytics.vw_drop_point_current_delivery AS

WITH period AS (

    SELECT
        as_of_date,
        month_start

    FROM analytics.vw_current_period
),

delivery AS (

    SELECT
        p.as_of_date,
        p.month_start,

        d.drop_point_id,
        d.drop_point_name,

        d.delivery_class,
        d.delay_hours

    FROM analytics.vw_delivery_detail d

    CROSS JOIN period p

    WHERE
        d.order_date >= p.month_start
        AND d.order_date <= p.as_of_date
)

SELECT
    as_of_date,
    month_start,

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

    COUNT(*) FILTER (
        WHERE delivery_class = 'OPEN'
    ) AS open_delivery,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE delivery_class = 'ON_TIME'
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE delivery_class IN (
                    'ON_TIME',
                    'LATE'
                )
            ),
            0
        ),
        2
    ) AS on_time_rate_pct,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE delivery_class = 'LATE'
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE delivery_class IN (
                    'ON_TIME',
                    'LATE'
                )
            ),
            0
        ),
        2
    ) AS late_rate_pct,

    ROUND(
        AVG(delay_hours)
        FILTER (
            WHERE delivery_class = 'LATE'
        ),
        2
    ) AS avg_delay_hours

FROM delivery

GROUP BY
    as_of_date,
    month_start,
    drop_point_id,
    drop_point_name;

-- =========================================================
-- 2. OUTLET ATTENTION SUMMARY PER DROP POINT
-- =========================================================

CREATE OR REPLACE VIEW
analytics.vw_drop_point_outlet_attention_summary AS

SELECT
    as_of_date,

    drop_point_id,
    drop_point_name,

    COUNT(*) AS total_monitored_outlet,

    COUNT(*) FILTER (
        WHERE attention_status = 'CRITICAL'
    ) AS critical_outlet,

    COUNT(*) FILTER (
        WHERE attention_status = 'WARNING'
    ) AS warning_outlet,

    COUNT(*) FILTER (
        WHERE attention_status = 'NORMAL'
    ) AS normal_outlet,

    COUNT(*) FILTER (
        WHERE activity_status = 'INACTIVE_14D'
    ) AS inactive_14d_outlet,

    COUNT(*) FILTER (
        WHERE activity_status = 'WATCH_7D'
    ) AS watch_7d_outlet

FROM analytics.vw_outlet_attention

GROUP BY
    as_of_date,
    drop_point_id,
    drop_point_name;

-- =========================================================
-- 3. DAILY OPERATIONAL SUMMARY
-- Grain:
-- 1 row = 1 Drop Point
-- =========================================================

CREATE OR REPLACE VIEW
analytics.vw_daily_operational_summary AS

WITH target AS (

    SELECT
        month_start,
        drop_point_id,
        delivery_sla_target_pct

    FROM analytics.vw_drop_point_sales_monthly
)

SELECT
    s.as_of_date,
    s.month_start,

    s.drop_point_id,
    s.drop_point_name,
    s.region,
    s.area,

    -- =====================================================
    -- SALES
    -- =====================================================

    s.net_sales,
    s.sales_target,

    s.sales_achievement_pct,
    s.expected_achievement_pct,

    s.sales_achievement_pct
        - s.expected_achievement_pct
        AS sales_pace_gap_pp,

    s.performance_status
        AS sales_status,


    -- =====================================================
    -- OUTLET
    -- =====================================================

    s.active_outlet,
    s.active_outlet_target,
    s.active_outlet_achievement_pct,

    COALESCE(o.critical_outlet, 0)
        AS critical_outlet,

    COALESCE(o.warning_outlet, 0)
        AS warning_outlet,

    COALESCE(o.inactive_14d_outlet, 0)
        AS inactive_14d_outlet,


    -- =====================================================
    -- DELIVERY
    -- =====================================================

    COALESCE(d.total_shipment, 0)
        AS total_shipment,

    COALESCE(d.on_time_delivery, 0)
        AS on_time_delivery,

    COALESCE(d.late_delivery, 0)
        AS late_delivery,

    COALESCE(d.failed_delivery, 0)
        AS failed_delivery,

    COALESCE(d.overdue_delivery, 0)
        AS overdue_delivery,

    d.on_time_rate_pct,

    t.delivery_sla_target_pct,

    ROUND(
        d.on_time_rate_pct
        - t.delivery_sla_target_pct,
        2
    ) AS delivery_sla_gap_pp,

    d.avg_delay_hours,


    -- =====================================================
    -- OVERALL OPERATIONAL STATUS
    -- Prototype rules
    -- =====================================================

    CASE

        WHEN s.performance_status = 'CRITICAL'
        THEN 'CRITICAL'

        WHEN
            d.on_time_rate_pct
            - t.delivery_sla_target_pct <= -10
        THEN 'CRITICAL'

        WHEN COALESCE(o.critical_outlet, 0) >= 3
        THEN 'CRITICAL'


        WHEN s.performance_status = 'WARNING'
        THEN 'WARNING'

        WHEN
            d.on_time_rate_pct
            - t.delivery_sla_target_pct < 0
        THEN 'WARNING'

        WHEN COALESCE(o.critical_outlet, 0) >= 1
        THEN 'WARNING'

        WHEN COALESCE(o.warning_outlet, 0) >= 3
        THEN 'WARNING'


        ELSE 'NORMAL'

    END AS overall_status


FROM analytics.vw_drop_point_current_performance s

LEFT JOIN analytics.vw_drop_point_current_delivery d
    ON s.drop_point_id = d.drop_point_id

LEFT JOIN analytics.vw_drop_point_outlet_attention_summary o
    ON s.drop_point_id = o.drop_point_id

LEFT JOIN target t
    ON s.month_start = t.month_start
    AND s.drop_point_id = t.drop_point_id;

