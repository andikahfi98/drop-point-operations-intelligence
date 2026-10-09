-- ============================================================
-- 047 - Rebaseline logistics domain
--
-- Purpose
-- - Remove retail/FMCG concepts: Product, SKU, Inventory, Stock,
--   Quantity, Unit Price, Discount, COGS.
-- - Rename Salesperson master to PIC.
-- - Keep PIC responsible for sales + outlet coverage only.
-- - Keep delivery performance at Drop Point / logistics level.
-- - Split PIC targets from Drop Point delivery SLA targets.
-- - Rebuild the runtime analytics layer with logistics semantics.
--
-- IMPORTANT
-- - Designed for the current prototype schema after migration 046.
-- - Wrapped in one transaction: any failure rolls everything back.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. PRE-FLIGHT DOMAIN CONSISTENCY CHECKS
-- ============================================================

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM core.fact_sales
        GROUP BY invoice_id
        HAVING COUNT(DISTINCT drop_point_id) > 1
            OR COUNT(DISTINCT salesperson_id) > 1
            OR COUNT(DISTINCT outlet_id) > 1
    ) THEN
        RAISE EXCEPTION
            'Cannot rebaseline fact_sales: one or more invoices map to multiple Drop Points/PICs/outlets.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM core.fact_target
        GROUP BY month_start, drop_point_id
        HAVING COUNT(DISTINCT delivery_sla_target_pct) > 1
    ) THEN
        RAISE EXCEPTION
            'Cannot split delivery target: delivery SLA differs between PIC rows within the same Drop Point/month.';
    END IF;
END $$;


-- ============================================================
-- 2. ANALYTICS IS DERIVED DATA: REBUILD CLEANLY
-- ============================================================

DROP SCHEMA IF EXISTS analytics CASCADE;
CREATE SCHEMA analytics;


-- ============================================================
-- 3. SALESPERSON -> PIC MASTER TERMINOLOGY
-- ============================================================

ALTER TABLE core.dim_salesperson
    RENAME TO dim_pic;

ALTER TABLE core.dim_pic
    RENAME COLUMN salesperson_id TO pic_id;

ALTER TABLE core.dim_pic
    RENAME COLUMN salesperson_name TO pic_name;

ALTER TABLE core.dim_outlet
    RENAME COLUMN salesperson_id TO pic_id;

ALTER TABLE raw.dim_salesperson
    RENAME TO dim_pic;

ALTER TABLE raw.dim_pic
    RENAME COLUMN salesperson_id TO pic_id;

ALTER TABLE raw.dim_pic
    RENAME COLUMN salesperson_name TO pic_name;

ALTER TABLE raw.dim_outlet
    RENAME COLUMN salesperson_id TO pic_id;


-- ============================================================
-- 4. CLEAN SALES FACT
-- Grain: 1 row = 1 invoice / business transaction
-- ============================================================

CREATE TABLE core.fact_sales_v2 (
    invoice_id          VARCHAR(30) PRIMARY KEY,
    sales_date          DATE NOT NULL,
    transaction_ts      TIMESTAMP NOT NULL,
    drop_point_id       VARCHAR(20) NOT NULL,
    pic_id              VARCHAR(20) NOT NULL,
    outlet_id           VARCHAR(20) NOT NULL,
    net_sales           NUMERIC(18,2) NOT NULL,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_sales_v2_date
        FOREIGN KEY (sales_date)
        REFERENCES core.dim_date(date),

    CONSTRAINT fk_sales_v2_drop_point
        FOREIGN KEY (drop_point_id)
        REFERENCES core.dim_drop_point(drop_point_id),

    CONSTRAINT fk_sales_v2_pic
        FOREIGN KEY (pic_id)
        REFERENCES core.dim_pic(pic_id),

    CONSTRAINT fk_sales_v2_outlet
        FOREIGN KEY (outlet_id)
        REFERENCES core.dim_outlet(outlet_id),

    CONSTRAINT chk_sales_v2_net_sales
        CHECK (net_sales >= 0)
);

INSERT INTO core.fact_sales_v2 (
    invoice_id,
    sales_date,
    transaction_ts,
    drop_point_id,
    pic_id,
    outlet_id,
    net_sales,
    loaded_at
)
SELECT
    invoice_id,
    MIN(sales_date) AS sales_date,
    MIN(COALESCE(transaction_ts, sales_date::timestamp + INTERVAL '12 hours'))
        AS transaction_ts,
    MIN(drop_point_id) AS drop_point_id,
    MIN(salesperson_id) AS pic_id,
    MIN(outlet_id) AS outlet_id,
    ROUND(SUM(net_sales), 2) AS net_sales,
    MIN(loaded_at) AS loaded_at
FROM core.fact_sales
GROUP BY invoice_id;

DROP TABLE core.fact_sales;
ALTER TABLE core.fact_sales_v2
    RENAME TO fact_sales;

CREATE INDEX idx_fact_sales_sales_date
    ON core.fact_sales(sales_date);

CREATE INDEX idx_fact_sales_transaction_ts
    ON core.fact_sales(transaction_ts);

CREATE INDEX idx_fact_sales_drop_point
    ON core.fact_sales(drop_point_id);

CREATE INDEX idx_fact_sales_pic
    ON core.fact_sales(pic_id);

CREATE INDEX idx_fact_sales_outlet
    ON core.fact_sales(outlet_id);


-- Rebuild RAW sales without retail/product fields.
DROP TABLE raw.fact_sales;

