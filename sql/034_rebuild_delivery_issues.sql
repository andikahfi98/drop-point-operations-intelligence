CREATE OR REPLACE VIEW analytics.vw_delivery_issues AS

SELECT
    -- =====================================================
    -- Existing columns
    -- =====================================================

    d.shipment_id,
    d.invoice_id,
    d.order_date,
    d.planned_delivery_date,
    d.actual_delivery_date,

    d.drop_point_id,
    d.drop_point_name,
    d.region,
    d.area,

    d.salesperson_id,
    d.salesperson_name,

    d.outlet_id,
    d.bp_code,
    d.outlet_name,

    d.delivery_status,
    d.sla_hours,
    d.actual_delivery_hours,
    d.on_time_flag,
    d.attempt_count,
    d.failure_reason,

    d.delivery_class,
    d.is_late,
    d.is_overdue,
    d.delay_hours,
    d.delay_bucket,

    -- =====================================================
    -- New lifecycle fields
    -- =====================================================

    d.shipment_ts,
    d.target_delivery_ts,
    d.actual_delivery_ts,

    d.is_completed,
    d.is_delivered,
    d.is_failed,

    d.late_hours,
    d.overdue_hours,

    -- =====================================================
    -- ISSUE TYPE
    -- =====================================================

    CASE
        WHEN d.delivery_class = 'FAILED'
            THEN 'FAILED'

        WHEN d.delivery_class = 'LATE'
            THEN 'LATE'

        WHEN d.delivery_class = 'IN_TRANSIT'
             AND d.is_overdue = TRUE
            THEN 'OVERDUE'

        ELSE NULL
    END AS issue_type,

    -- =====================================================
    -- ISSUE DURATION
    -- =====================================================

    CASE
        WHEN d.delivery_class = 'LATE'
            THEN d.late_hours

        WHEN d.delivery_class = 'IN_TRANSIT'
             AND d.is_overdue = TRUE
            THEN d.overdue_hours

        ELSE NULL
    END AS issue_hours

FROM analytics.vw_delivery_detail d

WHERE
       d.delivery_class IN ('LATE', 'FAILED')

    OR (
        d.delivery_class = 'IN_TRANSIT'
        AND d.is_overdue = TRUE
    );