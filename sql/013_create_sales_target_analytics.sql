-- =========================================================
-- Drop Point Operations Intelligence
-- 013_create_sales_target_analytics.sql
-- SALES & TARGET ANALYTICS
-- =========================================================


-- =========================================================
-- 1. MONTHLY SALESPERSON PERFORMANCE
-- Grain:
-- 1 row = 1 salesperson per month
-- =========================================================

CREATE OR REPLACE VIEW analytics.vw_salesperson_monthly_performance AS

WITH sales AS (

    SELECT
        DATE_TRUNC('month', sales_date)::DATE AS month_start,
        drop_point_id,
        salesperson_id,

        SUM(quantity) AS total_quantity,
        COUNT(DISTINCT invoice_id) AS total_transaction,
        COUNT(DISTINCT outlet_id) AS active_outlet,

        SUM(gross_sales) AS gross_sales,
        SUM(discount_amount) AS discount_amount,
        SUM(net_sales) AS net_sales,
        SUM(total_cogs) AS total_cogs

    FROM core.fact_sales

    GROUP BY
        DATE_TRUNC('month', sales_date)::DATE,
        drop_point_id,
        salesperson_id
)

SELECT
    t.month_start,

    t.drop_point_id,
    dp.drop_point_name,

    t.salesperson_id,
    sp.salesperson_name,

    COALESCE(s.total_quantity, 0) AS total_quantity,
    COALESCE(s.total_transaction, 0) AS total_transaction,
    COALESCE(s.active_outlet, 0) AS active_outlet,

    COALESCE(s.gross_sales, 0) AS gross_sales,
    COALESCE(s.discount_amount, 0) AS discount_amount,
    COALESCE(s.net_sales, 0) AS net_sales,
    COALESCE(s.total_cogs, 0) AS total_cogs,

    t.sales_target,
    t.active_outlet_target,
    ROUND(
    t.delivery_sla_target_pct * 100,
    2) AS delivery_sla_target_pct,

    COALESCE(s.net_sales, 0) - t.sales_target
        AS sales_variance,

    ROUND(
        100.0
        * COALESCE(s.net_sales, 0)
        / NULLIF(t.sales_target, 0),
        2
    ) AS sales_achievement_pct,

    COALESCE(s.active_outlet, 0)
        - t.active_outlet_target
        AS active_outlet_variance,

    ROUND(
        100.0
        * COALESCE(s.active_outlet, 0)
        / NULLIF(t.active_outlet_target, 0),
        2
    ) AS active_outlet_achievement_pct

FROM core.fact_target t

JOIN core.dim_drop_point dp
    ON t.drop_point_id = dp.drop_point_id

JOIN core.dim_salesperson sp
    ON t.salesperson_id = sp.salesperson_id

LEFT JOIN sales s
    ON t.month_start = s.month_start
    AND t.drop_point_id = s.drop_point_id
    AND t.salesperson_id = s.salesperson_id;

-- =========================================================
-- 2. MONTHLY DROP POINT SALES PERFORMANCE
-- Grain:
-- 1 row = 1 Drop Point per month
-- =========================================================

CREATE OR REPLACE VIEW analytics.vw_drop_point_sales_monthly AS

WITH sales AS (

    SELECT
        DATE_TRUNC('month', sales_date)::DATE AS month_start,
        drop_point_id,

        SUM(quantity) AS total_quantity,
        COUNT(DISTINCT invoice_id) AS total_transaction,
        COUNT(DISTINCT outlet_id) AS active_outlet,

        SUM(gross_sales) AS gross_sales,
        SUM(discount_amount) AS discount_amount,
        SUM(net_sales) AS net_sales,
        SUM(total_cogs) AS total_cogs

    FROM core.fact_sales

    GROUP BY
        DATE_TRUNC('month', sales_date)::DATE,
        drop_point_id
),

target AS (

    SELECT
        month_start,
        drop_point_id,

        SUM(sales_target) AS sales_target,
        SUM(active_outlet_target) AS active_outlet_target,

        AVG(delivery_sla_target_pct) AS delivery_sla_target_pct

    FROM core.fact_target

    GROUP BY
        month_start,
        drop_point_id
)

SELECT
    t.month_start,

    t.drop_point_id,
    dp.drop_point_name,
    dp.region,
    dp.area,

    COALESCE(s.total_quantity, 0) AS total_quantity,
    COALESCE(s.total_transaction, 0) AS total_transaction,
    COALESCE(s.active_outlet, 0) AS active_outlet,

    COALESCE(s.gross_sales, 0) AS gross_sales,
    COALESCE(s.discount_amount, 0) AS discount_amount,
    COALESCE(s.net_sales, 0) AS net_sales,
    COALESCE(s.total_cogs, 0) AS total_cogs,

    t.sales_target,
    t.active_outlet_target,

    ROUND(
    t.delivery_sla_target_pct * 100,
    2 ) AS delivery_sla_target_pct,

    COALESCE(s.net_sales, 0) - t.sales_target
        AS sales_variance,

    ROUND(
        100.0
        * COALESCE(s.net_sales, 0)
        / NULLIF(t.sales_target, 0),
        2
    ) AS sales_achievement_pct,

    COALESCE(s.active_outlet, 0)
        - t.active_outlet_target
        AS active_outlet_variance,

    ROUND(
        100.0
        * COALESCE(s.active_outlet, 0)
        / NULLIF(t.active_outlet_target, 0),
        2
    ) AS active_outlet_achievement_pct

FROM target t

JOIN core.dim_drop_point dp
    ON t.drop_point_id = dp.drop_point_id

LEFT JOIN sales s
    ON t.month_start = s.month_start
    AND t.drop_point_id = s.drop_point_id;

-- =========================================================
-- 3. MONTHLY OUTLET SALES PERFORMANCE
-- Grain:
-- 1 row = 1 outlet per month
-- =========================================================

CREATE OR REPLACE VIEW analytics.vw_outlet_sales_monthly AS

SELECT
    DATE_TRUNC('month', f.sales_date)::DATE
        AS month_start,

    f.drop_point_id,
    dp.drop_point_name,

    f.salesperson_id,
    sp.salesperson_name,

    f.outlet_id,
    o.bp_code,
    o.outlet_name,
    o.segment,
    o.route_code,

    COUNT(DISTINCT f.invoice_id)
        AS total_transaction,

    SUM(f.quantity)
        AS total_quantity,

    SUM(f.gross_sales)
        AS gross_sales,

    SUM(f.discount_amount)
        AS discount_amount,

    SUM(f.net_sales)
        AS net_sales,

    SUM(f.total_cogs)
        AS total_cogs,

    MAX(f.sales_date)
        AS last_transaction_date

FROM core.fact_sales f

JOIN core.dim_drop_point dp
    ON f.drop_point_id = dp.drop_point_id

JOIN core.dim_salesperson sp
    ON f.salesperson_id = sp.salesperson_id

JOIN core.dim_outlet o
    ON f.outlet_id = o.outlet_id

GROUP BY
    DATE_TRUNC('month', f.sales_date)::DATE,

    f.drop_point_id,
    dp.drop_point_name,

    f.salesperson_id,
    sp.salesperson_name,

    f.outlet_id,
    o.bp_code,
    o.outlet_name,
    o.segment,
    o.route_code;