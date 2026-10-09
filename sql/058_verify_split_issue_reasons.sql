\echo '=== SHIPMENT ISSUE COLUMNS ==='
SELECT
    table_schema,
    table_name,
    column_name
FROM information_schema.columns
WHERE table_schema IN ('core', 'raw')
  AND table_name = 'fact_shipment'
  AND column_name ILIKE '%issue_reason%'
ORDER BY table_schema, ordinal_position;

\echo ''
\echo '=== DETAIL VIEW ISSUE COLUMN ==='
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'analytics'
  AND table_name = 'vw_shipment_detail'
  AND column_name ILIKE '%issue_reason%'
ORDER BY ordinal_position;

\echo ''
\echo '=== TANGERANG PARCEL ISSUES ==='
SELECT
    issue_type,
    COALESCE(parcel_issue_reason, 'NO_REASON') AS parcel_issue_reason,
    COUNT(*) AS total,
    MAX(parcel_age_hours) AS oldest_hours
FROM analytics.vw_parcel_issues
WHERE drop_point_id = 'DP-TGR-01'
GROUP BY issue_type, COALESCE(parcel_issue_reason, 'NO_REASON')
ORDER BY issue_type, total DESC;

\echo ''
\echo '=== TANGERANG DELIVERY ISSUES ==='
SELECT
    issue_type,
    COALESCE(delivery_issue_reason, 'NO_REASON') AS delivery_issue_reason,
    COUNT(*) AS total,
    MAX(issue_hours) AS max_issue_hours
FROM analytics.vw_delivery_issues
WHERE drop_point_id = 'DP-TGR-01'
GROUP BY issue_type, COALESCE(delivery_issue_reason, 'NO_REASON')
ORDER BY issue_type, total DESC;

\echo ''
\echo '=== CURRENT AT-DP STAGE CHECK ==='
SELECT
    COUNT(*) FILTER (WHERE parcel_issue_reason IS NOT NULL) AS parcel_reason_rows,
    COUNT(*) FILTER (WHERE delivery_issue_reason IS NOT NULL) AS delivery_reason_rows
FROM core.fact_shipment
WHERE drop_point_id = 'DP-TGR-01'
  AND left_dp_ts IS NULL
  AND shipment_status IN ('RECEIVED', 'SORTING', 'READY');
