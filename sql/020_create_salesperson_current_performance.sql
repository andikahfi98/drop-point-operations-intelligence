-- =========================================================
-- 020_create_salesperson_current_performance.sql
-- CURRENT PIC / SALESPERSON PERFORMANCE
-- =========================================================

CREATE OR REPLACE VIEW
analytics.vw_salesperson_current_performance AS

WITH period AS (

    SELECT
        as_of_date,
        month_start,
        expected_achievement_pct

    FROM analytics.vw_current_period
),

delivery AS (

    SELECT
        d.drop_point_id,
        d.salesperson_id,

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
            WHERE d.delivery_class = 'OVERDUE'
        ) AS overdue_delivery,

        ROUND(
            100.0
            * COUNT(*) FILTER (
                WHERE d.delivery_class = 'ON_TIME'
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE d.delivery_class IN (
                        'ON_TIME',
                        'LATE'
                    )
                ),
                0
            ),
            2
        ) AS on_time_rate_pct,

        ROUND(
            AVG(d.delay_hours)
            FILTER (
                WHERE d.delivery_class = 'LATE'
            ),
            2
        ) AS avg_delay_hours

    FROM analytics.vw_delivery_detail d

    CROSS JOIN period p

    WHERE
        d.order_date >= p.month_start
        AND d.order_date <= p.as_of_date

    GROUP BY
        d.drop_point_id,
        d.salesperson_id
)

SELECT
    p.as_of_date,
    s.month_start,

    s.drop_point_id,
    s.drop_point_name,

    s.salesperson_id,
    s.salesperson_name,

    s.net_sales,
    s.sales_target,
    s.sales_achievement_pct,

    p.expected_achievement_pct,

    ROUND(
        s.sales_achievement_pct
        - p.expected_achievement_pct,
        2
    ) AS sales_pace_gap_pp,

    s.active_outlet,
    s.active_outlet_target,
    s.active_outlet_achievement_pct,

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

    d.on_time_rate_pct,

    s.delivery_sla_target_pct,

    ROUND(
        d.on_time_rate_pct
        - s.delivery_sla_target_pct,
        2
    ) AS delivery_sla_gap_pp,

    d.avg_delay_hours,

    CASE

        WHEN
            s.sales_achievement_pct
            - p.expected_achievement_pct <= -20
        THEN 'CRITICAL'

        WHEN
            d.on_time_rate_pct
            - s.delivery_sla_target_pct <= -10
        THEN 'CRITICAL'

        WHEN
            s.sales_achievement_pct
            - p.expected_achievement_pct <= -10
        THEN 'WARNING'

        WHEN
            d.on_time_rate_pct
            - s.delivery_sla_target_pct < 0
        THEN 'WARNING'

        ELSE 'NORMAL'

    END AS pic_status

FROM analytics.vw_salesperson_monthly_performance s

CROSS JOIN period p

LEFT JOIN delivery d
    ON s.drop_point_id = d.drop_point_id
    AND s.salesperson_id = d.salesperson_id

WHERE
    s.month_start = p.month_start;