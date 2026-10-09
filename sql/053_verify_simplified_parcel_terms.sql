-- ============================================================
-- 053 - Verify simplified parcel terminology
-- ============================================================

\echo '=== FACT SHIPMENT CORE COLUMNS ==='
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'core'
  AND table_name = 'fact_shipment'
ORDER BY ordinal_position;

\echo '=== OLD TERMS STILL EXPOSED IN ACTIVE DB OBJECTS ==='
SELECT table_schema, table_name, column_name
FROM information_schema.columns
WHERE table_schema IN ('core', 'raw', 'analytics', 'app')
  AND column_name IN (
      'dispatched_ts',
      'dispatched_rows',
      'latest_dispatched_ts',
      'is_on_hand',
      'dwell_hours',
      'parcel_on_hand',
      'avg_dwell_hours',
      'dispatch_rate_pct'
  )
ORDER BY table_schema, table_name, column_name;

\echo '=== NEW PARCEL TERMS ==='
SELECT table_schema, table_name, column_name
FROM information_schema.columns
WHERE table_schema IN ('core', 'raw', 'analytics', 'app')
  AND column_name IN (
      'left_dp_ts',
      'left_dp_rows',
      'latest_left_dp_ts',
      'is_at_dp',
      'dp_hours',
      'parcel_at_dp',
      'avg_dp_hours',
      'parcel_out_pct'
  )
ORDER BY table_schema, table_name, column_name;

\echo '=== TANGERANG PARCEL SAMPLE ==='
SELECT
    drop_point_name,
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
    parcel_status
FROM analytics.vw_drop_point_parcel_current
WHERE drop_point_id = 'DP-TGR-01';
