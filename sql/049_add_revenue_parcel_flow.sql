-- ============================================================
-- 049 - Revenue + Parcel Flow rebaseline
--
-- Purpose
-- - Rename Sales -> Revenue (shipping fee income).
-- - Replace Delivery fact with Shipment fact.
-- - Add parcel lifecycle inside the Drop Point:
--     RECEIVED -> SORTING -> READY -> OUT_FOR_DELIVERY -> DELIVERED/FAILED
-- - Add parcel on-hand / aging / backlog analytics.
-- - Keep delivery SLA at Drop Point level.
-- - Keep PIC responsible only for revenue + outlet coverage.
--
-- Assumption
-- - Migration 047 has already been applied successfully.
-- - Existing synthetic delivery rows are preserved and mapped into the
--   new shipment lifecycle. Existing historical rows are treated as
--   already dispatched because the old model started at IN_TRANSIT.
-- ============================================================

BEGIN;

-- ============================================================
-- 0. PRE-FLIGHT
-- ============================================================

DO $$
BEGIN
    IF to_regclass('core.fact_sales') IS NULL THEN
        RAISE EXCEPTION 'core.fact_sales not found. Apply migration 047 first.';
    END IF;

    IF to_regclass('core.fact_delivery') IS NULL THEN
        RAISE EXCEPTION 'core.fact_delivery not found. Apply migration 047 first.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM core.fact_delivery
        GROUP BY invoice_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            'Cannot create fact_shipment: multiple delivery rows exist for one invoice.';
    END IF;
END $$;


-- ============================================================
-- 1. REBUILD ANALYTICS FROM THE NEW DOMAIN MODEL
-- ============================================================

DROP SCHEMA IF EXISTS analytics CASCADE;
CREATE SCHEMA analytics;


-- ============================================================
-- 2. SALES -> REVENUE
-- One row = one shipping transaction / invoice.
-- Revenue means shipping fee income, not product sales.
-- ============================================================

ALTER TABLE core.fact_sales
    RENAME TO fact_revenue;

ALTER TABLE core.fact_revenue
    RENAME COLUMN sales_date TO revenue_date;

ALTER TABLE core.fact_revenue
    RENAME COLUMN net_sales TO revenue;

ALTER INDEX IF EXISTS core.idx_fact_sales_sales_date
    RENAME TO idx_fact_revenue_date;

ALTER INDEX IF EXISTS core.idx_fact_sales_transaction_ts
    RENAME TO idx_fact_revenue_transaction_ts;

ALTER INDEX IF EXISTS core.idx_fact_sales_drop_point
    RENAME TO idx_fact_revenue_drop_point;

ALTER INDEX IF EXISTS core.idx_fact_sales_pic
    RENAME TO idx_fact_revenue_pic;

ALTER INDEX IF EXISTS core.idx_fact_sales_outlet
    RENAME TO idx_fact_revenue_outlet;


ALTER TABLE raw.fact_sales
    RENAME TO fact_revenue;

ALTER TABLE raw.fact_revenue
    RENAME COLUMN date TO revenue_date;

ALTER TABLE raw.fact_revenue
    RENAME COLUMN net_sales TO revenue;


ALTER TABLE core.fact_pic_target
    RENAME COLUMN sales_target TO revenue_target;

ALTER TABLE core.fact_pic_target
    RENAME CONSTRAINT chk_pic_target_sales TO chk_pic_target_revenue;

ALTER TABLE raw.fact_pic_target
    RENAME COLUMN sales_target TO revenue_target;


-- ============================================================
-- 3. DELIVERY -> SHIPMENT / PARCEL LIFECYCLE
-- ============================================================

CREATE TABLE core.fact_shipment_v2 (
    shipment_id          VARCHAR(40) PRIMARY KEY,
    invoice_id           VARCHAR(30) NOT NULL UNIQUE,
    drop_point_id        VARCHAR(20) NOT NULL,
    outlet_id            VARCHAR(20) NOT NULL,

    created_ts           TIMESTAMP NOT NULL,
    received_ts          TIMESTAMP,
    sorted_ts            TIMESTAMP,
    dispatched_ts        TIMESTAMP,
    target_delivery_ts   TIMESTAMP,
    actual_delivery_ts   TIMESTAMP,

    shipment_status      VARCHAR(30) NOT NULL,
    sla_hours            INTEGER NOT NULL,
    attempt_count        INTEGER NOT NULL DEFAULT 1,
    issue_reason         VARCHAR(40),
    loaded_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_shipment_revenue
        FOREIGN KEY (invoice_id)
        REFERENCES core.fact_revenue(invoice_id),

    CONSTRAINT fk_shipment_drop_point
        FOREIGN KEY (drop_point_id)
        REFERENCES core.dim_drop_point(drop_point_id),

    CONSTRAINT fk_shipment_outlet
        FOREIGN KEY (outlet_id)
        REFERENCES core.dim_outlet(outlet_id),

    CONSTRAINT chk_shipment_status
        CHECK (
            shipment_status IN (
                'RECEIVED',
                'SORTING',
                'READY',
                'OUT_FOR_DELIVERY',
                'DELIVERED',
                'FAILED'
            )
        ),

    CONSTRAINT chk_shipment_sla
        CHECK (sla_hours > 0),

    CONSTRAINT chk_shipment_attempt
        CHECK (attempt_count >= 1),

    CONSTRAINT chk_shipment_issue_reason
        CHECK (
            issue_reason IS NULL
            OR issue_reason IN (
                'ADDRESS_ISSUE',
                'RECEIVER_UNAVAILABLE',
                'OPERATIONAL_DELAY',
                'CAPACITY_ISSUE',
                'LINEHAUL_DELAY',
                'VEHICLE_ISSUE',
                'OUTLET_CLOSED',
                'OTHER'
            )
        ),

    CONSTRAINT chk_shipment_received_order
        CHECK (received_ts IS NULL OR received_ts >= created_ts),

    CONSTRAINT chk_shipment_sorted_order
        CHECK (
            sorted_ts IS NULL
            OR received_ts IS NULL
            OR sorted_ts >= received_ts
        ),

    CONSTRAINT chk_shipment_dispatched_order
        CHECK (
            dispatched_ts IS NULL
            OR received_ts IS NULL
            OR dispatched_ts >= received_ts
        ),

    CONSTRAINT chk_shipment_target_order
        CHECK (
            target_delivery_ts IS NULL
            OR dispatched_ts IS NULL
            OR target_delivery_ts >= dispatched_ts
        ),

    CONSTRAINT chk_shipment_actual_order
        CHECK (
            actual_delivery_ts IS NULL
            OR dispatched_ts IS NULL
            OR actual_delivery_ts >= dispatched_ts
        )
);

