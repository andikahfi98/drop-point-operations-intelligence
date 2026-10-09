-- =========================================================
-- Drop Point Operations Intelligence
-- 018_create_inventory_monitoring.sql
-- INVENTORY MONITORING
-- =========================================================


-- =========================================================
-- 1. LATEST INVENTORY DETAIL
-- Grain:
-- 1 row = 1 Product per Drop Point
-- latest available snapshot
-- =========================================================

CREATE OR REPLACE VIEW analytics.vw_inventory_latest AS

WITH latest_snapshot AS (

    SELECT
        MAX(snapshot_date) AS snapshot_date

    FROM core.fact_inventory
)

SELECT
    i.snapshot_date,

    f.latest_sales_date AS reference_date,

    f.latest_sales_date - i.snapshot_date
        AS snapshot_age_days,

    i.drop_point_id,
    dp.drop_point_name,

    i.product_id,
    p.product_name,
    p.category,

    i.stock_on_hand,
    i.safety_stock,

    i.stock_on_hand - i.safety_stock
        AS stock_gap_qty,

    i.reorder_flag,

    CASE

        WHEN i.stock_on_hand = 0
            THEN 'OUT_OF_STOCK'

        WHEN i.reorder_flag = TRUE
             OR i.stock_on_hand <= i.safety_stock
            THEN 'REORDER_REQUIRED'

        ELSE 'HEALTHY'

    END AS inventory_status,

    CASE

        WHEN f.latest_sales_date - i.snapshot_date > 7
            THEN 'STALE'

        ELSE 'FRESH'

    END AS inventory_data_status

FROM core.fact_inventory i

JOIN latest_snapshot ls
    ON i.snapshot_date = ls.snapshot_date

JOIN core.dim_drop_point dp
    ON i.drop_point_id = dp.drop_point_id

JOIN core.dim_product p
    ON i.product_id = p.product_id

CROSS JOIN analytics.vw_data_freshness f;


-- =========================================================
-- 2. DROP POINT INVENTORY SUMMARY
-- Grain:
-- 1 row = 1 Drop Point
-- =========================================================

CREATE OR REPLACE VIEW
analytics.vw_drop_point_inventory_summary AS

SELECT
    snapshot_date,
    reference_date,
    snapshot_age_days,

    drop_point_id,
    drop_point_name,

    COUNT(*) AS total_product,

    COUNT(*) FILTER (
        WHERE inventory_status = 'HEALTHY'
    ) AS healthy_product,

    COUNT(*) FILTER (
        WHERE inventory_status = 'REORDER_REQUIRED'
    ) AS reorder_required_product,

    COUNT(*) FILTER (
        WHERE inventory_status = 'OUT_OF_STOCK'
    ) AS out_of_stock_product,

    SUM(stock_on_hand)
        AS total_stock_on_hand,

    SUM(safety_stock)
        AS total_safety_stock,

    MAX(inventory_data_status)
        AS inventory_data_status,

    CASE

        WHEN COUNT(*) FILTER (
            WHERE inventory_status = 'OUT_OF_STOCK'
        ) > 0
        THEN 'CRITICAL'

        WHEN COUNT(*) FILTER (
            WHERE inventory_status = 'REORDER_REQUIRED'
        ) > 0
        THEN 'WARNING'

        ELSE 'NORMAL'

    END AS inventory_status

FROM analytics.vw_inventory_latest

GROUP BY
    snapshot_date,
    reference_date,
    snapshot_age_days,
    drop_point_id,
    drop_point_name;