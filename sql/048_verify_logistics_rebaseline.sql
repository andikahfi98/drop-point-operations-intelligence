-- ============================================================
-- 048 - Verify logistics domain rebaseline
-- Read-only verification queries.
-- ============================================================

-- 1. Product / inventory tables must be gone.
SELECT
    to_regclass('core.dim_product') AS core_dim_product,
    to_regclass('core.fact_inventory') AS core_fact_inventory,
    to_regclass('raw.dim_product') AS raw_dim_product,
    to_regclass('raw.fact_inventory') AS raw_fact_inventory;

-- Expected: all NULL.


-- 2. Correct core model must exist.
SELECT
    to_regclass('core.dim_pic') AS dim_pic,
    to_regclass('core.dim_outlet') AS dim_outlet,
    to_regclass('core.fact_sales') AS fact_sales,
    to_regclass('core.fact_pic_target') AS fact_pic_target,
    to_regclass('core.fact_delivery') AS fact_delivery,
    to_regclass('core.fact_delivery_target') AS fact_delivery_target;


-- 3. fact_sales must not contain retail/product columns.
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'core'
  AND table_name = 'fact_sales'
ORDER BY ordinal_position;


-- 4. Delivery must not be assigned to PIC.
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'core'
  AND table_name = 'fact_delivery'
  AND column_name IN ('pic_id', 'salesperson_id');

-- Expected: 0 rows.


-- 5. Delivery SLA target must be Drop Point level, not PIC level.
SELECT
    month_start,
    drop_point_id,
    delivery_sla_target_pct
FROM core.fact_delivery_target
ORDER BY month_start DESC, drop_point_id
LIMIT 20;


-- 6. Runtime status must only use NORMAL / WATCH / CRITICAL.
SELECT DISTINCT overall_status
FROM analytics.vw_daily_operational_summary
ORDER BY 1;

SELECT DISTINCT sales_status
FROM analytics.vw_daily_operational_summary
ORDER BY 1;

SELECT DISTINCT outlet_status
FROM analytics.vw_daily_operational_summary
ORDER BY 1;

SELECT DISTINCT delivery_status
FROM analytics.vw_daily_operational_summary
ORDER BY 1;


-- 7. Operational summary sanity check.
SELECT
    drop_point_name,
    net_sales,
    sales_target,
    sales_achievement_pct,
    expected_achievement_pct,
    sales_gap_pct,
    sales_status,
    normal_outlet,
    watch_outlet,
    critical_outlet,
    outlet_status,
    total_shipment,
    completed_delivery,
    in_transit_delivery,
    overdue_delivery,
    on_time_rate_pct,
    delivery_sla_target_pct,
    delivery_status,
    overall_status
FROM analytics.vw_daily_operational_summary
ORDER BY drop_point_name;


-- 8. PIC must contain sales/outlet metrics only.
SELECT
    drop_point_name,
    pic_name,
    net_sales,
    sales_target,
    sales_achievement_pct,
    active_outlet,
    active_outlet_target,
    pic_status
FROM analytics.vw_pic_current_performance
ORDER BY drop_point_name, pic_name
LIMIT 30;


-- 9. Freshness now covers only sales + delivery.
SELECT *
FROM analytics.vw_data_freshness;
