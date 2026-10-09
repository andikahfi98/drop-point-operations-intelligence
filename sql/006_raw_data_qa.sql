-- =========================================================
-- Drop Point Operations Intelligence
-- 006_raw_data_qa.sql
-- RAW DATA QUALITY CHECK
-- =========================================================


-- =========================================================
-- 1. ROW COUNT
-- =========================================================

SELECT 'dim_date' AS table_name, COUNT(*) AS row_count
FROM raw.dim_date

UNION ALL
SELECT 'dim_drop_point', COUNT(*)
FROM raw.dim_drop_point

UNION ALL
SELECT 'dim_salesperson', COUNT(*)
FROM raw.dim_salesperson

UNION ALL
SELECT 'dim_outlet', COUNT(*)
FROM raw.dim_outlet

UNION ALL
SELECT 'dim_product', COUNT(*)
FROM raw.dim_product

UNION ALL
SELECT 'fact_sales', COUNT(*)
FROM raw.fact_sales

UNION ALL
SELECT 'fact_delivery', COUNT(*)
FROM raw.fact_delivery

UNION ALL
SELECT 'fact_target', COUNT(*)
FROM raw.fact_target

UNION ALL
SELECT 'fact_inventory', COUNT(*)
FROM raw.fact_inventory

UNION ALL
SELECT 'app_role', COUNT(*)
FROM raw.app_role

UNION ALL
SELECT 'app_user', COUNT(*)
FROM raw.app_user

UNION ALL
SELECT 'user_drop_point_access', COUNT(*)
FROM raw.user_drop_point_access

ORDER BY table_name;


-- =========================================================
-- 2. NULL / EMPTY PRIMARY BUSINESS KEYS
-- Expected: all 0
-- =========================================================

SELECT 'dim_drop_point.drop_point_id' AS check_name, COUNT(*) AS issue_count
FROM raw.dim_drop_point
WHERE NULLIF(TRIM(drop_point_id), '') IS NULL

UNION ALL

SELECT 'dim_salesperson.salesperson_id', COUNT(*)
FROM raw.dim_salesperson
WHERE NULLIF(TRIM(salesperson_id), '') IS NULL

UNION ALL

SELECT 'dim_outlet.outlet_id', COUNT(*)
FROM raw.dim_outlet
WHERE NULLIF(TRIM(outlet_id), '') IS NULL

UNION ALL

SELECT 'dim_product.product_id', COUNT(*)
FROM raw.dim_product
WHERE NULLIF(TRIM(product_id), '') IS NULL

UNION ALL

SELECT 'fact_sales.invoice_id', COUNT(*)
FROM raw.fact_sales
WHERE NULLIF(TRIM(invoice_id), '') IS NULL

UNION ALL

SELECT 'fact_delivery.shipment_id', COUNT(*)
FROM raw.fact_delivery
WHERE NULLIF(TRIM(shipment_id), '') IS NULL

UNION ALL

SELECT 'app_user.user_id', COUNT(*)
FROM raw.app_user
WHERE NULLIF(TRIM(user_id), '') IS NULL

UNION ALL

SELECT 'app_user.email', COUNT(*)
FROM raw.app_user
WHERE NULLIF(TRIM(email), '') IS NULL

ORDER BY check_name;


-- =========================================================
-- 3. DUPLICATE DIMENSION KEYS
-- Expected: 0 rows returned
-- =========================================================

SELECT
    drop_point_id,
    COUNT(*) AS duplicate_count
FROM raw.dim_drop_point
GROUP BY drop_point_id
HAVING COUNT(*) > 1;


SELECT
    salesperson_id,
    COUNT(*) AS duplicate_count
FROM raw.dim_salesperson
GROUP BY salesperson_id
HAVING COUNT(*) > 1;


SELECT
    outlet_id,
    COUNT(*) AS duplicate_count
FROM raw.dim_outlet
GROUP BY outlet_id
HAVING COUNT(*) > 1;


SELECT
    bp_code,
    COUNT(*) AS duplicate_count
FROM raw.dim_outlet
GROUP BY bp_code
HAVING COUNT(*) > 1;


SELECT
    product_id,
    COUNT(*) AS duplicate_count
FROM raw.dim_product
GROUP BY product_id
HAVING COUNT(*) > 1;


SELECT
    shipment_id,
    COUNT(*) AS duplicate_count
FROM raw.fact_delivery
GROUP BY shipment_id
HAVING COUNT(*) > 1;


SELECT
    LOWER(TRIM(email)) AS email,
    COUNT(*) AS duplicate_count
FROM raw.app_user
GROUP BY LOWER(TRIM(email))
HAVING COUNT(*) > 1;


-- =========================================================
-- 4. ORPHAN RELATIONSHIPS
-- Expected: issue_count = 0
-- =========================================================

-- Salesperson -> Drop Point
SELECT
    'salesperson_without_drop_point' AS check_name,
    COUNT(*) AS issue_count
FROM raw.dim_salesperson s
LEFT JOIN raw.dim_drop_point dp
    ON s.drop_point_id = dp.drop_point_id
WHERE dp.drop_point_id IS NULL;