INSERT INTO core.fact_shipment_v2 (
    shipment_id,
    invoice_id,
    drop_point_id,
    outlet_id,
    created_ts,
    received_ts,
    sorted_ts,
    dispatched_ts,
    target_delivery_ts,
    actual_delivery_ts,
    shipment_status,
    sla_hours,
    attempt_count,
    issue_reason,
    loaded_at
)
SELECT
    d.shipment_id,
    d.invoice_id,
    d.drop_point_id,
    d.outlet_id,
    COALESCE(
        d.shipment_ts,
        d.order_date::timestamp + INTERVAL '09 hours'
    ) - INTERVAL '75 minutes' AS created_ts,
    COALESCE(
        d.shipment_ts,
        d.order_date::timestamp + INTERVAL '09 hours'
    ) - INTERVAL '60 minutes' AS received_ts,
    COALESCE(
        d.shipment_ts,
        d.order_date::timestamp + INTERVAL '09 hours'
    ) - INTERVAL '30 minutes' AS sorted_ts,
    COALESCE(
        d.shipment_ts,
        d.order_date::timestamp + INTERVAL '09 hours'
    ) AS dispatched_ts,
    d.target_delivery_ts,
    d.actual_delivery_ts,
    CASE
        WHEN d.delivery_status = 'FAILED' THEN 'FAILED'
        WHEN d.actual_delivery_ts IS NOT NULL THEN 'DELIVERED'
        ELSE 'OUT_FOR_DELIVERY'
    END AS shipment_status,
    COALESCE(d.sla_hours, 24) AS sla_hours,
    GREATEST(COALESCE(d.attempt_count, 1), 1) AS attempt_count,
    CASE
        WHEN d.failure_reason IS NULL THEN NULL
        WHEN LOWER(d.failure_reason) LIKE '%address%' THEN 'ADDRESS_ISSUE'
        WHEN LOWER(d.failure_reason) LIKE '%customer%'
          OR LOWER(d.failure_reason) LIKE '%receiver%' THEN 'RECEIVER_UNAVAILABLE'
        WHEN LOWER(d.failure_reason) LIKE '%vehicle%' THEN 'VEHICLE_ISSUE'
        WHEN LOWER(d.failure_reason) LIKE '%outlet%closed%' THEN 'OUTLET_CLOSED'
        WHEN LOWER(d.failure_reason) LIKE '%operational%' THEN 'OPERATIONAL_DELAY'
        ELSE 'OTHER'
    END AS issue_reason,
    d.loaded_at
FROM core.fact_delivery d;

DROP TABLE core.fact_delivery;
ALTER TABLE core.fact_shipment_v2
    RENAME TO fact_shipment;

CREATE INDEX idx_fact_shipment_drop_point
    ON core.fact_shipment(drop_point_id);

CREATE INDEX idx_fact_shipment_outlet
    ON core.fact_shipment(outlet_id);

CREATE INDEX idx_fact_shipment_received_ts
    ON core.fact_shipment(received_ts);

CREATE INDEX idx_fact_shipment_dispatched_ts
    ON core.fact_shipment(dispatched_ts);

CREATE INDEX idx_fact_shipment_target_delivery_ts
    ON core.fact_shipment(target_delivery_ts);

CREATE INDEX idx_fact_shipment_status
    ON core.fact_shipment(shipment_status);


-- RAW shipment mirrors the clean logistics domain.
DROP TABLE raw.fact_delivery;

