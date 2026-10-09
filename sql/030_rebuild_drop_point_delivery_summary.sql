CREATE OR REPLACE VIEW analytics.vw_drop_point_delivery_summary AS

WITH delivery_summary AS (
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
            WHERE delivery_class = 'IN_TRANSIT'
              AND is_overdue = TRUE
        ) AS overdue_delivery,

        COUNT(*) FILTER (
            WHERE delivery_class = 'IN_TRANSIT'
        ) AS open_delivery,

        COUNT(*) FILTER (
            WHERE is_completed = TRUE
        ) AS completed_delivery,

        COUNT(*) FILTER (
            WHERE is_delivered = TRUE
        ) AS successful_delivery,

        COUNT(*) FILTER (
            WHERE delivery_class = 'IN_TRANSIT'
        ) AS in_transit_delivery,

        ROUND(
            AVG(actual_delivery_hours)
            FILTER (
                WHERE is_delivered = TRUE
            ),
            2
        ) AS avg_delivery_hours,

        ROUND(
            AVG(late_hours)
            FILTER (
                WHERE delivery_class = 'LATE'
            ),
            2
        ) AS avg_delay_hours,

        MAX(late_hours)
        FILTER (
            WHERE delivery_class = 'LATE'
        ) AS max_delay_hours

    FROM analytics.vw_delivery_detail

    GROUP BY
        drop_point_id,
        drop_point_name,
        region,
        area
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

    FROM delivery_summary
)

SELECT
    drop_point_id,
    drop_point_name,
    region,
    area,

    -- Existing columns, preserved for compatibility
    total_shipment,
    on_time_delivery,
    late_delivery,
    failed_delivery,
    overdue_delivery,
    open_delivery,
    on_time_rate_pct,
    late_rate_pct,
    failure_rate_pct,
    avg_delay_hours,
    max_delay_hours,

    -- New clearer metrics
    completed_delivery,
    successful_delivery,
    in_transit_delivery,
    delivery_success_rate_pct,
    avg_delivery_hours

FROM rates;