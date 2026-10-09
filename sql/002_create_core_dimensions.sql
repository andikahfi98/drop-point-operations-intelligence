-- =========================================================
-- Drop Point Operations Intelligence
-- 002_create_core_dimensions.sql
-- =========================================================

CREATE TABLE IF NOT EXISTS core.dim_date (
    date_key            INTEGER PRIMARY KEY,
    date                DATE NOT NULL UNIQUE,
    year                SMALLINT NOT NULL,
    quarter             VARCHAR(2) NOT NULL,
    month_no            SMALLINT NOT NULL,
    month_name          VARCHAR(15) NOT NULL,
    month_start         DATE NOT NULL,
    week_no             SMALLINT NOT NULL,
    day_of_month        SMALLINT NOT NULL,
    day_name            VARCHAR(15) NOT NULL,
    is_weekend          BOOLEAN NOT NULL,
    is_holiday          BOOLEAN NOT NULL,
    is_working_day      BOOLEAN NOT NULL,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_month_no
        CHECK (month_no BETWEEN 1 AND 12),

    CONSTRAINT chk_quarter
        CHECK (quarter IN ('Q1', 'Q2', 'Q3', 'Q4'))
);


CREATE TABLE IF NOT EXISTS core.dim_drop_point (
    drop_point_id       VARCHAR(20) PRIMARY KEY,
    drop_point_name     VARCHAR(100) NOT NULL,
    region              VARCHAR(100) NOT NULL,
    area                VARCHAR(100) NOT NULL,
    manager_name        VARCHAR(100),
    status              VARCHAR(20) NOT NULL,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


CREATE TABLE IF NOT EXISTS core.dim_salesperson (
    salesperson_id      VARCHAR(20) PRIMARY KEY,
    salesperson_name    VARCHAR(100) NOT NULL,
    drop_point_id       VARCHAR(20) NOT NULL,
    role                VARCHAR(50) NOT NULL,
    join_date           DATE,
    status              VARCHAR(20) NOT NULL,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_salesperson_drop_point
        FOREIGN KEY (drop_point_id)
        REFERENCES core.dim_drop_point(drop_point_id)
);


CREATE TABLE IF NOT EXISTS core.dim_outlet (
    outlet_id           VARCHAR(20) PRIMARY KEY,
    bp_code             VARCHAR(20) NOT NULL UNIQUE,
    outlet_name         VARCHAR(150) NOT NULL,
    drop_point_id       VARCHAR(20) NOT NULL,
    salesperson_id      VARCHAR(20) NOT NULL,
    segment             VARCHAR(20),
    route_code          VARCHAR(30),
    city_area           VARCHAR(100),
    active_flag         BOOLEAN NOT NULL,
    open_date           DATE,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_outlet_drop_point
        FOREIGN KEY (drop_point_id)
        REFERENCES core.dim_drop_point(drop_point_id),

    CONSTRAINT fk_outlet_salesperson
        FOREIGN KEY (salesperson_id)
        REFERENCES core.dim_salesperson(salesperson_id)
);


CREATE TABLE IF NOT EXISTS core.dim_product (
    product_id          VARCHAR(20) PRIMARY KEY,
    product_name        VARCHAR(150) NOT NULL,
    category            VARCHAR(100) NOT NULL,
    list_price          NUMERIC(18,2) NOT NULL,
    standard_cogs       NUMERIC(18,2) NOT NULL,
    status              VARCHAR(20) NOT NULL,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_product_list_price
        CHECK (list_price >= 0),

    CONSTRAINT chk_product_cogs
        CHECK (standard_cogs >= 0)
);