CREATE TABLE raw.fact_shipment (
    raw_row_id          BIGSERIAL PRIMARY KEY,
    shipment_id         TEXT,
    invoice_id          TEXT,
    drop_point_id       TEXT,
    outlet_id           TEXT,
    created_ts          TEXT,
    received_ts         TEXT,
    sorted_ts           TEXT,
    dispatched_ts       TEXT,
    target_delivery_ts  TEXT,
    actual_delivery_ts  TEXT,
    shipment_status     TEXT,
    sla_hours           TEXT,
    attempt_count       TEXT,
    issue_reason        TEXT,
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO raw.fact_shipment (
    shipment_id,
    invoice_id,
    drop_point_id,
    outlet_id,
    created_ts,
    received_ts,
    sorted_ts,
    dispatched_ts,
    target_delivery_ts,
    actual_delivery_ts,
    shipment_status,
    sla_hours,
    attempt_count,
    issue_reason
)
SELECT
    shipment_id,
    invoice_id,
    drop_point_id,
    outlet_id,
    created_ts::text,
    received_ts::text,
    sorted_ts::text,
    dispatched_ts::text,
    target_delivery_ts::text,
    actual_delivery_ts::text,
    shipment_status,
    sla_hours::text,
    attempt_count::text,
    issue_reason
FROM core.fact_shipment;


-- ============================================================
-- 4. SIMULATION LOG TERMINOLOGY
-- ============================================================

ALTER TABLE app.simulation_run_log
    RENAME COLUMN sales_rows TO revenue_rows;

ALTER TABLE app.simulation_run_log
    RENAME COLUMN delivery_rows TO shipment_rows;

ALTER TABLE app.simulation_run_log
    ADD COLUMN IF NOT EXISTS received_rows INTEGER NOT NULL DEFAULT 0;

ALTER TABLE app.simulation_run_log
    ADD COLUMN IF NOT EXISTS dispatched_rows INTEGER NOT NULL DEFAULT 0;

ALTER TABLE app.simulation_run_log
    ADD COLUMN IF NOT EXISTS completed_rows INTEGER NOT NULL DEFAULT 0;


-- ============================================================
-- 5. DATA FRESHNESS
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
            SELECT MAX(r.revenue_date)
            FROM core.fact_revenue r
            CROSS JOIN simulation s
            WHERE r.transaction_ts <= s.simulation_ts
        ) AS latest_revenue_date,
        (
            SELECT MAX(r.transaction_ts)
            FROM core.fact_revenue r
            CROSS JOIN simulation s
            WHERE r.transaction_ts <= s.simulation_ts
        ) AS latest_revenue_ts,
        (
            SELECT MAX(sh.received_ts)
            FROM core.fact_shipment sh
            CROSS JOIN simulation s
            WHERE sh.received_ts <= s.simulation_ts
        ) AS latest_received_ts,
        (
            SELECT MAX(sh.dispatched_ts)
            FROM core.fact_shipment sh
            CROSS JOIN simulation s
            WHERE sh.dispatched_ts <= s.simulation_ts
        ) AS latest_dispatched_ts,
        (
            SELECT MAX(sh.actual_delivery_ts)
            FROM core.fact_shipment sh
            CROSS JOIN simulation s
            WHERE sh.actual_delivery_ts <= s.simulation_ts
        ) AS latest_actual_delivery_ts
)
SELECT
    f.latest_revenue_date,
    f.latest_revenue_ts,
    f.latest_received_ts,
    f.latest_dispatched_ts,
    f.latest_actual_delivery_ts,
    s.simulation_ts,
    CASE
        WHEN f.latest_revenue_ts IS NULL THEN NULL
        ELSE ROUND(
            EXTRACT(EPOCH FROM (s.simulation_ts - f.latest_revenue_ts)) / 60.0,
            2
        )
    END AS revenue_freshness_minutes,
    CASE
        WHEN f.latest_received_ts IS NULL THEN NULL
        ELSE ROUND(
            EXTRACT(EPOCH FROM (s.simulation_ts - f.latest_received_ts)) / 60.0,
            2
        )
    END AS parcel_freshness_minutes
FROM freshness f
CROSS JOIN simulation s;


-- ============================================================
-- 6. CURRENT PERIOD
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
-- 7. REVENUE / PIC ANALYTICS
-- ============================================================

CREATE VIEW analytics.vw_pic_monthly_performance AS
WITH revenue AS (
    SELECT
        DATE_TRUNC('month', revenue_date)::date AS month_start,
        drop_point_id,
        pic_id,
        COUNT(*) AS total_transaction,
        COUNT(DISTINCT outlet_id) AS active_outlet,
        SUM(revenue) AS revenue
    FROM core.fact_revenue
    GROUP BY 1, 2, 3
)
SELECT
    t.month_start,
    t.drop_point_id,
    dp.drop_point_name,
    t.pic_id,
    p.pic_name,
    COALESCE(r.total_transaction, 0) AS total_transaction,
    COALESCE(r.active_outlet, 0) AS active_outlet,
    COALESCE(r.revenue, 0) AS revenue,
    t.revenue_target,
    t.active_outlet_target,
    COALESCE(r.revenue, 0) - t.revenue_target AS revenue_variance,
    ROUND(
        100.0 * COALESCE(r.revenue, 0) / NULLIF(t.revenue_target, 0),
        2
    ) AS revenue_achievement_pct,
    COALESCE(r.active_outlet, 0) - t.active_outlet_target
        AS active_outlet_variance,
    ROUND(
        100.0 * COALESCE(r.active_outlet, 0)
        / NULLIF(t.active_outlet_target, 0),
        2
    ) AS active_outlet_achievement_pct