CREATE TABLE raw.fact_sales (
    raw_row_id          BIGSERIAL PRIMARY KEY,
    date                TEXT,
    transaction_ts      TEXT,
    invoice_id          TEXT,
    drop_point_id       TEXT,
    pic_id              TEXT,
    outlet_id           TEXT,
    net_sales           TEXT,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO raw.fact_sales (
    date,
    transaction_ts,
    invoice_id,
    drop_point_id,
    pic_id,
    outlet_id,
    net_sales
)
SELECT
    sales_date::text,
    transaction_ts::text,
    invoice_id,
    drop_point_id,
    pic_id,
    outlet_id,
    net_sales::text
FROM core.fact_sales;


-- ============================================================
-- 5. SPLIT TARGETS BY BUSINESS RESPONSIBILITY
-- PIC: sales + outlet coverage
-- Drop Point: delivery SLA
-- ============================================================

CREATE TABLE core.fact_pic_target (
    month_start             DATE NOT NULL,
    drop_point_id           VARCHAR(20) NOT NULL,
    pic_id                  VARCHAR(20) NOT NULL,
    sales_target            NUMERIC(18,2) NOT NULL,
    active_outlet_target    INTEGER NOT NULL,
    loaded_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (
        month_start,
        drop_point_id,
        pic_id
    ),

    CONSTRAINT fk_pic_target_month
        FOREIGN KEY (month_start)
        REFERENCES core.dim_date(date),

    CONSTRAINT fk_pic_target_drop_point
        FOREIGN KEY (drop_point_id)
        REFERENCES core.dim_drop_point(drop_point_id),

    CONSTRAINT fk_pic_target_pic
        FOREIGN KEY (pic_id)
        REFERENCES core.dim_pic(pic_id),

    CONSTRAINT chk_pic_target_sales
        CHECK (sales_target >= 0),

    CONSTRAINT chk_pic_target_outlet
        CHECK (active_outlet_target >= 0)
);

INSERT INTO core.fact_pic_target (
    month_start,
    drop_point_id,
    pic_id,
    sales_target,
    active_outlet_target,
    loaded_at
)
SELECT
    month_start,
    drop_point_id,
    salesperson_id,
    sales_target,
    active_outlet_target,
    loaded_at
FROM core.fact_target;


CREATE TABLE core.fact_delivery_target (
    month_start                 DATE NOT NULL,
    drop_point_id               VARCHAR(20) NOT NULL,
    delivery_sla_target_pct     NUMERIC(6,4) NOT NULL,
    loaded_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (
        month_start,
        drop_point_id
    ),

    CONSTRAINT fk_delivery_target_month
        FOREIGN KEY (month_start)
        REFERENCES core.dim_date(date),

    CONSTRAINT fk_delivery_target_drop_point
        FOREIGN KEY (drop_point_id)
        REFERENCES core.dim_drop_point(drop_point_id),

    CONSTRAINT chk_delivery_target_sla
        CHECK (delivery_sla_target_pct BETWEEN 0 AND 1)
);

INSERT INTO core.fact_delivery_target (
    month_start,
    drop_point_id,
    delivery_sla_target_pct,
    loaded_at
)
SELECT
    month_start,
    drop_point_id,
    MAX(delivery_sla_target_pct),
    MIN(loaded_at)
FROM core.fact_target
GROUP BY
    month_start,
    drop_point_id;

DROP TABLE core.fact_target;
DROP TABLE raw.fact_target;

CREATE TABLE raw.fact_pic_target (
    raw_row_id              BIGSERIAL PRIMARY KEY,
    month_start             TEXT,
    drop_point_id           TEXT,
    pic_id                  TEXT,
    sales_target            TEXT,
    active_outlet_target    TEXT,
    loaded_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE raw.fact_delivery_target (
    raw_row_id                  BIGSERIAL PRIMARY KEY,
    month_start                 TEXT,
    drop_point_id               TEXT,
    delivery_sla_target_pct     TEXT,
    loaded_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO raw.fact_pic_target (
    month_start,
    drop_point_id,
    pic_id,
    sales_target,
    active_outlet_target
)
SELECT
    month_start::text,
    drop_point_id,
    pic_id,
    sales_target::text,
    active_outlet_target::text
FROM core.fact_pic_target;

INSERT INTO raw.fact_delivery_target (
    month_start,
    drop_point_id,
    delivery_sla_target_pct
)
SELECT
    month_start::text,
    drop_point_id,
    delivery_sla_target_pct::text
FROM core.fact_delivery_target;


-- ============================================================
-- 6. DELIVERY BELONGS TO LOGISTICS / DROP POINT
-- Remove PIC assignment from delivery fact.
-- PIC can still be derived from outlet ownership for context only.
-- ============================================================

ALTER TABLE core.fact_delivery
    DROP CONSTRAINT IF EXISTS fk_delivery_salesperson;

ALTER TABLE core.fact_delivery
    DROP COLUMN salesperson_id;

-- Rebuild RAW delivery from CORE with lifecycle timestamps.
DROP TABLE raw.fact_delivery;

CREATE TABLE raw.fact_delivery (
    raw_row_id              BIGSERIAL PRIMARY KEY,
    shipment_id             TEXT,
    invoice_id              TEXT,
    order_date              TEXT,
    planned_delivery_date   TEXT,
    actual_delivery_date    TEXT,
    drop_point_id           TEXT,
    outlet_id               TEXT,
    delivery_status         TEXT,
    sla_hours               TEXT,
    actual_delivery_hours   TEXT,
    on_time_flag            TEXT,
    attempt_count           TEXT,
    failure_reason          TEXT,
    shipment_ts             TEXT,
    target_delivery_ts      TEXT,
    actual_delivery_ts      TEXT,
    loaded_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO raw.fact_delivery (
    shipment_id,
    invoice_id,
    order_date,
    planned_delivery_date,
    actual_delivery_date,
    drop_point_id,
    outlet_id,
    delivery_status,
    sla_hours,
    actual_delivery_hours,
    on_time_flag,
    attempt_count,
    failure_reason,
    shipment_ts,
    target_delivery_ts,
    actual_delivery_ts
)
SELECT
    shipment_id,
    invoice_id,
    order_date::text,
    planned_delivery_date::text,
    actual_delivery_date::text,
    drop_point_id,
    outlet_id,
    delivery_status,
    sla_hours::text,
    actual_delivery_hours::text,
    CASE
        WHEN on_time_flag IS TRUE THEN 'Y'
        WHEN on_time_flag IS FALSE THEN 'N'
        ELSE NULL
    END,
    attempt_count::text,
    failure_reason,
    shipment_ts::text,
    target_delivery_ts::text,
    actual_delivery_ts::text
FROM core.fact_delivery;

-- Delivery invoice relationship is now explicit.
ALTER TABLE core.fact_delivery
    ADD CONSTRAINT fk_delivery_invoice
    FOREIGN KEY (invoice_id)
    REFERENCES core.fact_sales(invoice_id)
    NOT VALID;

ALTER TABLE core.fact_delivery
    VALIDATE CONSTRAINT fk_delivery_invoice;


-- ============================================================
-- 7. REMOVE PRODUCT / INVENTORY DOMAIN COMPLETELY
-- ============================================================

DROP TABLE IF EXISTS core.fact_inventory;
DROP TABLE IF EXISTS raw.fact_inventory;
DROP TABLE IF EXISTS core.dim_product;
DROP TABLE IF EXISTS raw.dim_product;

ALTER TABLE app.simulation_run_log
    DROP COLUMN IF EXISTS inventory_rows;


-- ============================================================
-- 8. DATA FRESHNESS
-- ============================================================

CREATE VIEW analytics.vw_data_freshness AS
WITH simulation AS (
    SELECT
        current_business_date,
        current_business_time,
        current_business_date + current_business_time AS simulation_ts
    FROM app.simulation_state
    WHERE simulation_name = 'operations_demo'
),
freshness AS (
    SELECT
        (
            SELECT MAX(f.sales_date)
            FROM core.fact_sales f
            CROSS JOIN simulation s
            WHERE f.transaction_ts <= s.simulation_ts
        ) AS latest_sales_date,
        (
            SELECT MAX(f.transaction_ts)
            FROM core.fact_sales f
            CROSS JOIN simulation s
            WHERE f.transaction_ts <= s.simulation_ts
        ) AS latest_sales_ts,
        (
            SELECT MAX(COALESCE(d.shipment_ts::date, d.order_date))
            FROM core.fact_delivery d
            CROSS JOIN simulation s
            WHERE d.shipment_ts IS NULL
               OR d.shipment_ts <= s.simulation_ts
        ) AS latest_delivery_date,
        (
            SELECT MAX(d.shipment_ts)
            FROM core.fact_delivery d
            CROSS JOIN simulation s
            WHERE d.shipment_ts <= s.simulation_ts
        ) AS latest_shipment_ts,
        (
            SELECT MAX(d.actual_delivery_ts)
            FROM core.fact_delivery d
            CROSS JOIN simulation s
            WHERE d.actual_delivery_ts <= s.simulation_ts
        ) AS latest_actual_delivery_ts
)
SELECT
    f.latest_sales_date,
    f.latest_delivery_date,
    f.latest_sales_ts,
    f.latest_shipment_ts,
    f.latest_actual_delivery_ts,
    s.simulation_ts,
    CASE
        WHEN f.latest_sales_ts IS NULL THEN NULL
        ELSE ROUND(
            EXTRACT(EPOCH FROM (s.simulation_ts - f.latest_sales_ts)) / 60.0,
            2
        )
    END AS sales_freshness_minutes,
    CASE
        WHEN f.latest_shipment_ts IS NULL THEN NULL
        ELSE ROUND(
            EXTRACT(EPOCH FROM (s.simulation_ts - f.latest_shipment_ts)) / 60.0,
            2
        )
    END AS delivery_freshness_minutes
FROM freshness f
CROSS JOIN simulation s;


-- ============================================================
-- 9. CURRENT PERIOD
-- ============================================================

CREATE VIEW analytics.vw_current_period AS
WITH params AS (
    SELECT
        current_business_date AS as_of_date,
        DATE_TRUNC('month', current_business_date)::date AS month_start
    FROM app.simulation_state
    WHERE simulation_name = 'operations_demo'
)
SELECT
    p.as_of_date,
    p.month_start,
    (p.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_end,
    COUNT(*) FILTER (WHERE d.is_working_day = TRUE) AS total_working_days,
    COUNT(*) FILTER (
        WHERE d.is_working_day = TRUE
          AND d.date <= p.as_of_date
    ) AS elapsed_working_days,
    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE d.is_working_day = TRUE
              AND d.date <= p.as_of_date
        )
        / NULLIF(COUNT(*) FILTER (WHERE d.is_working_day = TRUE), 0),
        2
    ) AS expected_achievement_pct
FROM params p
JOIN core.dim_date d
    ON d.month_start = p.month_start
GROUP BY
    p.as_of_date,
    p.month_start;


-- ============================================================
-- 10. SALES / PIC ANALYTICS
-- ============================================================

CREATE VIEW analytics.vw_pic_monthly_performance AS
WITH sales AS (
    SELECT
        DATE_TRUNC('month', sales_date)::date AS month_start,
        drop_point_id,
        pic_id,
        COUNT(*) AS total_transaction,
        COUNT(DISTINCT outlet_id) AS active_outlet,
        SUM(net_sales) AS net_sales
    FROM core.fact_sales
    GROUP BY 1, 2, 3
)
SELECT
    t.month_start,
    t.drop_point_id,
    dp.drop_point_name,
    t.pic_id,
    p.pic_name,
    COALESCE(s.total_transaction, 0) AS total_transaction,
    COALESCE(s.active_outlet, 0) AS active_outlet,
    COALESCE(s.net_sales, 0) AS net_sales,
    t.sales_target,
    t.active_outlet_target,
    COALESCE(s.net_sales, 0) - t.sales_target AS sales_variance,
    ROUND(
        100.0 * COALESCE(s.net_sales, 0) / NULLIF(t.sales_target, 0),
        2
    ) AS sales_achievement_pct,
    COALESCE(s.active_outlet, 0) - t.active_outlet_target
        AS active_outlet_variance,
    ROUND(
        100.0 * COALESCE(s.active_outlet, 0)
        / NULLIF(t.active_outlet_target, 0),
        2
    ) AS active_outlet_achievement_pct
FROM core.fact_pic_target t
JOIN core.dim_drop_point dp
    ON t.drop_point_id = dp.drop_point_id
JOIN core.dim_pic p
    ON t.pic_id = p.pic_id
LEFT JOIN sales s
    ON t.month_start = s.month_start
   AND t.drop_point_id = s.drop_point_id
   AND t.pic_id = s.pic_id;


CREATE VIEW analytics.vw_drop_point_sales_monthly AS
WITH sales AS (
    SELECT
        DATE_TRUNC('month', sales_date)::date AS month_start,
        drop_point_id,
        COUNT(*) AS total_transaction,
        COUNT(DISTINCT outlet_id) AS active_outlet,
        SUM(net_sales) AS net_sales
    FROM core.fact_sales
    GROUP BY 1, 2
),
target AS (
    SELECT
        month_start,
        drop_point_id,
        SUM(sales_target) AS sales_target,
        SUM(active_outlet_target) AS active_outlet_target
    FROM core.fact_pic_target
    GROUP BY 1, 2
)
SELECT
    t.month_start,
    t.drop_point_id,
    dp.drop_point_name,
    dp.region,
    dp.area,
    COALESCE(s.total_transaction, 0) AS total_transaction,
    COALESCE(s.active_outlet, 0) AS active_outlet,
    COALESCE(s.net_sales, 0) AS net_sales,
    t.sales_target,
    t.active_outlet_target,
    COALESCE(s.net_sales, 0) - t.sales_target AS sales_variance,
    ROUND(
        100.0 * COALESCE(s.net_sales, 0) / NULLIF(t.sales_target, 0),
        2
    ) AS sales_achievement_pct,
    COALESCE(s.active_outlet, 0) - t.active_outlet_target
        AS active_outlet_variance,
    ROUND(
        100.0 * COALESCE(s.active_outlet, 0)
        / NULLIF(t.active_outlet_target, 0),
        2
    ) AS active_outlet_achievement_pct
FROM target t
JOIN core.dim_drop_point dp
    ON t.drop_point_id = dp.drop_point_id
LEFT JOIN sales s
    ON t.month_start = s.month_start
   AND t.drop_point_id = s.drop_point_id;


CREATE VIEW analytics.vw_drop_point_current_performance AS
WITH period AS (
    SELECT * FROM analytics.vw_current_period
)
SELECT
    p.as_of_date,
    p.month_start,
    p.total_working_days,
    p.elapsed_working_days,
    p.expected_achievement_pct,
    s.drop_point_id,
    s.drop_point_name,
    s.region,
    s.area,
    s.net_sales,
    s.sales_target,
    s.sales_achievement_pct,
    ROUND(s.sales_achievement_pct - p.expected_achievement_pct, 2)
        AS gap_vs_expected_pct,
    s.active_outlet,
    s.active_outlet_target,
    s.active_outlet_achievement_pct,
    CASE
        WHEN s.sales_achievement_pct - p.expected_achievement_pct <= -20
            THEN 'CRITICAL'
        WHEN s.sales_achievement_pct - p.expected_achievement_pct <= -10
            THEN 'WATCH'
        ELSE 'NORMAL'
    END AS performance_status
FROM analytics.vw_drop_point_sales_monthly s
CROSS JOIN period p
WHERE s.month_start = p.month_start;


CREATE VIEW analytics.vw_pic_current_performance AS
WITH period AS (
    SELECT
        as_of_date,
        month_start,
        expected_achievement_pct
    FROM analytics.vw_current_period
),
base AS (
    SELECT
        p.as_of_date,
        s.month_start,
        s.drop_point_id,
        s.drop_point_name,
        s.pic_id,
        s.pic_name,
        s.net_sales,
        s.sales_target,
        s.sales_achievement_pct,
        p.expected_achievement_pct,
        ROUND(s.sales_achievement_pct - p.expected_achievement_pct, 2)
            AS sales_gap_pct,
        s.active_outlet,
        s.active_outlet_target,
        s.active_outlet_achievement_pct
    FROM analytics.vw_pic_monthly_performance s
    CROSS JOIN period p
    WHERE s.month_start = p.month_start
)
SELECT
    *,
    CASE
        WHEN sales_target IS NULL OR sales_target <= 0
            THEN 'NO_DATA'
        ELSE 'SUFFICIENT_DATA'
    END AS pic_data_status,
    CASE
        WHEN sales_target IS NULL OR sales_target <= 0
            THEN 'NORMAL'
        WHEN sales_gap_pct <= -20
            THEN 'CRITICAL'
        WHEN sales_gap_pct < 0
            THEN 'WATCH'
        ELSE 'NORMAL'
    END AS pic_status
FROM base;


-- ============================================================
-- 11. DELIVERY ANALYTICS
-- ============================================================

CREATE VIEW analytics.vw_delivery_detail AS
WITH reference_time AS (
    SELECT
        COALESCE(
            (
                SELECT current_business_date + current_business_time
                FROM app.simulation_state
                WHERE simulation_name = 'operations_demo'
                LIMIT 1
            ),
            CURRENT_TIMESTAMP::timestamp
        ) AS reference_ts
),
base AS (
    SELECT
        d.*,
        CASE
            WHEN d.actual_delivery_ts IS NOT NULL
             AND d.shipment_ts IS NOT NULL
            THEN ROUND(
                EXTRACT(EPOCH FROM (d.actual_delivery_ts - d.shipment_ts))
                / 3600.0
            )::integer
            ELSE NULL
        END AS calc_delivery_hours,
        CASE
            WHEN d.actual_delivery_ts IS NOT NULL
             AND d.target_delivery_ts IS NOT NULL
            THEN GREATEST(
                0,
                ROUND(
                    EXTRACT(EPOCH FROM (
                        d.actual_delivery_ts - d.target_delivery_ts
                    )) / 3600.0
                )::integer
            )
            ELSE NULL
        END AS calc_late_hours
    FROM core.fact_delivery d
)
SELECT
    d.shipment_id,
    d.invoice_id,
    d.order_date,
    d.target_delivery_ts::date AS planned_delivery_date,
    d.actual_delivery_ts::date AS actual_delivery_date,
    d.drop_point_id,
    dp.drop_point_name,
    dp.region,
    dp.area,
    d.outlet_id,
    o.bp_code,
    o.outlet_name,
    o.pic_id,
    p.pic_name,
    d.delivery_status,
    d.sla_hours,
    d.calc_delivery_hours AS actual_delivery_hours,
    CASE
        WHEN d.delivery_status = 'FAILED' THEN FALSE
        WHEN d.actual_delivery_ts IS NULL
          OR d.target_delivery_ts IS NULL THEN NULL
        WHEN d.actual_delivery_ts <= d.target_delivery_ts THEN TRUE
        ELSE FALSE
    END AS on_time_flag,
    d.attempt_count,
    d.failure_reason,
    CASE
        WHEN d.delivery_status = 'FAILED' THEN 'FAILED'
        WHEN d.delivery_status = 'IN_TRANSIT' THEN 'IN_TRANSIT'
        WHEN d.actual_delivery_ts IS NOT NULL
         AND d.target_delivery_ts IS NOT NULL
         AND d.actual_delivery_ts > d.target_delivery_ts THEN 'LATE'
        WHEN d.actual_delivery_ts IS NOT NULL
         AND d.target_delivery_ts IS NOT NULL
         AND d.actual_delivery_ts <= d.target_delivery_ts THEN 'ON_TIME'
        ELSE 'UNKNOWN'
    END AS delivery_class,
    CASE
        WHEN d.actual_delivery_ts IS NOT NULL
         AND d.target_delivery_ts IS NOT NULL
         AND d.actual_delivery_ts > d.target_delivery_ts
            THEN TRUE
        ELSE FALSE
    END AS is_late,
    CASE
        WHEN d.delivery_status = 'IN_TRANSIT'
         AND d.target_delivery_ts IS NOT NULL
         AND rt.reference_ts > d.target_delivery_ts
            THEN TRUE
        ELSE FALSE
    END AS is_overdue,
    d.calc_late_hours AS delay_hours,
    d.shipment_ts,
    d.target_delivery_ts,
    d.actual_delivery_ts,
    CASE
        WHEN d.delivery_status = 'FAILED'
          OR d.actual_delivery_ts IS NOT NULL
            THEN TRUE
        ELSE FALSE
    END AS is_completed,
    (d.actual_delivery_ts IS NOT NULL) AS is_delivered,
    (d.delivery_status = 'FAILED') AS is_failed,
    d.calc_late_hours AS late_hours,
    CASE
        WHEN d.delivery_status = 'IN_TRANSIT'
         AND d.target_delivery_ts IS NOT NULL
         AND rt.reference_ts > d.target_delivery_ts
        THEN ROUND(
            EXTRACT(EPOCH FROM (rt.reference_ts - d.target_delivery_ts))
            / 3600.0
        )::integer
        ELSE 0
    END AS overdue_hours,
    rt.reference_ts
FROM base d
JOIN core.dim_drop_point dp
    ON d.drop_point_id = dp.drop_point_id
JOIN core.dim_outlet o
    ON d.outlet_id = o.outlet_id
JOIN core.dim_pic p
    ON o.pic_id = p.pic_id
CROSS JOIN reference_time rt;


CREATE VIEW analytics.vw_drop_point_current_delivery AS
WITH period AS (
    SELECT as_of_date, month_start
    FROM analytics.vw_current_period
),
target AS (
    SELECT
        p.as_of_date,
        p.month_start,
        t.drop_point_id,
        ROUND(t.delivery_sla_target_pct * 100, 2) AS sla_target_pct
    FROM core.fact_delivery_target t
    CROSS JOIN period p
    WHERE t.month_start = p.month_start
),
delivery AS (
    SELECT
        d.drop_point_id,
        COUNT(*) AS total_shipment,
        COUNT(*) FILTER (WHERE d.delivery_class = 'ON_TIME') AS on_time_delivery,
        COUNT(*) FILTER (WHERE d.delivery_class = 'LATE') AS late_delivery,
        COUNT(*) FILTER (WHERE d.delivery_class = 'FAILED') AS failed_delivery,
        COUNT(*) FILTER (WHERE d.delivery_class = 'IN_TRANSIT') AS in_transit_delivery,
        COUNT(*) FILTER (
            WHERE d.delivery_class = 'IN_TRANSIT'
              AND d.is_overdue = TRUE
        ) AS overdue_delivery,
        COUNT(*) FILTER (WHERE d.is_completed = TRUE) AS completed_delivery,
        COUNT(*) FILTER (WHERE d.is_delivered = TRUE) AS successful_delivery,
        ROUND(
            AVG(d.actual_delivery_hours) FILTER (WHERE d.is_delivered = TRUE),
            2
        ) AS avg_delivery_hours,
        ROUND(
            AVG(d.late_hours) FILTER (WHERE d.delivery_class = 'LATE'),
            2
        ) AS avg_delay_hours
    FROM analytics.vw_delivery_detail d
    CROSS JOIN period p
    WHERE COALESCE(d.shipment_ts::date, d.order_date)
          BETWEEN p.month_start AND p.as_of_date
    GROUP BY d.drop_point_id
),
base AS (
    SELECT
        t.as_of_date,
        t.month_start,
        t.drop_point_id,
        dp.drop_point_name,
        COALESCE(d.total_shipment, 0) AS total_shipment,
        COALESCE(d.on_time_delivery, 0) AS on_time_delivery,
        COALESCE(d.late_delivery, 0) AS late_delivery,
        COALESCE(d.failed_delivery, 0) AS failed_delivery,
        COALESCE(d.overdue_delivery, 0) AS overdue_delivery,
        COALESCE(d.completed_delivery, 0) AS completed_delivery,
        COALESCE(d.successful_delivery, 0) AS successful_delivery,
        COALESCE(d.in_transit_delivery, 0) AS in_transit_delivery,
        d.avg_delivery_hours,
        d.avg_delay_hours,
        t.sla_target_pct
    FROM target t
    JOIN core.dim_drop_point dp
        ON t.drop_point_id = dp.drop_point_id
    LEFT JOIN delivery d
        ON t.drop_point_id = d.drop_point_id
)
SELECT
    *,
    ROUND(
        100.0 * on_time_delivery / NULLIF(completed_delivery, 0),
        2
    ) AS on_time_rate_pct,
    ROUND(
        100.0 * late_delivery / NULLIF(completed_delivery, 0),
        2
    ) AS late_rate_pct,
    ROUND(
        100.0 * failed_delivery / NULLIF(completed_delivery, 0),
        2
    ) AS failure_rate_pct,
    ROUND(
        100.0 * successful_delivery / NULLIF(completed_delivery, 0),
        2
    ) AS delivery_success_rate_pct
FROM base;


CREATE VIEW analytics.vw_drop_point_current_delivery_status AS
SELECT
    d.*,
    ROUND(d.on_time_rate_pct - d.sla_target_pct, 2) AS sla_gap_pct,
    CASE
        WHEN d.on_time_rate_pct IS NULL THEN NULL
        ELSE GREATEST(d.sla_target_pct - d.on_time_rate_pct, 0)
    END AS sla_shortfall_pct,
    CASE
        WHEN d.completed_delivery < 20 THEN 'NORMAL'
        WHEN d.on_time_rate_pct > d.sla_target_pct - 10 THEN 'NORMAL'
        WHEN d.on_time_rate_pct >= d.sla_target_pct - 20 THEN 'WATCH'
        ELSE 'CRITICAL'
    END AS sla_performance_status,
    CASE
        WHEN d.completed_delivery = 0 THEN 'NO_DATA'
        WHEN d.completed_delivery < 20 THEN 'INSUFFICIENT_DATA'
        ELSE 'SUFFICIENT_DATA'
    END AS delivery_data_status
FROM analytics.vw_drop_point_current_delivery d;


CREATE VIEW analytics.vw_delivery_issues AS
SELECT
    d.shipment_id,
    d.invoice_id,
    d.order_date,
    d.planned_delivery_date,
    d.actual_delivery_date,
    d.drop_point_id,
    d.drop_point_name,
    d.region,
    d.area,
    d.outlet_id,
    d.bp_code,
    d.outlet_name,
    d.pic_id,
    d.pic_name,
    d.delivery_status,
    d.delivery_class,
    CASE
        WHEN d.delivery_class = 'FAILED' THEN 'FAILED'
        WHEN d.delivery_class = 'LATE' THEN 'LATE'
        WHEN d.delivery_class = 'IN_TRANSIT'
         AND d.is_overdue = TRUE THEN 'OVERDUE'
        ELSE NULL
    END AS issue_type,
    d.sla_hours,
    d.actual_delivery_hours,
    CASE
        WHEN d.delivery_class = 'LATE' THEN d.late_hours
        WHEN d.delivery_class = 'IN_TRANSIT'
         AND d.is_overdue = TRUE THEN d.overdue_hours
        ELSE NULL
    END AS issue_hours,
    d.late_hours,
    d.overdue_hours,
    d.attempt_count,
    d.failure_reason,
    d.shipment_ts,
    d.target_delivery_ts,
    d.actual_delivery_ts
FROM analytics.vw_delivery_detail d
WHERE d.delivery_class IN ('LATE', 'FAILED')
   OR (
        d.delivery_class = 'IN_TRANSIT'
        AND d.is_overdue = TRUE
   );


-- ============================================================
-- 12. OUTLET ANALYTICS
-- ============================================================

CREATE VIEW analytics.vw_outlet_activity AS
WITH params AS (
    SELECT as_of_date, month_start
    FROM analytics.vw_current_period
),
sales_activity AS (
    SELECT
        f.outlet_id,
        MAX(f.sales_date) AS last_transaction_date,
        COUNT(*) FILTER (
            WHERE f.sales_date >= (SELECT month_start FROM params)
        ) AS current_month_transaction,
        SUM(f.net_sales) FILTER (
            WHERE f.sales_date >= (SELECT month_start FROM params)
        ) AS current_month_sales
    FROM core.fact_sales f
    GROUP BY f.outlet_id
)
SELECT
    p.as_of_date,
    o.drop_point_id,
    dp.drop_point_name,
    o.pic_id,
    pic.pic_name,
    o.outlet_id,
    o.bp_code,
    o.outlet_name,
    o.segment,
    o.route_code,
    o.active_flag,
    s.last_transaction_date,
    CASE
        WHEN s.last_transaction_date IS NULL THEN NULL
        ELSE p.as_of_date - s.last_transaction_date
    END AS days_since_last_transaction,
    COALESCE(s.current_month_transaction, 0) AS current_month_transaction,
    COALESCE(s.current_month_sales, 0) AS current_month_sales,
    CASE
        WHEN o.active_flag = FALSE THEN 'INACTIVE_MASTER'
        WHEN s.last_transaction_date IS NULL THEN 'NO_SALES_HISTORY'
        WHEN p.as_of_date - s.last_transaction_date >= 14 THEN 'INACTIVE_14D'
        WHEN p.as_of_date - s.last_transaction_date >= 7 THEN 'WATCH_7D'
        ELSE 'ACTIVE'
    END AS activity_status
FROM core.dim_outlet o
JOIN core.dim_drop_point dp
    ON o.drop_point_id = dp.drop_point_id
JOIN core.dim_pic pic
    ON o.pic_id = pic.pic_id
LEFT JOIN sales_activity s
    ON o.outlet_id = s.outlet_id
CROSS JOIN params p;


CREATE VIEW analytics.vw_outlet_current_delivery_issues AS
WITH params AS (
    SELECT as_of_date, month_start
    FROM analytics.vw_current_period
)
SELECT
    d.outlet_id,
    COUNT(*) AS total_delivery,
    COUNT(*) FILTER (WHERE d.delivery_class = 'LATE') AS late_delivery,
    COUNT(*) FILTER (WHERE d.delivery_class = 'FAILED') AS failed_delivery,
    COUNT(*) FILTER (
        WHERE d.delivery_class = 'IN_TRANSIT'
          AND d.is_overdue = TRUE
    ) AS overdue_delivery,
    COUNT(*) FILTER (WHERE d.delivery_class = 'IN_TRANSIT')
        AS in_transit_delivery,
    COUNT(*) FILTER (WHERE d.is_completed = TRUE) AS completed_delivery,
    COUNT(*) FILTER (
        WHERE d.delivery_class IN ('LATE', 'FAILED')
           OR (
                d.delivery_class = 'IN_TRANSIT'
                AND d.is_overdue = TRUE
           )
    ) AS total_issue
FROM analytics.vw_delivery_detail d
CROSS JOIN params p
WHERE COALESCE(d.shipment_ts::date, d.order_date)
      BETWEEN p.month_start AND p.as_of_date
GROUP BY d.outlet_id;


CREATE VIEW analytics.vw_outlet_attention AS
WITH base AS (
    SELECT
        a.as_of_date,
        a.drop_point_id,
        a.drop_point_name,
        a.pic_id,
        a.pic_name,
        a.outlet_id,
        a.bp_code,
        a.outlet_name,
        a.last_transaction_date,
        a.days_since_last_transaction,
        a.current_month_transaction,
        a.current_month_sales,
        a.activity_status,
        COALESCE(d.total_delivery, 0) AS total_delivery,
        COALESCE(d.late_delivery, 0) AS late_delivery,
        COALESCE(d.failed_delivery, 0) AS failed_delivery,
        COALESCE(d.overdue_delivery, 0) AS overdue_delivery,
        COALESCE(d.completed_delivery, 0) AS completed_delivery,
        COALESCE(d.in_transit_delivery, 0) AS in_transit_delivery,
        COALESCE(d.total_issue, 0) AS total_issue,
        GREATEST(
            COALESCE(d.completed_delivery, 0)
            - COALESCE(d.late_delivery, 0)
            - COALESCE(d.failed_delivery, 0),
            0
        ) AS on_time_delivery,
        dp.sla_target_pct
    FROM analytics.vw_outlet_activity a
    LEFT JOIN analytics.vw_outlet_current_delivery_issues d
        ON a.outlet_id = d.outlet_id
    LEFT JOIN analytics.vw_drop_point_current_delivery dp
        ON a.drop_point_id = dp.drop_point_id
    WHERE a.active_flag = TRUE
),
metrics AS (
    SELECT
        *,
        CASE
            WHEN completed_delivery = 0 THEN NULL
            ELSE ROUND(100.0 * on_time_delivery / completed_delivery, 2)
        END AS outlet_on_time_rate_pct
    FROM base
),
status_calc AS (
    SELECT
        *,
        CASE
            WHEN completed_delivery = 0 THEN 'NO_DATA'
            WHEN completed_delivery < 20 THEN 'INSUFFICIENT_DATA'
            ELSE 'SUFFICIENT_DATA'
        END AS delivery_data_status,
        CASE
            WHEN sla_target_pct IS NULL OR completed_delivery < 20
                THEN 'NORMAL'
            WHEN outlet_on_time_rate_pct > sla_target_pct - 10
                THEN 'NORMAL'
            WHEN outlet_on_time_rate_pct >= sla_target_pct - 20
                THEN 'WATCH'
            ELSE 'CRITICAL'
        END AS delivery_performance_status
    FROM metrics
)
SELECT
    as_of_date,
    drop_point_id,
    drop_point_name,
    pic_id,
    pic_name,
    outlet_id,
    bp_code,
    outlet_name,
    last_transaction_date,
    days_since_last_transaction,
    current_month_transaction,
    current_month_sales,
    activity_status,
    total_delivery,
    completed_delivery,
    in_transit_delivery,
    on_time_delivery,
    late_delivery,
    failed_delivery,
    overdue_delivery,
    outlet_on_time_rate_pct,
    sla_target_pct,
    CASE
        WHEN outlet_on_time_rate_pct IS NULL THEN NULL
        ELSE ROUND(outlet_on_time_rate_pct - sla_target_pct, 2)
    END AS delivery_sla_gap_pct,
    CASE
        WHEN outlet_on_time_rate_pct IS NULL THEN NULL
        ELSE GREATEST(ROUND(sla_target_pct - outlet_on_time_rate_pct, 2), 0)
    END AS sla_shortfall_pct,
    delivery_performance_status,
    delivery_data_status,
    total_issue,
    CASE
        WHEN activity_status IN ('NO_SALES_HISTORY', 'INACTIVE_14D')
            THEN 'CRITICAL'
        WHEN delivery_performance_status = 'CRITICAL'
            THEN 'CRITICAL'
        WHEN activity_status = 'WATCH_7D'
            THEN 'WATCH'
        WHEN delivery_performance_status = 'WATCH'
            THEN 'WATCH'
        ELSE 'NORMAL'
    END AS attention_status
FROM status_calc;


CREATE VIEW analytics.vw_drop_point_outlet_attention_summary AS
SELECT
    as_of_date,
    drop_point_id,
    drop_point_name,
    COUNT(*) AS total_monitored_outlet,
    COUNT(*) FILTER (WHERE attention_status = 'NORMAL') AS normal_outlet,
    COUNT(*) FILTER (WHERE attention_status = 'WATCH') AS watch_outlet,
    COUNT(*) FILTER (WHERE attention_status = 'CRITICAL') AS critical_outlet,
    COUNT(*) FILTER (WHERE activity_status = 'INACTIVE_14D') AS inactive_14d_outlet,
    COUNT(*) FILTER (WHERE activity_status = 'WATCH_7D') AS watch_7d_outlet
FROM analytics.vw_outlet_attention
GROUP BY
    as_of_date,
    drop_point_id,
    drop_point_name;


-- ============================================================
-- 13. DAILY OPERATIONAL SUMMARY
-- ============================================================

CREATE VIEW analytics.vw_daily_operational_summary AS
WITH sales AS (
    SELECT
        s.*,
        s.performance_status AS sales_status
    FROM analytics.vw_drop_point_current_performance s
),
outlet AS (
    SELECT
        o.*,
        ROUND(
            100.0 * o.critical_outlet
            / NULLIF(o.total_monitored_outlet, 0),
            2
        ) AS critical_outlet_pct,
        ROUND(
            100.0 * (o.critical_outlet + o.watch_outlet)
            / NULLIF(o.total_monitored_outlet, 0),
            2
        ) AS attention_outlet_pct
    FROM analytics.vw_drop_point_outlet_attention_summary o
),
combined AS (
    SELECT
        s.as_of_date,
        s.month_start,
        s.drop_point_id,
        s.drop_point_name,
        s.region,
        s.area,
        s.net_sales,
        s.sales_target,
        s.sales_achievement_pct,
        s.expected_achievement_pct,
        ROUND(s.sales_achievement_pct - s.expected_achievement_pct, 2)
            AS sales_pace_gap_pp,
        s.sales_status,
        s.active_outlet,
        s.active_outlet_target,
        s.active_outlet_achievement_pct,
        COALESCE(o.normal_outlet, 0) AS normal_outlet,
        COALESCE(o.watch_outlet, 0) AS watch_outlet,
        COALESCE(o.critical_outlet, 0) AS critical_outlet,
        COALESCE(o.total_monitored_outlet, 0) AS total_monitored_outlet,
        COALESCE(o.inactive_14d_outlet, 0) AS inactive_14d_outlet,
        COALESCE(o.critical_outlet_pct, 0) AS critical_outlet_pct,
        COALESCE(o.attention_outlet_pct, 0) AS attention_outlet_pct,
        CASE
            WHEN COALESCE(o.critical_outlet_pct, 0) > 20 THEN 'CRITICAL'
            WHEN COALESCE(o.attention_outlet_pct, 0) >= 10 THEN 'WATCH'
            ELSE 'NORMAL'
        END AS outlet_status,
        COALESCE(d.total_shipment, 0) AS total_shipment,
        COALESCE(d.completed_delivery, 0) AS completed_delivery,
        COALESCE(d.in_transit_delivery, 0) AS in_transit_delivery,
        COALESCE(d.successful_delivery, 0) AS successful_delivery,
        COALESCE(d.on_time_delivery, 0) AS on_time_delivery,
        COALESCE(d.late_delivery, 0) AS late_delivery,
        COALESCE(d.failed_delivery, 0) AS failed_delivery,
        COALESCE(d.overdue_delivery, 0) AS overdue_delivery,
        d.on_time_rate_pct,
        d.delivery_success_rate_pct,
        d.sla_target_pct AS delivery_sla_target_pct,
        ROUND(d.on_time_rate_pct - d.sla_target_pct, 2)
            AS delivery_sla_gap_pp,
        d.avg_delay_hours,
        COALESCE(d.sla_performance_status, 'NORMAL') AS delivery_status,
        d.delivery_data_status
    FROM sales s
    LEFT JOIN analytics.vw_drop_point_current_delivery_status d
        ON s.drop_point_id = d.drop_point_id
    LEFT JOIN outlet o
        ON s.drop_point_id = o.drop_point_id
       AND s.as_of_date = o.as_of_date
),
final AS (
    SELECT
        *,
        CASE
            WHEN sales_status = 'CRITICAL'
              OR outlet_status = 'CRITICAL'
              OR delivery_status = 'CRITICAL'
                THEN 'CRITICAL'
            WHEN sales_status = 'WATCH'
              OR outlet_status = 'WATCH'
              OR delivery_status = 'WATCH'
                THEN 'WATCH'
            ELSE 'NORMAL'
        END AS overall_status
    FROM combined
)
SELECT
    as_of_date,
    month_start,
    drop_point_id,
    drop_point_name,
    region,
    area,
    net_sales,
    sales_target,
    sales_achievement_pct,
    expected_achievement_pct,
    sales_pace_gap_pp,
    sales_pace_gap_pp AS sales_gap_pct,
    sales_status,
    active_outlet,
    active_outlet_target,
    active_outlet_achievement_pct,
    normal_outlet,
    watch_outlet,
    critical_outlet,
    total_monitored_outlet,
    inactive_14d_outlet,
    critical_outlet_pct,
    attention_outlet_pct,
    outlet_status,
    total_shipment,
    completed_delivery,
    in_transit_delivery,
    successful_delivery,
    on_time_delivery,
    late_delivery,
    failed_delivery,
    overdue_delivery,
    on_time_rate_pct,
    delivery_success_rate_pct,
    delivery_sla_target_pct,
    delivery_sla_gap_pp,
    delivery_sla_gap_pp AS delivery_sla_gap_pct,
    avg_delay_hours,
    delivery_status,
    delivery_data_status,
    overall_status
FROM final;


-- ============================================================
-- 14. DAILY REPORT
-- ============================================================

CREATE VIEW analytics.vw_daily_report AS
WITH params AS (
    SELECT current_business_date AS business_date
    FROM app.simulation_state
    WHERE simulation_name = 'operations_demo'
),
sales AS (
    SELECT
        f.drop_point_id,
        SUM(f.net_sales) AS daily_net_sales,
        COUNT(*) AS daily_invoice,
        COUNT(DISTINCT f.outlet_id) AS daily_active_outlet
    FROM core.fact_sales f
    CROSS JOIN params p
    WHERE f.sales_date = p.business_date
    GROUP BY f.drop_point_id
),
delivery AS (
    SELECT
        d.drop_point_id,
        COUNT(*) AS daily_shipment,
        COUNT(*) FILTER (WHERE d.delivery_class = 'ON_TIME') AS daily_on_time,
        COUNT(*) FILTER (WHERE d.delivery_class = 'LATE') AS daily_late,
        COUNT(*) FILTER (WHERE d.delivery_class = 'FAILED') AS daily_failed,
        COUNT(*) FILTER (WHERE d.delivery_class = 'IN_TRANSIT') AS daily_in_transit,
        COUNT(*) FILTER (
            WHERE d.delivery_class = 'IN_TRANSIT'
              AND d.is_overdue = TRUE
        ) AS daily_overdue,
        COUNT(*) FILTER (WHERE d.is_completed = TRUE) AS daily_completed,
        COUNT(*) FILTER (WHERE d.is_delivered = TRUE) AS daily_successful_delivery,
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE d.delivery_class = 'ON_TIME')
            / NULLIF(COUNT(*) FILTER (WHERE d.is_completed = TRUE), 0),
            2
        ) AS daily_on_time_rate_pct,
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE d.is_delivered = TRUE)
            / NULLIF(COUNT(*) FILTER (WHERE d.is_completed = TRUE), 0),
            2
        ) AS daily_delivery_success_rate_pct
    FROM analytics.vw_delivery_detail d
    CROSS JOIN params p
    WHERE COALESCE(d.shipment_ts::date, d.order_date) = p.business_date
    GROUP BY d.drop_point_id
),
period AS (
    SELECT total_working_days
    FROM analytics.vw_current_period
)
SELECT
    p.business_date,
    s.drop_point_id,
    s.drop_point_name,
    COALESCE(ds.daily_net_sales, 0::numeric) AS daily_net_sales,
    COALESCE(ds.daily_invoice, 0::bigint) AS daily_invoice,
    COALESCE(ds.daily_active_outlet, 0::bigint) AS daily_active_outlet,
    ROUND(s.sales_target / NULLIF(period.total_working_days, 0), 2)
        AS daily_sales_target,
    ROUND(
        100.0 * COALESCE(ds.daily_net_sales, 0::numeric)
        / NULLIF(
            s.sales_target / NULLIF(period.total_working_days, 0),
            0
        ),
        2
    ) AS daily_sales_achievement_pct,
    COALESCE(dd.daily_shipment, 0::bigint) AS daily_shipment,
    COALESCE(dd.daily_completed, 0::bigint) AS daily_completed,
    COALESCE(dd.daily_in_transit, 0::bigint) AS daily_in_transit,
    COALESCE(dd.daily_on_time, 0::bigint) AS daily_on_time,
    COALESCE(dd.daily_late, 0::bigint) AS daily_late,
    COALESCE(dd.daily_failed, 0::bigint) AS daily_failed,
    COALESCE(dd.daily_overdue, 0::bigint) AS daily_overdue,
    dd.daily_on_time_rate_pct,
    COALESCE(dd.daily_successful_delivery, 0::bigint)
        AS daily_successful_delivery,
    dd.daily_delivery_success_rate_pct,
    s.net_sales AS mtd_net_sales,
    s.sales_target AS monthly_sales_target,
    s.sales_achievement_pct AS mtd_sales_achievement_pct,
    s.expected_achievement_pct,
    s.sales_pace_gap_pp,
    s.on_time_rate_pct AS mtd_on_time_rate_pct,
    s.completed_delivery AS mtd_completed_delivery,
    s.in_transit_delivery AS mtd_in_transit_delivery,
    s.late_delivery AS mtd_late_delivery,
    s.failed_delivery AS mtd_failed_delivery,
    s.overdue_delivery AS mtd_overdue_delivery,
    s.delivery_sla_target_pct,
    s.delivery_status,
    s.normal_outlet,
    s.watch_outlet,
    s.critical_outlet,
    s.overall_status
FROM analytics.vw_daily_operational_summary s
CROSS JOIN params p
CROSS JOIN period
LEFT JOIN sales ds
    ON s.drop_point_id = ds.drop_point_id
LEFT JOIN delivery dd
    ON s.drop_point_id = dd.drop_point_id;


-- ============================================================
-- 15. FINAL DOMAIN GUARDS
-- ============================================================

DO $$
BEGIN
    IF to_regclass('core.dim_product') IS NOT NULL
       OR to_regclass('core.fact_inventory') IS NOT NULL
       OR to_regclass('raw.dim_product') IS NOT NULL
       OR to_regclass('raw.fact_inventory') IS NOT NULL
    THEN
        RAISE EXCEPTION 'Product/inventory objects still exist after cleanup.';
    END IF;
END $$;

COMMIT;
