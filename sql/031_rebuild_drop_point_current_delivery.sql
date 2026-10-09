CREATE OR REPLACE VIEW analytics.vw_drop_point_current_delivery AS

WITH period AS (
    SELECT
        as_of_date,
        month_start
    FROM analytics.vw_current_period
),

-- =========================================================
-- SLA TARGET CURRENT MONTH
-- Target exists even when there is no delivery yet.
-- =========================================================
target_by_dp AS (
    SELECT
        p.as_of_date,
        p.month_start,
        t.drop_point_id,

        ROUND(
            CASE
                -- Protect against source stored as 0.95
                WHEN MAX(t.delivery_sla_target_pct) <= 1
                    THEN MAX(t.delivery_sla_target_pct) * 100
                ELSE MAX(t.delivery_sla_target_pct)
            END,
            2
        ) AS sla_target_pct

    FROM core.fact_target t

    CROSS JOIN period p

    WHERE t.month_start = p.month_start

    GROUP BY
        p.as_of_date,
        p.month_start,
        t.drop_point_id
),

-- =========================================================
-- CURRENT MONTH DELIVERY ACTUAL
-- =========================================================
delivery_agg AS (
    SELECT
        d.drop_point_id,

        COUNT(*) AS total_shipment,

        COUNT(*) FILTER (
            WHERE d.delivery_class = 'ON_TIME'
        ) AS on_time_delivery,

        COUNT(*) FILTER (
            WHERE d.delivery_class = 'LATE'
        ) AS late_delivery,

        COUNT(*) FILTER (
            WHERE d.delivery_class = 'FAILED'
        ) AS failed_delivery,

        COUNT(*) FILTER (
            WHERE d.delivery_class = 'IN_TRANSIT'
        ) AS in_transit_delivery,

        COUNT(*) FILTER (
            WHERE d.delivery_class = 'IN_TRANSIT'
              AND d.is_overdue = TRUE
        ) AS overdue_delivery,

        COUNT(*) FILTER (
            WHERE d.is_completed = TRUE
        ) AS completed_delivery,

        COUNT(*) FILTER (
            WHERE d.is_delivered = TRUE
        ) AS successful_delivery,

        ROUND(
            AVG(d.actual_delivery_hours)
            FILTER (
                WHERE d.is_delivered = TRUE
            ),
            2
        ) AS avg_delivery_hours,

        ROUND(
            AVG(d.late_hours)
            FILTER (
                WHERE d.delivery_class = 'LATE'
            ),
            2
        ) AS avg_delay_hours

    FROM analytics.vw_delivery_detail d

    CROSS JOIN period p

    WHERE COALESCE(
        d.shipment_ts::date,
        d.order_date
    )
    BETWEEN p.month_start AND p.as_of_date

    GROUP BY d.drop_point_id
),

base AS (
    SELECT
        t.as_of_date,
        t.month_start,

        t.drop_point_id,
        dp.drop_point_name,

        COALESCE(d.total_shipment, 0)
            AS total_shipment,

        COALESCE(d.on_time_delivery, 0)
            AS on_time_delivery,

        COALESCE(d.late_delivery, 0)
            AS late_delivery,

        COALESCE(d.failed_delivery, 0)
            AS failed_delivery,

        COALESCE(d.overdue_delivery, 0)
            AS overdue_delivery,

        -- old column name kept for compatibility
        COALESCE(d.in_transit_delivery, 0)
            AS open_delivery,

        COALESCE(d.completed_delivery, 0)
            AS completed_delivery,

        COALESCE(d.successful_delivery, 0)
            AS successful_delivery,

        COALESCE(d.in_transit_delivery, 0)
            AS in_transit_delivery,

        d.avg_delivery_hours,
        d.avg_delay_hours,

        t.sla_target_pct

    FROM target_by_dp t

    JOIN core.dim_drop_point dp
        ON t.drop_point_id = dp.drop_point_id

    LEFT JOIN delivery_agg d
        ON t.drop_point_id = d.drop_point_id
),

rates AS (
    SELECT
        *,

        ROUND(
            100.0
            * on_time_delivery
            / NULLIF(completed_delivery, 0),
            2
        ) AS on_time_rate_pct,

        ROUND(
            100.0
            * late_delivery
            / NULLIF(completed_delivery, 0),
            2
        ) AS late_rate_pct,

        ROUND(
            100.0
            * failed_delivery
            / NULLIF(completed_delivery, 0),
            2
        ) AS failure_rate_pct,

        ROUND(
            100.0
            * successful_delivery
            / NULLIF(completed_delivery, 0),
            2
        ) AS delivery_success_rate_pct

    FROM base
)

SELECT
    -- Existing columns first for compatibility
    as_of_date,
    month_start,
    drop_point_id,
    drop_point_name,

    total_shipment,
    on_time_delivery,
    late_delivery,
    failed_delivery,
    overdue_delivery,
    open_delivery,

    on_time_rate_pct,
    late_rate_pct,
    avg_delay_hours,

    -- New clearer metrics
    completed_delivery,
    successful_delivery,
    in_transit_delivery,

    failure_rate_pct,
    delivery_success_rate_pct,
    avg_delivery_hours,

    sla_target_pct,

    ROUND(
        on_time_rate_pct - sla_target_pct,
        2
    ) AS sla_gap_pct

FROM rates;