FROM core.fact_pic_target t
JOIN core.dim_drop_point dp
    ON t.drop_point_id = dp.drop_point_id
JOIN core.dim_pic p
    ON t.pic_id = p.pic_id
LEFT JOIN revenue r
    ON t.month_start = r.month_start
   AND t.drop_point_id = r.drop_point_id
   AND t.pic_id = r.pic_id;


CREATE VIEW analytics.vw_drop_point_revenue_monthly AS
WITH revenue AS (
    SELECT
        DATE_TRUNC('month', revenue_date)::date AS month_start,
        drop_point_id,
        COUNT(*) AS total_transaction,
        COUNT(DISTINCT outlet_id) AS active_outlet,
        SUM(revenue) AS revenue
    FROM core.fact_revenue
    GROUP BY 1, 2
),
target AS (
    SELECT
        month_start,
        drop_point_id,
        SUM(revenue_target) AS revenue_target,
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
    COALESCE(r.total_transaction, 0) AS total_transaction,
    COALESCE(r.active_outlet, 0) AS active_outlet,
    COALESCE(r.revenue, 0) AS revenue,
    t.revenue_target,
    t.active_outlet_target,
    COALESCE(r.revenue, 0) - t.revenue_target AS revenue_variance,
    ROUND(
        100.0 * COALESCE(r.revenue, 0) / NULLIF(t.revenue_target, 0),
        2
    ) AS revenue_achievement_pct,
    COALESCE(r.active_outlet, 0) - t.active_outlet_target
        AS active_outlet_variance,
    ROUND(
        100.0 * COALESCE(r.active_outlet, 0)
        / NULLIF(t.active_outlet_target, 0),
        2
    ) AS active_outlet_achievement_pct
FROM target t
JOIN core.dim_drop_point dp
    ON t.drop_point_id = dp.drop_point_id
LEFT JOIN revenue r
    ON t.month_start = r.month_start
   AND t.drop_point_id = r.drop_point_id;


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
    r.drop_point_id,
    r.drop_point_name,
    r.region,
    r.area,
    r.revenue,
    r.revenue_target,
    r.revenue_achievement_pct,
    ROUND(r.revenue_achievement_pct - p.expected_achievement_pct, 2)
        AS revenue_gap_pct,
    r.active_outlet,
    r.active_outlet_target,
    r.active_outlet_achievement_pct,
    CASE
        WHEN r.revenue_achievement_pct - p.expected_achievement_pct <= -20
            THEN 'CRITICAL'
        WHEN r.revenue_achievement_pct - p.expected_achievement_pct <= -10
            THEN 'WATCH'
        ELSE 'NORMAL'
    END AS revenue_status
FROM analytics.vw_drop_point_revenue_monthly r
CROSS JOIN period p
WHERE r.month_start = p.month_start;


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
        r.month_start,
        r.drop_point_id,
        r.drop_point_name,
        r.pic_id,
        r.pic_name,
        r.revenue,
        r.revenue_target,
        r.revenue_achievement_pct,
        p.expected_achievement_pct,
        ROUND(r.revenue_achievement_pct - p.expected_achievement_pct, 2)
            AS revenue_gap_pct,
        r.active_outlet,
        r.active_outlet_target,
        r.active_outlet_achievement_pct
    FROM analytics.vw_pic_monthly_performance r
    CROSS JOIN period p
    WHERE r.month_start = p.month_start
)
SELECT
    *,
    CASE
        WHEN revenue_target IS NULL OR revenue_target <= 0
            THEN 'NO_DATA'
        ELSE 'SUFFICIENT_DATA'
    END AS pic_data_status,
    CASE
        WHEN revenue_target IS NULL OR revenue_target <= 0
            THEN 'NORMAL'
        WHEN revenue_gap_pct <= -20
            THEN 'CRITICAL'
        WHEN revenue_gap_pct < 0
            THEN 'WATCH'
        ELSE 'NORMAL'
    END AS pic_status
FROM base;


-- ============================================================
-- 8. SHIPMENT DETAIL / PARCEL LIFECYCLE
-- ============================================================

