-- =========================================================
-- Drop Point Operations Intelligence
-- 011_create_delivery_analytics.sql
-- DELIVERY ANALYTICS MART
-- =========================================================


-- =========================================================
-- 1. ENRICHED DELIVERY DETAIL
-- Grain:
-- 1 row = 1 shipment
-- =========================================================

CREATE OR REPLACE VIEW analytics.vw_delivery_detail AS

SELECT
    d.shipment_id,
    d.invoice_id,

    d.order_date,
    d.planned_delivery_date,
    d.actual_delivery_date,

    d.drop_point_id,
    dp.drop_point_name,
    dp.region,
    dp.area,

    d.salesperson_id,
    s.salesperson_name,

    d.outlet_id,
    o.bp_code,
    o.outlet_name,

    d.delivery_status,

    d.sla_hours,
    d.actual_delivery_hours,
    d.on_time_flag,
    d.attempt_count,
    d.failure_reason,

    -- =============================================
    -- DELIVERY CLASSIFICATION
    -- =============================================

    CASE
        WHEN UPPER(d.delivery_status) = 'FAILED'
            THEN 'FAILED'

        WHEN d.actual_delivery_date IS NOT NULL
             AND (
                 d.on_time_flag = FALSE
                 OR d.actual_delivery_hours > d.sla_hours
             )
            THEN 'LATE'

        WHEN d.actual_delivery_date IS NOT NULL
             AND d.on_time_flag = TRUE
            THEN 'ON_TIME'

        WHEN d.actual_delivery_date IS NULL
             AND CURRENT_DATE > d.planned_delivery_date
            THEN 'OVERDUE'

        ELSE 'OPEN'
    END AS delivery_class,


    -- =============================================
    -- LATE FLAG
    -- Shipment sudah selesai tetapi melewati SLA
    -- =============================================

    CASE
        WHEN d.actual_delivery_date IS NOT NULL
             AND (
                 d.on_time_flag = FALSE
                 OR d.actual_delivery_hours > d.sla_hours
             )
        THEN TRUE
        ELSE FALSE
    END AS is_late,


    -- =============================================
    -- OVERDUE FLAG
    -- Shipment belum selesai dan sudah lewat jadwal
    -- =============================================

    CASE
        WHEN d.actual_delivery_date IS NULL
             AND CURRENT_DATE > d.planned_delivery_date
        THEN TRUE
        ELSE FALSE
    END AS is_overdue,


    -- =============================================
    -- DELAY HOURS
    -- 0 = tidak terlambat
    -- =============================================

    CASE
        WHEN d.actual_delivery_hours IS NULL
            THEN NULL

        WHEN d.actual_delivery_hours > d.sla_hours
            THEN d.actual_delivery_hours - d.sla_hours

        ELSE 0
    END AS delay_hours,


    -- =============================================
    -- DELAY BUCKET
    -- =============================================

    CASE
        WHEN d.actual_delivery_hours IS NULL
            THEN NULL

        WHEN d.actual_delivery_hours <= d.sla_hours
            THEN 'ON TIME'

        WHEN d.actual_delivery_hours - d.sla_hours <= 12
            THEN '<= 12 HOURS'

        WHEN d.actual_delivery_hours - d.sla_hours <= 24
            THEN '12-24 HOURS'

        WHEN d.actual_delivery_hours - d.sla_hours <= 48
            THEN '24-48 HOURS'

        ELSE '> 48 HOURS'
    END AS delay_bucket

FROM core.fact_delivery d

JOIN core.dim_drop_point dp
    ON d.drop_point_id = dp.drop_point_id

JOIN core.dim_salesperson s
    ON d.salesperson_id = s.salesperson_id

JOIN core.dim_outlet o
    ON d.outlet_id = o.outlet_id;

-- =========================================================
-- 2. DROP POINT DELIVERY SUMMARY
-- Grain:
-- 1 row = 1 Drop Point
-- =========================================================

CREATE OR REPLACE VIEW analytics.vw_drop_point_delivery_summary AS

SELECT
    drop_point_id,
    drop_point_name,
    region,
    area,

    COUNT(*) AS total_shipment,

    COUNT(*) FILTER (
        WHERE delivery_class = 'ON_TIME'
    ) AS on_time_delivery,

    COUNT(*) FILTER (
        WHERE delivery_class = 'LATE'
    ) AS late_delivery,

    COUNT(*) FILTER (
        WHERE delivery_class = 'FAILED'
    ) AS failed_delivery,

    COUNT(*) FILTER (
        WHERE delivery_class = 'OVERDUE'
    ) AS overdue_delivery,

    COUNT(*) FILTER (
        WHERE delivery_class = 'OPEN'
    ) AS open_delivery,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE delivery_class = 'ON_TIME'
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE delivery_class IN ('ON_TIME', 'LATE')
            ),
            0
        ),
        2
    ) AS on_time_rate_pct,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE delivery_class = 'LATE'
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE delivery_class IN ('ON_TIME', 'LATE')
            ),
            0
        ),
        2
    ) AS late_rate_pct,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE delivery_class = 'FAILED'
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS failure_rate_pct,

    ROUND(
        AVG(delay_hours)
        FILTER (
            WHERE delivery_class = 'LATE'
        ),
        2
    ) AS avg_delay_hours,

    MAX(delay_hours) AS max_delay_hours

FROM analytics.vw_delivery_detail

GROUP BY
    drop_point_id,
    drop_point_name,
    region,
    area;