-- ============================================================
-- 062 - Verify final expedition/logistics domain
-- ============================================================

\pset pager off

\echo '=== FINAL CORE OBJECTS ==='
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema IN ('core', 'app')
  AND table_name IN (
      'dim_unit', 'dim_staff', 'dim_seller', 'dim_courier',
      'dim_responsibility_rule', 'fact_revenue', 'fact_seller_target',
      'fact_delivery_target', 'fact_shipment', 'app_user',
      'user_drop_point_access', 'user_region_access'
  )
ORDER BY table_schema, table_name;

\echo '=== LEGACY OBJECTS SHOULD BE ABSENT ==='
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema IN ('core', 'raw')
  AND table_name IN ('dim_outlet', 'dim_pic', 'fact_pic_target');

\echo '=== DROP POINT TEAM COUNTS ==='
SELECT
    dp.drop_point_name,
    COUNT(*) FILTER (WHERE s.role_code = 'MANAGER') AS manager_count,
    COUNT(*) FILTER (WHERE s.unit_code = 'SELLER' AND s.role_code = 'PIC') AS seller_pic_count,
    COUNT(*) FILTER (WHERE s.unit_code = 'INBOUND' AND s.role_code = 'PIC') AS inbound_pic_count,
    COUNT(*) FILTER (WHERE s.unit_code = 'SORTING' AND s.role_code = 'PIC') AS sorting_pic_count,
    COUNT(*) FILTER (WHERE s.unit_code = 'OUTBOUND' AND s.role_code = 'PIC') AS outbound_pic_count,
    COUNT(*) FILTER (WHERE s.unit_code = 'DELIVERY' AND s.role_code = 'PIC') AS delivery_pic_count,
    COUNT(*) FILTER (WHERE s.unit_code = 'CUSTOMER_SERVICE' AND s.role_code = 'PIC') AS cs_pic_count
FROM core.dim_drop_point dp
LEFT JOIN core.dim_staff s ON dp.drop_point_id = s.drop_point_id
GROUP BY dp.drop_point_id, dp.drop_point_name
ORDER BY dp.drop_point_id;

\echo '=== SELLER SAMPLE ==='
SELECT
    s.seller_id,
    s.seller_code,
    s.seller_name,
    dp.drop_point_name,
    st.staff_name AS seller_pic
FROM core.dim_seller s
JOIN core.dim_drop_point dp ON s.drop_point_id = dp.drop_point_id
JOIN core.dim_staff st ON s.seller_pic_id = st.staff_id
ORDER BY s.seller_id
LIMIT 10;

\echo '=== SHIPMENT FINAL COLUMNS ==='
SELECT ordinal_position, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'core'
  AND table_name = 'fact_shipment'
ORDER BY ordinal_position;

\echo '=== SHIPMENT SAMPLE ==='
SELECT
    shipment_id,
    origin_dp_id,
    destination_dp_id,
    seller_id,
    receiver_name,
    courier_id,
    weight_kg,
    shipment_status,
    parcel_issue_reason,
    delivery_issue_reason,
    return_reason
FROM core.fact_shipment
ORDER BY shipment_id
LIMIT 10;

\echo '=== RESPONSIBILITY SAMPLE ==='
SELECT
    shipment_id,
    shipment_status,
    current_dp_name,
    responsible_unit_code,
    responsible_staff_name,
    manager_name
FROM analytics.vw_shipment_responsibility
WHERE is_at_dp
   OR delivery_class IN ('IN_TRANSIT', 'FAILED', 'LATE', 'RETURNED')
ORDER BY shipment_id
LIMIT 15;


\echo '=== STATUS RESPONSIBILITY ==='
SELECT
    drop_point_name,
    component,
    status,
    responsible_unit_name,
    responsible_staff_name,
    manager_name
FROM analytics.vw_drop_point_status_responsibility
ORDER BY drop_point_name, component;

\echo '=== WEBSITE ACCOUNTS ==='
SELECT
    u.user_id,
    u.full_name,
    u.email,
    u.role_code,
    u.staff_id,
    CASE WHEN u.password_hash IS NULL THEN 'PASSWORD_NOT_SEEDED' ELSE 'HASHED' END AS password_state,
    COUNT(a.drop_point_id) AS drop_point_access_count
FROM app.app_user u
LEFT JOIN app.user_drop_point_access a
  ON u.user_id = a.user_id
 AND a.revoked_at IS NULL
WHERE u.role_code IN ('DP_MANAGER', 'REGIONAL_MANAGER')
GROUP BY u.user_id, u.full_name, u.email, u.role_code, u.staff_id, u.password_hash
ORDER BY u.role_code, u.email;

\echo '=== DAILY SUMMARY ==='
SELECT
    drop_point_name,
    manager_name,
    revenue_status,
    active_seller,
    seller_status,
    parcel_at_dp,
    parcel_over_24h,
    parcel_status,
    on_time_rate_pct,
    delivery_status,
    overall_status
FROM analytics.vw_daily_operational_summary
ORDER BY drop_point_name;

\echo '=== NO OUTLET COLUMNS IN FINAL ANALYTICS ==='
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'analytics'
  AND column_name ILIKE '%outlet%'
ORDER BY table_name, ordinal_position;
