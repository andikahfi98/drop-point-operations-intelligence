CREATE OR REPLACE VIEW analytics.vw_delivery_daily_trend AS

WITH daily AS (
    SELECT
        COALESCE(
            shipment_ts::date,
            order_date
        ) AS order_date,

        drop_point_id,
        drop_point_name,

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
            WHERE is_completed = TRUE
        ) AS completed_delivery,

        COUNT(*) FILTER (
            WHERE delivery_class = 'IN_TRANSIT'
        ) AS in_transit_delivery,

        COUNT(*) FILTER (
            WHERE is_delivered = TRUE
        ) AS successful_delivery,

        ROUND(
            AVG(late_hours)
            FILTER (
                WHERE delivery_class = 'LATE'
            ),
            2
        ) AS avg_delay_hours,

        ROUND(
            AVG(actual_delivery_hours)
            FILTER (
                WHERE is_delivered = TRUE
            ),
            2
        ) AS avg_delivery_hours

    FROM analytics.vw_delivery_detail

    GROUP BY
        COALESCE(
            shipment_ts::date,
            order_date
        ),
        drop_point_id,
        drop_point_name
)

SELECT
    -- Existing columns preserved
    order_date,
    drop_point_id,
    drop_point_name,
    total_shipment,
    on_time_delivery,
    late_delivery,
    failed_delivery,
    overdue_delivery,

    ROUND(
        100.0
        * on_time_delivery
        / NULLIF(completed_delivery, 0),
        2
    ) AS on_time_rate_pct,

    avg_delay_hours,

    -- New clearer metrics
    completed_delivery,
    in_transit_delivery,
    successful_delivery,

    ROUND(
        100.0
        * successful_delivery
        / NULLIF(completed_delivery, 0),
        2
    ) AS delivery_success_rate_pct,

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

    avg_delivery_hours

FROM daily;