CREATE VIEW analytics.vw_shipment_detail AS
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
        sh.*,
        rt.reference_ts,
        (
            sh.received_ts IS NOT NULL
            AND sh.received_ts <= rt.reference_ts
            AND sh.dispatched_ts IS NULL
            AND sh.shipment_status IN ('RECEIVED', 'SORTING', 'READY')
        ) AS is_on_hand
    FROM core.fact_shipment sh
    CROSS JOIN reference_time rt
)
SELECT
    b.shipment_id,
    b.invoice_id,
    b.drop_point_id,
    dp.drop_point_name,
    dp.region,
    dp.area,
    b.outlet_id,
    o.bp_code,
    o.outlet_name,
    o.pic_id,
    p.pic_name,
    b.created_ts,
    b.received_ts,
    b.sorted_ts,
    b.dispatched_ts,
    b.target_delivery_ts,
    b.actual_delivery_ts,
    b.shipment_status,
    b.sla_hours,
    b.attempt_count,
    b.issue_reason,
    b.is_on_hand,
    CASE
        WHEN b.is_on_hand
        THEN ROUND(
            EXTRACT(EPOCH FROM (b.reference_ts - b.received_ts)) / 3600.0,
            2
        )
        ELSE NULL
    END AS parcel_age_hours,
    CASE
        WHEN b.received_ts IS NOT NULL
         AND b.dispatched_ts IS NOT NULL
        THEN ROUND(
            EXTRACT(EPOCH FROM (b.dispatched_ts - b.received_ts)) / 3600.0,
            2
        )
        ELSE NULL
    END AS dwell_hours,
    CASE
        WHEN b.shipment_status = 'FAILED' THEN 'FAILED'
        WHEN b.actual_delivery_ts IS NOT NULL
         AND b.target_delivery_ts IS NOT NULL
         AND b.actual_delivery_ts <= b.target_delivery_ts THEN 'ON_TIME'
        WHEN b.actual_delivery_ts IS NOT NULL
         AND b.target_delivery_ts IS NOT NULL
         AND b.actual_delivery_ts > b.target_delivery_ts THEN 'LATE'
        WHEN b.dispatched_ts IS NOT NULL
         AND b.actual_delivery_ts IS NULL
         AND b.shipment_status = 'OUT_FOR_DELIVERY' THEN 'IN_TRANSIT'
        ELSE 'NOT_DISPATCHED'
    END AS delivery_class,
    CASE
        WHEN b.shipment_status = 'OUT_FOR_DELIVERY'
         AND b.target_delivery_ts IS NOT NULL
         AND b.reference_ts > b.target_delivery_ts
        THEN TRUE
        ELSE FALSE
    END AS is_overdue,
    CASE
        WHEN b.actual_delivery_ts IS NOT NULL
         AND b.dispatched_ts IS NOT NULL
        THEN ROUND(
            EXTRACT(EPOCH FROM (b.actual_delivery_ts - b.dispatched_ts)) / 3600.0,
            2
        )
        ELSE NULL
    END AS delivery_hours,
    CASE
        WHEN b.actual_delivery_ts IS NOT NULL
         AND b.target_delivery_ts IS NOT NULL
         AND b.actual_delivery_ts > b.target_delivery_ts
        THEN ROUND(
            EXTRACT(EPOCH FROM (b.actual_delivery_ts - b.target_delivery_ts)) / 3600.0,
            2
        )
        ELSE NULL
    END AS late_hours,
    CASE
        WHEN b.shipment_status = 'OUT_FOR_DELIVERY'
         AND b.target_delivery_ts IS NOT NULL
         AND b.reference_ts > b.target_delivery_ts
        THEN ROUND(
            EXTRACT(EPOCH FROM (b.reference_ts - b.target_delivery_ts)) / 3600.0,
            2
        )
        ELSE NULL
    END AS overdue_hours,
    b.reference_ts
FROM base b
JOIN core.dim_drop_point dp
    ON b.drop_point_id = dp.drop_point_id
JOIN core.dim_outlet o
    ON b.outlet_id = o.outlet_id
JOIN core.dim_pic p
    ON o.pic_id = p.pic_id;


-- ============================================================
-- 9. PARCEL FLOW / PAKET TERTAHAN
-- ============================================================

CREATE VIEW analytics.vw_drop_point_parcel_current AS
WITH period AS (
    SELECT as_of_date, month_start
    FROM analytics.vw_current_period
),
stats AS (
    SELECT
        dp.drop_point_id,
        dp.drop_point_name,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.received_ts::date BETWEEN p.month_start AND p.as_of_date
        ) AS parcel_in_mtd,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.dispatched_ts::date BETWEEN p.month_start AND p.as_of_date
        ) AS parcel_out_mtd,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.received_ts::date = p.as_of_date
        ) AS parcel_in_today,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.dispatched_ts::date = p.as_of_date
        ) AS parcel_out_today,
        COUNT(sh.shipment_id) FILTER (WHERE sh.is_on_hand) AS parcel_on_hand,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.is_on_hand
              AND sh.parcel_age_hours < 6
        ) AS parcel_under_6h,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.is_on_hand
              AND sh.parcel_age_hours >= 6
              AND sh.parcel_age_hours < 12
        ) AS parcel_6_12h,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.is_on_hand
              AND sh.parcel_age_hours >= 12
              AND sh.parcel_age_hours < 24
        ) AS parcel_12_24h,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.is_on_hand
              AND sh.parcel_age_hours >= 24
        ) AS parcel_over_24h,
        MAX(sh.parcel_age_hours) FILTER (WHERE sh.is_on_hand)
            AS oldest_parcel_hours,
        ROUND(
            AVG(sh.dwell_hours) FILTER (
                WHERE sh.dispatched_ts::date BETWEEN p.month_start AND p.as_of_date
            ),
            2
        ) AS avg_dwell_hours
    FROM core.dim_drop_point dp
    CROSS JOIN period p
    LEFT JOIN analytics.vw_shipment_detail sh
        ON dp.drop_point_id = sh.drop_point_id
    GROUP BY
        dp.drop_point_id,
        dp.drop_point_name
),
metrics AS (
    SELECT
        *,
        ROUND(
            100.0 * parcel_out_mtd / NULLIF(parcel_in_mtd, 0),
            2
        ) AS dispatch_rate_pct,
        ROUND(
            100.0 * parcel_over_24h / NULLIF(parcel_on_hand, 0),
            2
        ) AS parcel_over_24h_pct
    FROM stats
)
SELECT
    *,
    CASE
        WHEN parcel_over_24h >= 10
          OR COALESCE(oldest_parcel_hours, 0) >= 48
            THEN 'CRITICAL'
        WHEN parcel_over_24h >= 3
          OR COALESCE(oldest_parcel_hours, 0) >= 24
            THEN 'WATCH'
        ELSE 'NORMAL'
    END AS parcel_status
