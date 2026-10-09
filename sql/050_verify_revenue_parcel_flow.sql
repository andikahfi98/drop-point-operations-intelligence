-- ============================================================
-- 050 - Verify Revenue + Parcel Flow rebaseline
-- Read-only verification queries.
-- ============================================================

-- 1. Canonical facts.
SELECT
    to_regclass('core.fact_revenue') AS fact_revenue,
    to_regclass('core.fact_shipment') AS fact_shipment,
    to_regclass('core.fact_pic_target') AS fact_pic_target,
    to_regclass('core.fact_delivery_target') AS fact_delivery_target;

-- 2. Legacy facts must be gone.
SELECT
    to_regclass('core.fact_sales') AS legacy_fact_sales,
    to_regclass('core.fact_delivery') AS legacy_fact_delivery,
    to_regclass('raw.fact_sales') AS legacy_raw_sales,
    to_regclass('raw.fact_delivery') AS legacy_raw_delivery;

-- Expected: all NULL.

-- 3. Revenue fact columns.
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'core'
  AND table_name = 'fact_revenue'
ORDER BY ordinal_position;

-- 4. Shipment lifecycle columns.
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'core'
  AND table_name = 'fact_shipment'
ORDER BY ordinal_position;

-- 5. Shipment status values.
SELECT shipment_status, COUNT(*)
FROM core.fact_shipment
GROUP BY shipment_status
ORDER BY shipment_status;

-- 6. Parcel flow by Drop Point.
SELECT
    drop_point_name,
    parcel_in_mtd,
    parcel_out_mtd,
    parcel_on_hand,
    parcel_under_6h,
    parcel_6_12h,
    parcel_12_24h,
    parcel_over_24h,
    oldest_parcel_hours,
    avg_dwell_hours,
    dispatch_rate_pct,
    parcel_status
FROM analytics.vw_drop_point_parcel_current
ORDER BY drop_point_name;

-- 7. Operational summary.
SELECT
    drop_point_name,
    revenue,
    revenue_target,
    revenue_achievement_pct,
    revenue_gap_pct,
    revenue_status,
    active_outlet,
    normal_outlet,
    watch_outlet,
    critical_outlet,
    outlet_status,
    parcel_on_hand,
    parcel_over_24h,
    oldest_parcel_hours,
    parcel_status,
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

-- 8. PIC only has revenue + outlet metrics.
SELECT
    drop_point_name,
    pic_name,
    revenue,
    revenue_target,
    revenue_achievement_pct,
    active_outlet,
    active_outlet_target,
    pic_status
FROM analytics.vw_pic_current_performance
ORDER BY drop_point_name, pic_name
LIMIT 30;

-- 9. Issues use logistics reasons only.
SELECT
    drop_point_name,
    issue_type,
    issue_reason,
    issue_count
FROM analytics.vw_drop_point_issue_summary
ORDER BY drop_point_name, issue_count DESC, issue_type;

-- 10. Status values must stay simple.
SELECT DISTINCT revenue_status
FROM analytics.vw_daily_operational_summary
ORDER BY 1;

SELECT DISTINCT outlet_status
FROM analytics.vw_daily_operational_summary
ORDER BY 1;

SELECT DISTINCT parcel_status
FROM analytics.vw_daily_operational_summary
ORDER BY 1;

SELECT DISTINCT delivery_status
FROM analytics.vw_daily_operational_summary
ORDER BY 1;

SELECT DISTINCT overall_status
FROM analytics.vw_daily_operational_summary
ORDER BY 1;

-- 11. Freshness.
SELECT *
FROM analytics.vw_data_freshness;
