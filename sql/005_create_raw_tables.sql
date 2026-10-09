-- =========================================================
-- Drop Point Operations Intelligence
-- 005_create_raw_tables.sql
-- Raw / staging tables
-- =========================================================


-- =========================
-- DIM DATE
-- =========================

CREATE TABLE IF NOT EXISTS raw.dim_date (
    raw_row_id          BIGSERIAL PRIMARY KEY,
    date                TEXT,
    date_key            TEXT,
    year                TEXT,
    quarter             TEXT,
    month_no            TEXT,
    month_name          TEXT,
    month_start         TEXT,
    week_no             TEXT,
    day_of_month        TEXT,
    day_name            TEXT,
    is_weekend          TEXT,
    is_holiday          TEXT,
    is_working_day      TEXT,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =========================
-- DIM DROP POINT
-- =========================

CREATE TABLE IF NOT EXISTS raw.dim_drop_point (
    raw_row_id          BIGSERIAL PRIMARY KEY,
    drop_point_id       TEXT,
    drop_point_name     TEXT,
    region              TEXT,
    area                TEXT,
    manager_name        TEXT,
    status              TEXT,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =========================
-- DIM SALESPERSON
-- =========================

CREATE TABLE IF NOT EXISTS raw.dim_salesperson (
    raw_row_id          BIGSERIAL PRIMARY KEY,
    salesperson_id      TEXT,
    salesperson_name    TEXT,
    drop_point_id       TEXT,
    role                TEXT,
    join_date           TEXT,
    status              TEXT,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =========================
-- DIM OUTLET
-- =========================

CREATE TABLE IF NOT EXISTS raw.dim_outlet (
    raw_row_id          BIGSERIAL PRIMARY KEY,
    outlet_id           TEXT,
    bp_code             TEXT,
    outlet_name         TEXT,
    drop_point_id       TEXT,
    salesperson_id      TEXT,
    segment             TEXT,
    route_code          TEXT,
    city_area           TEXT,
    active_flag         TEXT,
    open_date           TEXT,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =========================
-- DIM PRODUCT
-- =========================

CREATE TABLE IF NOT EXISTS raw.dim_product (
    raw_row_id          BIGSERIAL PRIMARY KEY,
    product_id          TEXT,
    product_name        TEXT,
    category            TEXT,
    list_price          TEXT,
    standard_cogs       TEXT,
    status              TEXT,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =========================
-- FACT SALES
-- =========================

CREATE TABLE IF NOT EXISTS raw.fact_sales (
    raw_row_id          BIGSERIAL PRIMARY KEY,
    date                TEXT,
    invoice_id          TEXT,
    drop_point_id       TEXT,
    salesperson_id      TEXT,
    outlet_id           TEXT,
    product_id          TEXT,
    quantity            TEXT,
    unit_price          TEXT,
    discount_pct        TEXT,
    gross_sales         TEXT,
    discount_amount     TEXT,
    net_sales           TEXT,
    unit_cogs           TEXT,
    total_cogs          TEXT,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =========================
-- FACT DELIVERY
-- =========================

CREATE TABLE IF NOT EXISTS raw.fact_delivery (
    raw_row_id              BIGSERIAL PRIMARY KEY,
    shipment_id             TEXT,
    invoice_id              TEXT,
    order_date              TEXT,
    planned_delivery_date   TEXT,
    actual_delivery_date    TEXT,
    drop_point_id           TEXT,
    salesperson_id          TEXT,
    outlet_id               TEXT,
    delivery_status         TEXT,
    sla_hours               TEXT,
    actual_delivery_hours   TEXT,
    on_time_flag            TEXT,
    attempt_count           TEXT,
    failure_reason          TEXT,
    loaded_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =========================
-- FACT TARGET
-- =========================

CREATE TABLE IF NOT EXISTS raw.fact_target (
    raw_row_id                  BIGSERIAL PRIMARY KEY,
    month_start                 TEXT,
    drop_point_id               TEXT,
    salesperson_id              TEXT,
    sales_target                TEXT,
    active_outlet_target        TEXT,
    delivery_sla_target_pct     TEXT,
    loaded_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =========================
-- FACT INVENTORY
-- =========================

CREATE TABLE IF NOT EXISTS raw.fact_inventory (
    raw_row_id          BIGSERIAL PRIMARY KEY,
    snapshot_date       TEXT,
    drop_point_id       TEXT,
    product_id          TEXT,
    stock_on_hand       TEXT,
    safety_stock        TEXT,
    reorder_flag        TEXT,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =========================
-- APP ROLE
-- =========================

CREATE TABLE IF NOT EXISTS raw.app_role (
    raw_row_id                  BIGSERIAL PRIMARY KEY,
    role_code                   TEXT,
    role_name                   TEXT,
    data_scope                  TEXT,
    can_view_all_drop_points    TEXT,
    description                 TEXT,
    loaded_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =========================
-- APP USER
-- =========================

CREATE TABLE IF NOT EXISTS raw.app_user (
    raw_row_id              BIGSERIAL PRIMARY KEY,
    user_id                 TEXT,
    full_name               TEXT,
    email                   TEXT,
    password_hash           TEXT,
    role_code               TEXT,
    status                  TEXT,
    must_change_password    TEXT,
    created_at              TEXT,
    loaded_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =========================
-- USER DROP POINT ACCESS
-- =========================

CREATE TABLE IF NOT EXISTS raw.user_drop_point_access (
    raw_row_id          BIGSERIAL PRIMARY KEY,
    user_id             TEXT,
    drop_point_id       TEXT,
    access_type         TEXT,
    is_primary          TEXT,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);