FROM metrics;


-- ============================================================
-- 10. DELIVERY / SLA AFTER DISPATCH
-- ============================================================

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
        sh.drop_point_id,
        COUNT(*) AS total_shipment,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'ON_TIME') AS on_time_delivery,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'LATE') AS late_delivery,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'FAILED') AS failed_delivery,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'IN_TRANSIT') AS in_transit_delivery,
        COUNT(*) FILTER (
            WHERE sh.delivery_class = 'IN_TRANSIT'
              AND sh.is_overdue = TRUE
        ) AS overdue_delivery,
        COUNT(*) FILTER (
            WHERE sh.delivery_class IN ('ON_TIME', 'LATE', 'FAILED')
        ) AS completed_delivery,
        COUNT(*) FILTER (
            WHERE sh.delivery_class IN ('ON_TIME', 'LATE')
        ) AS successful_delivery,
        ROUND(
            AVG(sh.delivery_hours) FILTER (
                WHERE sh.delivery_class IN ('ON_TIME', 'LATE')
            ),
            2
        ) AS avg_delivery_hours,
        ROUND(
            AVG(sh.late_hours) FILTER (WHERE sh.delivery_class = 'LATE'),
            2
        ) AS avg_delay_hours
    FROM analytics.vw_shipment_detail sh
    CROSS JOIN period p
    WHERE sh.dispatched_ts::date BETWEEN p.month_start AND p.as_of_date
    GROUP BY sh.drop_point_id
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
    END AS delivery_status,
    CASE
        WHEN d.completed_delivery = 0 THEN 'NO_DATA'
        WHEN d.completed_delivery < 20 THEN 'INSUFFICIENT_DATA'
        ELSE 'SUFFICIENT_DATA'
    END AS delivery_data_status
FROM analytics.vw_drop_point_current_delivery d;


CREATE VIEW analytics.vw_shipment_issues AS
SELECT
    sh.shipment_id,
    sh.invoice_id,
    sh.drop_point_id,
    sh.drop_point_name,
    sh.outlet_id,
    sh.bp_code,
    sh.outlet_name,
    sh.pic_id,
    sh.pic_name,
    sh.shipment_status,
    sh.delivery_class,
    CASE
        WHEN sh.is_on_hand AND sh.parcel_age_hours >= 24 THEN 'PARCEL_STUCK'
        WHEN sh.delivery_class = 'FAILED' THEN 'FAILED'
        WHEN sh.delivery_class = 'LATE' THEN 'LATE'
        WHEN sh.delivery_class = 'IN_TRANSIT' AND sh.is_overdue THEN 'OVERDUE'
        ELSE NULL
    END AS issue_type,
    sh.issue_reason,
    CASE
        WHEN sh.is_on_hand AND sh.parcel_age_hours >= 24 THEN sh.parcel_age_hours
        WHEN sh.delivery_class = 'LATE' THEN sh.late_hours
        WHEN sh.delivery_class = 'IN_TRANSIT' AND sh.is_overdue THEN sh.overdue_hours
        ELSE NULL
    END AS issue_hours,
    sh.received_ts,
    sh.dispatched_ts,
    sh.target_delivery_ts,
    sh.actual_delivery_ts
FROM analytics.vw_shipment_detail sh
WHERE (sh.is_on_hand AND sh.parcel_age_hours >= 24)
   OR sh.delivery_class IN ('LATE', 'FAILED')
   OR (sh.delivery_class = 'IN_TRANSIT' AND sh.is_overdue);


CREATE VIEW analytics.vw_drop_point_issue_summary AS
SELECT
    drop_point_id,
    drop_point_name,
    issue_type,
    COALESCE(issue_reason, 'OTHER') AS issue_reason,
    COUNT(*) AS issue_count
FROM analytics.vw_shipment_issues
GROUP BY
    drop_point_id,
    drop_point_name,
    issue_type,
    COALESCE(issue_reason, 'OTHER');


-- ============================================================
-- 11. OUTLET ANALYTICS
-- ============================================================

