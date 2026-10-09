-- =========================================================
-- Drop Point Operations Intelligence
-- 015_create_current_period_monitoring.sql
-- CURRENT PERIOD MONITORING
-- =========================================================


-- =========================================================
-- 1. DATA AS-OF DATE
-- =========================================================

CREATE OR REPLACE VIEW analytics.vw_data_freshness AS

SELECT
    (SELECT MAX(sales_date)
     FROM core.fact_sales)
        AS latest_sales_date,

    (SELECT MAX(order_date)
     FROM core.fact_delivery)
        AS latest_delivery_date,

    (SELECT MAX(snapshot_date)
     FROM core.fact_inventory)
        AS latest_inventory_date;

-- =========================================================
-- 2. CURRENT MONTH CALENDAR PROGRESS
-- =========================================================

CREATE OR REPLACE VIEW analytics.vw_current_period AS

WITH params AS (

    SELECT
        latest_sales_date AS as_of_date,
        DATE_TRUNC(
            'month',
            latest_sales_date
        )::DATE AS month_start

    FROM analytics.vw_data_freshness
)

SELECT
    p.as_of_date,
    p.month_start,

    (
        p.month_start
        + INTERVAL '1 month'
        - INTERVAL '1 day'
    )::DATE AS month_end,

    COUNT(*) FILTER (
        WHERE d.is_working_day = TRUE
    ) AS total_working_days,

    COUNT(*) FILTER (
        WHERE d.is_working_day = TRUE
          AND d.date <= p.as_of_date
    ) AS elapsed_working_days,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE d.is_working_day = TRUE
              AND d.date <= p.as_of_date
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE d.is_working_day = TRUE
            ),
            0
        ),
        2
    ) AS expected_achievement_pct

FROM params p

JOIN core.dim_date d
    ON d.month_start = p.month_start

GROUP BY
    p.as_of_date,
    p.month_start;


-- =========================================================
-- 3. CURRENT DROP POINT PERFORMANCE
-- =========================================================

CREATE OR REPLACE VIEW
analytics.vw_drop_point_current_performance AS

WITH period AS (

    SELECT *
    FROM analytics.vw_current_period
),

performance AS (

    SELECT
        s.month_start,
        s.drop_point_id,
        s.drop_point_name,
        s.region,
        s.area,

        s.net_sales,
        s.sales_target,
        s.sales_variance,
        s.sales_achievement_pct,

        s.active_outlet,
        s.active_outlet_target,
        s.active_outlet_achievement_pct

    FROM analytics.vw_drop_point_sales_monthly s

    CROSS JOIN period p

    WHERE s.month_start = p.month_start
)

SELECT
    p.as_of_date,
    p.month_start,

    p.total_working_days,
    p.elapsed_working_days,
    p.expected_achievement_pct,

    f.drop_point_id,
    f.drop_point_name,
    f.region,
    f.area,

    f.net_sales,
    f.sales_target,
    f.sales_achievement_pct,

    ROUND(
        f.sales_achievement_pct
        - p.expected_achievement_pct,
        2
    ) AS gap_vs_expected_pct,

    f.active_outlet,
    f.active_outlet_target,
    f.active_outlet_achievement_pct,

    CASE

        WHEN
            f.sales_achievement_pct
            - p.expected_achievement_pct <= -20
        THEN 'CRITICAL'

        WHEN
            f.sales_achievement_pct
            - p.expected_achievement_pct <= -10
        THEN 'WARNING'

        ELSE 'NORMAL'

    END AS performance_status

FROM performance f

CROSS JOIN period p;