-- =========================================================
-- Drop Point Operations Intelligence
-- 003_create_core_facts.sql
-- =========================================================


-- =========================================================
-- FACT SALES
-- Grain:
-- 1 row = 1 product line dalam 1 invoice
-- =========================================================

CREATE TABLE IF NOT EXISTS core.fact_sales (
    sales_line_id       BIGSERIAL PRIMARY KEY,

    sales_date          DATE NOT NULL,
    invoice_id          VARCHAR(30) NOT NULL,

    drop_point_id       VARCHAR(20) NOT NULL,
    salesperson_id      VARCHAR(20) NOT NULL,
    outlet_id           VARCHAR(20) NOT NULL,
    product_id          VARCHAR(20) NOT NULL,

    quantity            INTEGER NOT NULL,
    unit_price          NUMERIC(18,2) NOT NULL,
    discount_pct        NUMERIC(7,4) NOT NULL,

    gross_sales         NUMERIC(18,2) NOT NULL,
    discount_amount     NUMERIC(18,2) NOT NULL,
    net_sales           NUMERIC(18,2) NOT NULL,

    unit_cogs           NUMERIC(18,2) NOT NULL,
    total_cogs          NUMERIC(18,2) NOT NULL,

    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_sales_date
        FOREIGN KEY (sales_date)
        REFERENCES core.dim_date(date),

    CONSTRAINT fk_sales_drop_point
        FOREIGN KEY (drop_point_id)
        REFERENCES core.dim_drop_point(drop_point_id),

    CONSTRAINT fk_sales_salesperson
        FOREIGN KEY (salesperson_id)
        REFERENCES core.dim_salesperson(salesperson_id),

    CONSTRAINT fk_sales_outlet
        FOREIGN KEY (outlet_id)
        REFERENCES core.dim_outlet(outlet_id),

    CONSTRAINT fk_sales_product
        FOREIGN KEY (product_id)
        REFERENCES core.dim_product(product_id),

    CONSTRAINT uq_sales_invoice_product
        UNIQUE (invoice_id, product_id),

    CONSTRAINT chk_sales_quantity
        CHECK (quantity > 0),

    CONSTRAINT chk_sales_unit_price
        CHECK (unit_price >= 0),

    CONSTRAINT chk_sales_discount_pct
        CHECK (discount_pct BETWEEN 0 AND 1),

    CONSTRAINT chk_sales_values
        CHECK (
            gross_sales >= 0
            AND discount_amount >= 0
            AND net_sales >= 0
            AND unit_cogs >= 0
            AND total_cogs >= 0
        )
);


-- =========================================================
-- FACT DELIVERY
-- Grain:
-- 1 row = 1 shipment
-- =========================================================

CREATE TABLE IF NOT EXISTS core.fact_delivery (
    shipment_id             VARCHAR(30) PRIMARY KEY,
    invoice_id              VARCHAR(30) NOT NULL,

    order_date              DATE NOT NULL,
    planned_delivery_date   DATE NOT NULL,
    actual_delivery_date    DATE,

    drop_point_id           VARCHAR(20) NOT NULL,
    salesperson_id          VARCHAR(20) NOT NULL,
    outlet_id               VARCHAR(20) NOT NULL,

    delivery_status         VARCHAR(30) NOT NULL,

    sla_hours               INTEGER NOT NULL,
    actual_delivery_hours   INTEGER,

    on_time_flag            BOOLEAN,
    attempt_count           INTEGER NOT NULL,

    failure_reason          VARCHAR(255),

    loaded_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_delivery_order_date
        FOREIGN KEY (order_date)
        REFERENCES core.dim_date(date),

    CONSTRAINT fk_delivery_drop_point
        FOREIGN KEY (drop_point_id)
        REFERENCES core.dim_drop_point(drop_point_id),

    CONSTRAINT fk_delivery_salesperson
        FOREIGN KEY (salesperson_id)
        REFERENCES core.dim_salesperson(salesperson_id),

    CONSTRAINT fk_delivery_outlet
        FOREIGN KEY (outlet_id)
        REFERENCES core.dim_outlet(outlet_id),

    CONSTRAINT chk_delivery_sla
        CHECK (sla_hours > 0),

    CONSTRAINT chk_delivery_actual_hours
        CHECK (
            actual_delivery_hours IS NULL
            OR actual_delivery_hours >= 0
        ),

    CONSTRAINT chk_delivery_attempt
        CHECK (attempt_count >= 1)
);


-- =========================================================
-- FACT TARGET
-- Grain:
-- 1 row = 1 salesperson per Drop Point per month
-- =========================================================

CREATE TABLE IF NOT EXISTS core.fact_target (
    month_start                 DATE NOT NULL,
    drop_point_id               VARCHAR(20) NOT NULL,
    salesperson_id              VARCHAR(20) NOT NULL,

    sales_target                NUMERIC(18,2) NOT NULL,
    active_outlet_target        INTEGER NOT NULL,
    delivery_sla_target_pct     NUMERIC(6,4) NOT NULL,

    loaded_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_fact_target
        PRIMARY KEY (
            month_start,
            drop_point_id,
            salesperson_id
        ),

    CONSTRAINT fk_target_month
        FOREIGN KEY (month_start)
        REFERENCES core.dim_date(date),

    CONSTRAINT fk_target_drop_point
        FOREIGN KEY (drop_point_id)
        REFERENCES core.dim_drop_point(drop_point_id),

    CONSTRAINT fk_target_salesperson
        FOREIGN KEY (salesperson_id)
        REFERENCES core.dim_salesperson(salesperson_id),

    CONSTRAINT chk_target_sales
        CHECK (sales_target >= 0),

    CONSTRAINT chk_target_active_outlet
        CHECK (active_outlet_target >= 0),

    CONSTRAINT chk_target_sla
        CHECK (delivery_sla_target_pct BETWEEN 0 AND 1)
);


-- =========================================================
-- FACT INVENTORY
-- Grain:
-- 1 row = 1 product per Drop Point per snapshot date
-- =========================================================

CREATE TABLE IF NOT EXISTS core.fact_inventory (
    snapshot_date       DATE NOT NULL,
    drop_point_id       VARCHAR(20) NOT NULL,
    product_id          VARCHAR(20) NOT NULL,

    stock_on_hand       INTEGER NOT NULL,
    safety_stock        INTEGER NOT NULL,
    reorder_flag        BOOLEAN NOT NULL,

    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_fact_inventory
        PRIMARY KEY (
            snapshot_date,
            drop_point_id,
            product_id
        ),

    CONSTRAINT fk_inventory_date
        FOREIGN KEY (snapshot_date)
        REFERENCES core.dim_date(date),

    CONSTRAINT fk_inventory_drop_point
        FOREIGN KEY (drop_point_id)
        REFERENCES core.dim_drop_point(drop_point_id),

    CONSTRAINT fk_inventory_product
        FOREIGN KEY (product_id)
        REFERENCES core.dim_product(product_id),

    CONSTRAINT chk_inventory_stock
        CHECK (stock_on_hand >= 0),

    CONSTRAINT chk_inventory_safety_stock
        CHECK (safety_stock >= 0)
);