CREATE VIEW analytics.vw_outlet_activity AS
WITH params AS (
    SELECT as_of_date, month_start
    FROM analytics.vw_current_period
),
revenue_activity AS (
    SELECT
        r.outlet_id,
        MAX(r.revenue_date) AS last_transaction_date,
        COUNT(*) FILTER (
            WHERE r.revenue_date >= (SELECT month_start FROM params)
        ) AS current_month_transaction,
        SUM(r.revenue) FILTER (
            WHERE r.revenue_date >= (SELECT month_start FROM params)
        ) AS current_month_revenue
    FROM core.fact_revenue r
    GROUP BY r.outlet_id
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
    r.last_transaction_date,
    CASE
        WHEN r.last_transaction_date IS NULL THEN NULL
        ELSE p.as_of_date - r.last_transaction_date
    END AS days_since_last_transaction,
    COALESCE(r.current_month_transaction, 0) AS current_month_transaction,
    COALESCE(r.current_month_revenue, 0) AS current_month_revenue,
    CASE
        WHEN o.active_flag = FALSE THEN 'INACTIVE_MASTER'
        WHEN r.last_transaction_date IS NULL THEN 'NO_REVENUE_HISTORY'
        WHEN p.as_of_date - r.last_transaction_date >= 14 THEN 'INACTIVE_14D'
        WHEN p.as_of_date - r.last_transaction_date >= 7 THEN 'WATCH_7D'
        ELSE 'ACTIVE'
    END AS activity_status
FROM core.dim_outlet o
JOIN core.dim_drop_point dp
    ON o.drop_point_id = dp.drop_point_id
JOIN core.dim_pic pic
    ON o.pic_id = pic.pic_id
LEFT JOIN revenue_activity r
    ON o.outlet_id = r.outlet_id
CROSS JOIN params p;


CREATE VIEW analytics.vw_outlet_current_delivery_issues AS
WITH params AS (
    SELECT as_of_date, month_start
    FROM analytics.vw_current_period
)
SELECT
    sh.outlet_id,
    COUNT(*) AS total_delivery,
    COUNT(*) FILTER (WHERE sh.delivery_class = 'LATE') AS late_delivery,
    COUNT(*) FILTER (WHERE sh.delivery_class = 'FAILED') AS failed_delivery,
    COUNT(*) FILTER (
        WHERE sh.delivery_class = 'IN_TRANSIT'
          AND sh.is_overdue = TRUE
    ) AS overdue_delivery,
    COUNT(*) FILTER (WHERE sh.delivery_class = 'IN_TRANSIT')
        AS in_transit_delivery,
    COUNT(*) FILTER (
        WHERE sh.delivery_class IN ('ON_TIME', 'LATE', 'FAILED')
    ) AS completed_delivery,
    COUNT(*) FILTER (
        WHERE sh.delivery_class IN ('LATE', 'FAILED')
           OR (sh.delivery_class = 'IN_TRANSIT' AND sh.is_overdue = TRUE)
    ) AS total_issue
FROM analytics.vw_shipment_detail sh
CROSS JOIN params p
WHERE sh.dispatched_ts::date BETWEEN p.month_start AND p.as_of_date
GROUP BY sh.outlet_id;


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
        a.current_month_revenue,
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
    current_month_revenue,
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
        WHEN activity_status IN ('NO_REVENUE_HISTORY', 'INACTIVE_14D')
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
-- 12. DAILY OPERATIONAL SUMMARY
-- ============================================================

CREATE VIEW analytics.vw_daily_operational_summary AS
WITH revenue AS (
    SELECT *
    FROM analytics.vw_drop_point_current_performance
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
        r.as_of_date,
        r.month_start,
        r.drop_point_id,
        r.drop_point_name,
        r.region,
        r.area,
        r.revenue,
        r.revenue_target,
        r.revenue_achievement_pct,
        r.expected_achievement_pct,
        r.revenue_gap_pct,
        r.revenue_status,
        r.active_outlet,
        r.active_outlet_target,
        r.active_outlet_achievement_pct,
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
        COALESCE(p.parcel_in_mtd, 0) AS parcel_in_mtd,
        COALESCE(p.parcel_out_mtd, 0) AS parcel_out_mtd,
        COALESCE(p.parcel_on_hand, 0) AS parcel_on_hand,
        COALESCE(p.parcel_under_6h, 0) AS parcel_under_6h,
        COALESCE(p.parcel_6_12h, 0) AS parcel_6_12h,
        COALESCE(p.parcel_12_24h, 0) AS parcel_12_24h,
        COALESCE(p.parcel_over_24h, 0) AS parcel_over_24h,
        p.oldest_parcel_hours,
        p.avg_dwell_hours,
        p.dispatch_rate_pct,
        COALESCE(p.parcel_status, 'NORMAL') AS parcel_status,
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
        d.sla_gap_pct AS delivery_sla_gap_pct,
        d.avg_delay_hours,
        COALESCE(d.delivery_status, 'NORMAL') AS delivery_status,
        d.delivery_data_status
    FROM revenue r
    LEFT JOIN outlet o
        ON r.drop_point_id = o.drop_point_id
       AND r.as_of_date = o.as_of_date
    LEFT JOIN analytics.vw_drop_point_parcel_current p
        ON r.drop_point_id = p.drop_point_id
    LEFT JOIN analytics.vw_drop_point_current_delivery_status d
        ON r.drop_point_id = d.drop_point_id
),
final AS (
    SELECT
        *,
        CASE
            WHEN revenue_status = 'CRITICAL'
              OR outlet_status = 'CRITICAL'
              OR parcel_status = 'CRITICAL'
              OR delivery_status = 'CRITICAL'
                THEN 'CRITICAL'
            WHEN revenue_status = 'WATCH'
              OR outlet_status = 'WATCH'
              OR parcel_status = 'WATCH'
              OR delivery_status = 'WATCH'
                THEN 'WATCH'
            ELSE 'NORMAL'
        END AS overall_status
    FROM combined
)
SELECT * FROM final;


-- ============================================================
-- 13. DAILY REPORT
-- ============================================================

CREATE VIEW analytics.vw_daily_report AS
WITH params AS (
    SELECT current_business_date AS business_date
    FROM app.simulation_state
    WHERE simulation_name = 'operations_demo'
),
revenue AS (
    SELECT
        r.drop_point_id,
        SUM(r.revenue) AS daily_revenue,
        COUNT(*) AS daily_invoice,
        COUNT(DISTINCT r.outlet_id) AS daily_active_outlet
    FROM core.fact_revenue r
    CROSS JOIN params p
    WHERE r.revenue_date = p.business_date
    GROUP BY r.drop_point_id
),
delivery AS (
    SELECT
        sh.drop_point_id,
        COUNT(*) AS daily_shipment,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'ON_TIME') AS daily_on_time,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'LATE') AS daily_late,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'FAILED') AS daily_failed,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'IN_TRANSIT') AS daily_in_transit,
        COUNT(*) FILTER (
            WHERE sh.delivery_class = 'IN_TRANSIT' AND sh.is_overdue
        ) AS daily_overdue,
        COUNT(*) FILTER (
            WHERE sh.delivery_class IN ('ON_TIME', 'LATE', 'FAILED')
        ) AS daily_completed,
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE sh.delivery_class = 'ON_TIME')
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE sh.delivery_class IN ('ON_TIME', 'LATE', 'FAILED')
                ),
                0
            ),
            2
        ) AS daily_on_time_rate_pct
    FROM analytics.vw_shipment_detail sh
    CROSS JOIN params p
    WHERE sh.dispatched_ts::date = p.business_date
    GROUP BY sh.drop_point_id
),
period AS (
    SELECT total_working_days
    FROM analytics.vw_current_period
)
SELECT
    p.business_date,
    s.drop_point_id,
    s.drop_point_name,
    COALESCE(r.daily_revenue, 0::numeric) AS daily_revenue,
    COALESCE(r.daily_invoice, 0::bigint) AS daily_invoice,
    COALESCE(r.daily_active_outlet, 0::bigint) AS daily_active_outlet,
    ROUND(s.revenue_target / NULLIF(period.total_working_days, 0), 2)
        AS daily_revenue_target,
    ROUND(
        100.0 * COALESCE(r.daily_revenue, 0::numeric)
        / NULLIF(
            s.revenue_target / NULLIF(period.total_working_days, 0),
            0
        ),
        2
    ) AS daily_revenue_achievement_pct,
    pc.parcel_in_today AS daily_parcel_in,
    pc.parcel_out_today AS daily_parcel_out,
    pc.parcel_on_hand,
    pc.parcel_over_24h,
    pc.oldest_parcel_hours,
    pc.avg_dwell_hours,
    pc.dispatch_rate_pct,
    pc.parcel_status,
    COALESCE(d.daily_shipment, 0::bigint) AS daily_shipment,
    COALESCE(d.daily_completed, 0::bigint) AS daily_completed,
    COALESCE(d.daily_in_transit, 0::bigint) AS daily_in_transit,
    COALESCE(d.daily_on_time, 0::bigint) AS daily_on_time,
    COALESCE(d.daily_late, 0::bigint) AS daily_late,
    COALESCE(d.daily_failed, 0::bigint) AS daily_failed,
    COALESCE(d.daily_overdue, 0::bigint) AS daily_overdue,
    d.daily_on_time_rate_pct,
    s.revenue AS mtd_revenue,
    s.revenue_target AS monthly_revenue_target,
    s.revenue_achievement_pct AS mtd_revenue_achievement_pct,
    s.expected_achievement_pct,
    s.revenue_gap_pct,
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
LEFT JOIN revenue r
    ON s.drop_point_id = r.drop_point_id
LEFT JOIN delivery d
    ON s.drop_point_id = d.drop_point_id
LEFT JOIN analytics.vw_drop_point_parcel_current pc
    ON s.drop_point_id = pc.drop_point_id;


-- ============================================================
-- 14. FINAL DOMAIN GUARDS
-- ============================================================

DO $$
BEGIN
    IF to_regclass('core.fact_sales') IS NOT NULL
       OR to_regclass('core.fact_delivery') IS NOT NULL
       OR to_regclass('raw.fact_sales') IS NOT NULL
       OR to_regclass('raw.fact_delivery') IS NOT NULL
    THEN
        RAISE EXCEPTION 'Legacy sales/delivery tables still exist after migration 049.';
    END IF;

    IF to_regclass('core.fact_revenue') IS NULL
       OR to_regclass('core.fact_shipment') IS NULL
    THEN
        RAISE EXCEPTION 'New revenue/shipment facts were not created.';
    END IF;
END $$;

COMMIT;
