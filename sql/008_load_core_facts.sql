-- =========================================================
-- Drop Point Operations Intelligence
-- 008_load_core_facts.sql
-- RAW -> CORE FACT TABLES
-- =========================================================

BEGIN;


-- =========================================================
-- FULL REFRESH FACT TABLES
-- Prototype batch loading strategy
-- =========================================================

TRUNCATE TABLE
    core.fact_sales,
    core.fact_delivery,
    core.fact_target,
    core.fact_inventory
RESTART IDENTITY;


-- =========================================================
-- 1. FACT SALES
-- Grain:
-- 1 row = 1 product line per invoice
-- =========================================================

INSERT INTO core.fact_sales (
    sales_date,
    invoice_id,
    drop_point_id,
    salesperson_id,
    outlet_id,
    product_id,
    quantity,
    unit_price,
    discount_pct,
    gross_sales,
    discount_amount,
    net_sales,
    unit_cogs,
    total_cogs
)
SELECT
    LEFT(TRIM(date), 10)::DATE,

    TRIM(invoice_id),

    TRIM(drop_point_id),

    TRIM(salesperson_id),

    TRIM(outlet_id),

    TRIM(product_id),

    TRIM(quantity)::INTEGER,

    TRIM(unit_price)::NUMERIC(18,2),

    TRIM(discount_pct)::NUMERIC(7,4),

    TRIM(gross_sales)::NUMERIC(18,2),

    TRIM(discount_amount)::NUMERIC(18,2),

    TRIM(net_sales)::NUMERIC(18,2),

    TRIM(unit_cogs)::NUMERIC(18,2),

    TRIM(total_cogs)::NUMERIC(18,2)

FROM raw.fact_sales;


-- =========================================================
-- 2. FACT DELIVERY
-- Grain:
-- 1 row = 1 shipment
-- =========================================================

INSERT INTO core.fact_delivery (
    shipment_id,
    invoice_id,
    order_date,
    planned_delivery_date,
    actual_delivery_date,
    drop_point_id,
    salesperson_id,
    outlet_id,
    delivery_status,
    sla_hours,
    actual_delivery_hours,
    on_time_flag,
    attempt_count,
    failure_reason
)
SELECT
    TRIM(shipment_id),

    TRIM(invoice_id),

    LEFT(TRIM(order_date), 10)::DATE,

    LEFT(TRIM(planned_delivery_date), 10)::DATE,

    CASE
        WHEN NULLIF(TRIM(actual_delivery_date), '') IS NULL
        THEN NULL
        ELSE LEFT(TRIM(actual_delivery_date), 10)::DATE
    END,

    TRIM(drop_point_id),

    TRIM(salesperson_id),

    TRIM(outlet_id),

    UPPER(TRIM(delivery_status)),

    TRIM(sla_hours)::INTEGER,

    CASE
        WHEN NULLIF(TRIM(actual_delivery_hours), '') IS NULL
        THEN NULL
        ELSE TRIM(actual_delivery_hours)::INTEGER
    END,

    CASE
        WHEN NULLIF(TRIM(on_time_flag), '') IS NULL
        THEN NULL

        WHEN UPPER(TRIM(on_time_flag))
             IN ('Y', 'YES', 'TRUE', '1')
        THEN TRUE

        ELSE FALSE
    END,

    TRIM(attempt_count)::INTEGER,

    NULLIF(TRIM(failure_reason), '')

FROM raw.fact_delivery;


-- =========================================================
-- 3. FACT TARGET
-- Grain:
-- 1 salesperson + 1 Drop Point + 1 month
-- =========================================================

INSERT INTO core.fact_target (
    month_start,
    drop_point_id,
    salesperson_id,
    sales_target,
    active_outlet_target,
    delivery_sla_target_pct
)
SELECT
    LEFT(TRIM(month_start), 10)::DATE,

    TRIM(drop_point_id),

    TRIM(salesperson_id),

    TRIM(sales_target)::NUMERIC(18,2),

    TRIM(active_outlet_target)::INTEGER,

    TRIM(delivery_sla_target_pct)::NUMERIC(6,4)

FROM raw.fact_target;


-- =========================================================
-- 4. FACT INVENTORY
-- Grain:
-- 1 Drop Point + 1 Product + 1 Snapshot Date
-- =========================================================

INSERT INTO core.fact_inventory (
    snapshot_date,
    drop_point_id,
    product_id,
    stock_on_hand,
    safety_stock,
    reorder_flag
)
SELECT
    LEFT(TRIM(snapshot_date), 10)::DATE,

    TRIM(drop_point_id),

    TRIM(product_id),

    TRIM(stock_on_hand)::INTEGER,

    TRIM(safety_stock)::INTEGER,

    CASE
        WHEN UPPER(TRIM(reorder_flag))
             IN ('Y', 'YES', 'TRUE', '1')
        THEN TRUE
        ELSE FALSE
    END

FROM raw.fact_inventory;


COMMIT;