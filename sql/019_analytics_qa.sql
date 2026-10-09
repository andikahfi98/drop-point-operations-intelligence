-- =========================================================
-- Drop Point Operations Intelligence
-- 019_analytics_qa.sql
-- ANALYTICS QA & RECONCILIATION
-- =========================================================


-- =========================================================
-- 1. RAW VS CORE ROW COUNTS
-- =========================================================

SELECT
    'FACT SALES ROW COUNT' AS check_name,
    (SELECT COUNT(*) FROM raw.fact_sales) AS raw_count,
    (SELECT COUNT(*) FROM core.fact_sales) AS core_count,

    CASE
        WHEN (SELECT COUNT(*) FROM raw.fact_sales)
           = (SELECT COUNT(*) FROM core.fact_sales)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

UNION ALL

SELECT
    'FACT DELIVERY ROW COUNT',
    (SELECT COUNT(*) FROM raw.fact_delivery),
    (SELECT COUNT(*) FROM core.fact_delivery),

    CASE
        WHEN (SELECT COUNT(*) FROM raw.fact_delivery)
           = (SELECT COUNT(*) FROM core.fact_delivery)
        THEN 'PASS'
        ELSE 'FAIL'
    END

UNION ALL

SELECT
    'FACT TARGET ROW COUNT',
    (SELECT COUNT(*) FROM raw.fact_target),
    (SELECT COUNT(*) FROM core.fact_target),

    CASE
        WHEN (SELECT COUNT(*) FROM raw.fact_target)
           = (SELECT COUNT(*) FROM core.fact_target)
        THEN 'PASS'
        ELSE 'FAIL'
    END

UNION ALL

SELECT
    'FACT INVENTORY ROW COUNT',
    (SELECT COUNT(*) FROM raw.fact_inventory),
    (SELECT COUNT(*) FROM core.fact_inventory),

    CASE
        WHEN (SELECT COUNT(*) FROM raw.fact_inventory)
           = (SELECT COUNT(*) FROM core.fact_inventory)
        THEN 'PASS'
        ELSE 'FAIL'
    END;


-- =========================================================
-- 2. DELIVERY CLASSIFICATION RECONCILIATION
-- =========================================================

SELECT
    drop_point_name,
    total_shipment,

    (
        on_time_delivery
        + late_delivery
        + failed_delivery
        + overdue_delivery
        + open_delivery
    ) AS classified_shipment,

    CASE
        WHEN total_shipment =
            (
                on_time_delivery
                + late_delivery
                + failed_delivery
                + overdue_delivery
                + open_delivery
            )
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM analytics.vw_drop_point_current_delivery

ORDER BY drop_point_name;


-- =========================================================
-- 3. SALES PACE GAP VALIDATION
-- =========================================================

SELECT
    drop_point_name,

    sales_achievement_pct,
    expected_achievement_pct,
    sales_pace_gap_pp,

    ROUND(
        sales_achievement_pct
        - expected_achievement_pct,
        2
    ) AS recalculated_gap_pp,

    CASE
        WHEN ROUND(sales_pace_gap_pp, 2)
           = ROUND(
                sales_achievement_pct
                - expected_achievement_pct,
                2
             )
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM analytics.vw_daily_operational_summary

ORDER BY drop_point_name;


-- =========================================================
-- 4. DELIVERY SLA GAP VALIDATION
-- =========================================================

SELECT
    drop_point_name,

    on_time_rate_pct,
    delivery_sla_target_pct,
    delivery_sla_gap_pp,

    ROUND(
        on_time_rate_pct
        - delivery_sla_target_pct,
        2
    ) AS recalculated_gap_pp,

    CASE
        WHEN ROUND(delivery_sla_gap_pp, 2)
           = ROUND(
                on_time_rate_pct
                - delivery_sla_target_pct,
                2
             )
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM analytics.vw_daily_operational_summary

ORDER BY drop_point_name;


-- =========================================================
-- 5. OUTLET ATTENTION RECONCILIATION
-- =========================================================

SELECT
    drop_point_name,

    total_monitored_outlet,

    critical_outlet,
    warning_outlet,
    normal_outlet,

    (
        critical_outlet
        + warning_outlet
        + normal_outlet
    ) AS classified_outlet,

    CASE
        WHEN total_monitored_outlet =
            (
                critical_outlet
                + warning_outlet
                + normal_outlet
            )
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM analytics.vw_drop_point_outlet_attention_summary

ORDER BY drop_point_name;


-- =========================================================
-- 6. INVENTORY RECONCILIATION
-- =========================================================

SELECT
    drop_point_name,

    total_product,

    healthy_product,
    reorder_required_product,
    out_of_stock_product,

    (
        healthy_product
        + reorder_required_product
        + out_of_stock_product
    ) AS classified_product,

    CASE
        WHEN total_product =
            (
                healthy_product
                + reorder_required_product
                + out_of_stock_product
            )
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM analytics.vw_drop_point_inventory_summary

ORDER BY drop_point_name;


-- =========================================================
-- 7. DUPLICATE ANALYTICS GRAIN CHECK
-- Expected result = 0 rows
-- =========================================================

SELECT
    month_start,
    drop_point_id,
    COUNT(*) AS duplicate_count

FROM analytics.vw_drop_point_sales_monthly

GROUP BY
    month_start,
    drop_point_id

HAVING COUNT(*) > 1;


-- =========================================================
-- 8. DAILY SUMMARY GRAIN CHECK
-- Expected result = 0 rows
-- =========================================================

SELECT
    as_of_date,
    drop_point_id,
    COUNT(*) AS duplicate_count

FROM analytics.vw_daily_operational_summary

GROUP BY
    as_of_date,
    drop_point_id

HAVING COUNT(*) > 1;

