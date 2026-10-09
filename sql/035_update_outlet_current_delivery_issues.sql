CREATE OR REPLACE VIEW analytics.vw_outlet_current_delivery_issues AS

WITH params AS (
    SELECT
        as_of_date,
        month_start
    FROM analytics.vw_current_period
)

SELECT
    d.outlet_id,

    -- Existing metric
    COUNT(*) AS total_delivery,

    COUNT(*) FILTER (
        WHERE d.delivery_class = 'LATE'
    ) AS late_delivery,

    COUNT(*) FILTER (
        WHERE d.delivery_class = 'FAILED'
    ) AS failed_delivery,

    COUNT(*) FILTER (
        WHERE d.delivery_class = 'IN_TRANSIT'
          AND d.is_overdue = TRUE
    ) AS overdue_delivery,

    -- New clearer metrics
    COUNT(*) FILTER (
        WHERE d.delivery_class = 'IN_TRANSIT'
    ) AS in_transit_delivery,

    COUNT(*) FILTER (
        WHERE d.is_completed = TRUE
    ) AS completed_delivery,

    COUNT(*) FILTER (
        WHERE
            d.delivery_class IN ('LATE', 'FAILED')
            OR (
                d.delivery_class = 'IN_TRANSIT'
                AND d.is_overdue = TRUE
            )
    ) AS total_issue

FROM analytics.vw_delivery_detail d

CROSS JOIN params p

WHERE
    COALESCE(
        d.shipment_ts::date,
        d.order_date
    )
    BETWEEN p.month_start AND p.as_of_date

GROUP BY
    d.outlet_id;