-- Outlet -> Drop Point
SELECT
    'outlet_without_drop_point' AS check_name,
    COUNT(*) AS issue_count
FROM raw.dim_outlet o
LEFT JOIN raw.dim_drop_point dp
    ON o.drop_point_id = dp.drop_point_id
WHERE dp.drop_point_id IS NULL;


-- Outlet -> Salesperson
SELECT
    'outlet_without_salesperson' AS check_name,
    COUNT(*) AS issue_count
FROM raw.dim_outlet o
LEFT JOIN raw.dim_salesperson s
    ON o.salesperson_id = s.salesperson_id
WHERE s.salesperson_id IS NULL;


-- Fact Sales -> Outlet
SELECT
    'sales_without_outlet' AS check_name,
    COUNT(*) AS issue_count
FROM raw.fact_sales f
LEFT JOIN raw.dim_outlet o
    ON f.outlet_id = o.outlet_id
WHERE o.outlet_id IS NULL;


-- Fact Sales -> Product
SELECT
    'sales_without_product' AS check_name,
    COUNT(*) AS issue_count
FROM raw.fact_sales f
LEFT JOIN raw.dim_product p
    ON f.product_id = p.product_id
WHERE p.product_id IS NULL;


-- Fact Delivery -> Outlet
SELECT
    'delivery_without_outlet' AS check_name,
    COUNT(*) AS issue_count
FROM raw.fact_delivery f
LEFT JOIN raw.dim_outlet o
    ON f.outlet_id = o.outlet_id
WHERE o.outlet_id IS NULL;


-- Target -> Salesperson
SELECT
    'target_without_salesperson' AS check_name,
    COUNT(*) AS issue_count
FROM raw.fact_target f
LEFT JOIN raw.dim_salesperson s
    ON f.salesperson_id = s.salesperson_id
WHERE s.salesperson_id IS NULL;


-- Inventory -> Product
SELECT
    'inventory_without_product' AS check_name,
    COUNT(*) AS issue_count
FROM raw.fact_inventory f
LEFT JOIN raw.dim_product p
    ON f.product_id = p.product_id
WHERE p.product_id IS NULL;


-- User Access -> User
SELECT
    'access_without_user' AS check_name,
    COUNT(*) AS issue_count
FROM raw.user_drop_point_access a
LEFT JOIN raw.app_user u
    ON a.user_id = u.user_id
WHERE u.user_id IS NULL;


-- User Access -> Drop Point
SELECT
    'access_without_drop_point' AS check_name,
    COUNT(*) AS issue_count
FROM raw.user_drop_point_access a
LEFT JOIN raw.dim_drop_point dp
    ON a.drop_point_id = dp.drop_point_id
WHERE dp.drop_point_id IS NULL;


-- =========================================================
-- 5. CROSS-DIMENSION CONSISTENCY
-- Outlet Drop Point must match Salesperson Drop Point
-- Expected: issue_count = 0
-- =========================================================

SELECT
    COUNT(*) AS outlet_salesperson_drop_point_mismatch
FROM raw.dim_outlet o
JOIN raw.dim_salesperson s
    ON o.salesperson_id = s.salesperson_id
WHERE o.drop_point_id <> s.drop_point_id;


-- =========================================================
-- 6. DELIVERY BASIC QA
-- =========================================================

SELECT
    delivery_status,
    COUNT(*) AS shipment_count
FROM raw.fact_delivery
GROUP BY delivery_status
ORDER BY shipment_count DESC;


SELECT
    on_time_flag,
    COUNT(*) AS shipment_count
FROM raw.fact_delivery
GROUP BY on_time_flag
ORDER BY on_time_flag;


-- Delivered after planned date
SELECT
    COUNT(*) AS delivered_after_planned_date
FROM raw.fact_delivery
WHERE actual_delivery_date IS NOT NULL
  AND actual_delivery_date::date > planned_delivery_date::date;


-- Actual hours exceed SLA
SELECT
    COUNT(*) AS delivery_over_sla
FROM raw.fact_delivery
WHERE NULLIF(actual_delivery_hours, '') IS NOT NULL
  AND actual_delivery_hours::numeric > sla_hours::numeric;


-- =========================================================
-- 7. SALES BASIC QA
-- =========================================================

SELECT
    COUNT(*) AS invalid_quantity
FROM raw.fact_sales
WHERE quantity::numeric <= 0;


SELECT
    COUNT(*) AS invalid_net_sales
FROM raw.fact_sales
WHERE net_sales::numeric < 0;


SELECT
    COUNT(*) AS invalid_discount_pct
FROM raw.fact_sales
WHERE discount_pct::numeric < 0
   OR discount_pct::numeric > 1;


-- =========================================================
-- 8. AUTHORIZATION QA
-- =========================================================

SELECT
    role_code,
    COUNT(*) AS user_count
FROM raw.app_user
GROUP BY role_code
ORDER BY role_code;


SELECT
    u.user_id,
    u.full_name,
    u.role_code,
    a.drop_point_id
FROM raw.app_user u
LEFT JOIN raw.user_drop_point_access a
    ON u.user_id = a.user_id
ORDER BY u.user_id, a.drop_point_id;