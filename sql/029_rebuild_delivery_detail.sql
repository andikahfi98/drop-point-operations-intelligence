CREATE OR REPLACE VIEW analytics.vw_delivery_detail AS

WITH reference_time AS (
    SELECT
        COALESCE(
            (
                SELECT
                    current_business_date
                    + current_business_time
                FROM app.simulation_state
                WHERE simulation_name = 'operations_demo'
                LIMIT 1
            ),
            CURRENT_TIMESTAMP::timestamp
        ) AS reference_ts
),

delivery_base AS (
    SELECT
        d.*,

        CASE
            WHEN d.actual_delivery_ts IS NOT NULL
                 AND d.shipment_ts IS NOT NULL
            THEN ROUND(
                EXTRACT(
                    EPOCH FROM (
                        d.actual_delivery_ts
                        - d.shipment_ts
                    )
                ) / 3600.0
            )::integer

            ELSE NULL
        END AS calc_delivery_hours,

        CASE
            WHEN d.actual_delivery_ts IS NOT NULL
                 AND d.target_delivery_ts IS NOT NULL
            THEN GREATEST(
                0,
                ROUND(
                    EXTRACT(
                        EPOCH FROM (
                            d.actual_delivery_ts
                            - d.target_delivery_ts
                        )
                    ) / 3600.0
                )::integer
            )

            ELSE NULL
        END AS calc_late_hours

    FROM core.fact_delivery d
)

SELECT

    -- =====================================================
    -- Existing columns
    -- Keep these for compatibility with downstream views.
    -- =====================================================

    d.shipment_id,
    d.invoice_id,
    d.order_date,

    d.target_delivery_ts::date
        AS planned_delivery_date,

    d.actual_delivery_ts::date
        AS actual_delivery_date,

    d.drop_point_id,
    dp.drop_point_name,
    dp.region,
    dp.area,

    d.salesperson_id,
    sp.salesperson_name,

    d.outlet_id,
    o.bp_code,
    o.outlet_name,

    d.delivery_status,

    d.sla_hours,

    d.calc_delivery_hours
        AS actual_delivery_hours,

    CASE
        WHEN d.delivery_status = 'FAILED'
            THEN FALSE

        WHEN d.actual_delivery_ts IS NULL
             OR d.target_delivery_ts IS NULL
            THEN NULL

        WHEN d.actual_delivery_ts
             <= d.target_delivery_ts
            THEN TRUE

        ELSE FALSE
    END AS on_time_flag,

    d.attempt_count,
    d.failure_reason,


    -- =====================================================
    -- Normalized delivery classification
    -- =====================================================

    CASE
        WHEN d.delivery_status = 'FAILED'
            THEN 'FAILED'

        WHEN d.delivery_status = 'IN_TRANSIT'
            THEN 'IN_TRANSIT'

        WHEN d.actual_delivery_ts IS NOT NULL
             AND d.target_delivery_ts IS NOT NULL
             AND d.actual_delivery_ts
                 > d.target_delivery_ts
            THEN 'LATE'

        WHEN d.actual_delivery_ts IS NOT NULL
             AND d.target_delivery_ts IS NOT NULL
             AND d.actual_delivery_ts
                 <= d.target_delivery_ts
            THEN 'ON_TIME'

        ELSE 'UNKNOWN'
    END AS delivery_class,


    -- =====================================================
    -- Flags
    -- =====================================================

    CASE
        WHEN d.actual_delivery_ts IS NOT NULL
             AND d.target_delivery_ts IS NOT NULL
             AND d.actual_delivery_ts
                 > d.target_delivery_ts
            THEN TRUE

        ELSE FALSE
    END AS is_late,


    CASE
        WHEN d.delivery_status = 'IN_TRANSIT'
             AND d.target_delivery_ts IS NOT NULL
             AND rt.reference_ts
                 > d.target_delivery_ts
            THEN TRUE

        ELSE FALSE
    END AS is_overdue,


    -- =====================================================
    -- Delay
    -- Only meaningful when shipment actually arrived.
    -- =====================================================

    d.calc_late_hours
        AS delay_hours,


    CASE
        WHEN d.actual_delivery_ts IS NULL
             OR d.target_delivery_ts IS NULL
            THEN NULL

        WHEN d.actual_delivery_ts
             <= d.target_delivery_ts
            THEN 'ON TIME'

        WHEN d.calc_late_hours <= 12
            THEN '1-12 HOURS'

        WHEN d.calc_late_hours <= 24
            THEN '12-24 HOURS'

        WHEN d.calc_late_hours <= 48
            THEN '24-48 HOURS'

        ELSE '>48 HOURS'
    END AS delay_bucket,


    -- =====================================================
    -- New timestamp fields
    -- Source of truth for delivery lifecycle.
    -- =====================================================

    d.shipment_ts,
    d.target_delivery_ts,
    d.actual_delivery_ts,


    -- =====================================================
    -- New operational flags
    -- =====================================================

    CASE
        WHEN d.delivery_status IN (
            'DELIVERED',
            'DELIVERED LATE',
            'FAILED'
        )
        THEN TRUE

        ELSE FALSE
    END AS is_completed,


    CASE
        WHEN d.actual_delivery_ts IS NOT NULL
        THEN TRUE

        ELSE FALSE
    END AS is_delivered,


    CASE
        WHEN d.delivery_status = 'FAILED'
        THEN TRUE

        ELSE FALSE
    END AS is_failed,


    -- Hours late after target.
    d.calc_late_hours
        AS late_hours,


    -- Shipment still in transit but already past target.
    CASE
        WHEN d.delivery_status = 'IN_TRANSIT'
             AND d.target_delivery_ts IS NOT NULL
             AND rt.reference_ts
                 > d.target_delivery_ts
        THEN ROUND(
            EXTRACT(
                EPOCH FROM (
                    rt.reference_ts
                    - d.target_delivery_ts
                )
            ) / 3600.0
        )::integer

        ELSE 0
    END AS overdue_hours,


    -- Useful for simulator/debugging.
    rt.reference_ts

FROM delivery_base d

JOIN core.dim_drop_point dp
    ON d.drop_point_id = dp.drop_point_id

JOIN core.dim_salesperson sp
    ON d.salesperson_id = sp.salesperson_id

JOIN core.dim_outlet o
    ON d.outlet_id = o.outlet_id

CROSS JOIN reference_time rt;