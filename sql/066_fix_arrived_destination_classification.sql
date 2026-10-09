-- 066: Correct shipment delivery_class when a parcel is at Destination DP.
-- Non-destructive: replace analytics view only, no shipment data changes.
-- Existing dependent views keep their column schemas.
-- A parcel at Destination DP is classified AT_DESTINATION_DP,
-- not IN_TRANSIT. is_overdue still represents SLA breach independently.
BEGIN;

CREATE OR REPLACE VIEW analytics.vw_shipment_detail AS
WITH reference_time AS (
    SELECT COALESCE(
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
            AND sh.left_dp_ts IS NULL
            AND sh.shipment_status IN ('RECEIVED', 'SORTING', 'READY')
        ) AS at_origin_dp,
        (
            sh.destination_dp_id <> sh.origin_dp_id
            AND sh.arrived_destination_ts IS NOT NULL
            AND sh.arrived_destination_ts <= rt.reference_ts
            AND sh.out_for_delivery_ts IS NULL
            AND sh.shipment_status = 'ARRIVED_DESTINATION'
        ) AS at_destination_dp
    FROM core.fact_shipment sh
    CROSS JOIN reference_time rt
)
SELECT
    b.shipment_id,
    b.invoice_id,
    b.origin_dp_id,
    odp.drop_point_name AS origin_dp_name,
    b.destination_dp_id,
    ddp.drop_point_name AS destination_dp_name,
    CASE
        WHEN b.at_origin_dp THEN b.origin_dp_id
        WHEN b.at_destination_dp THEN b.destination_dp_id
        ELSE NULL
    END AS current_dp_id,
    CASE
        WHEN b.at_origin_dp THEN odp.drop_point_name
        WHEN b.at_destination_dp THEN ddp.drop_point_name
        ELSE NULL
    END AS current_dp_name,
    b.seller_id,
    s.seller_code,
    s.seller_name,
    s.seller_pic_id,
    sp.staff_name AS seller_pic_name,
    b.receiver_name,
    b.receiver_area,
    b.courier_id,
    c.courier_name,
    b.weight_kg,
    b.created_ts,
    b.received_ts,
    b.sorted_ts,
    b.left_dp_ts,
    b.arrived_destination_ts,
    b.out_for_delivery_ts,
    b.target_delivery_ts,
    b.actual_delivery_ts,
    b.returned_ts,
    b.shipment_status,
    b.sla_hours,
    b.attempt_count,
    b.parcel_issue_reason,
    b.delivery_issue_reason,
    b.return_reason,
    (b.at_origin_dp OR b.at_destination_dp) AS is_at_dp,
    CASE
        WHEN b.at_origin_dp THEN b.received_ts
        WHEN b.at_destination_dp THEN b.arrived_destination_ts
        ELSE NULL
    END AS at_dp_since_ts,
    CASE
        WHEN b.at_origin_dp THEN ROUND(EXTRACT(EPOCH FROM (b.reference_ts - b.received_ts)) / 3600.0, 2)
        WHEN b.at_destination_dp THEN ROUND(EXTRACT(EPOCH FROM (b.reference_ts - b.arrived_destination_ts)) / 3600.0, 2)
        ELSE NULL
    END AS parcel_age_hours,
    CASE
        WHEN b.shipment_status = 'RETURN_TO_SELLER' THEN 'RETURNED'
        WHEN b.shipment_status = 'FAILED' THEN 'FAILED'
        WHEN b.actual_delivery_ts IS NOT NULL
         AND b.target_delivery_ts IS NOT NULL
         AND b.actual_delivery_ts <= b.target_delivery_ts THEN 'ON_TIME'
        WHEN b.actual_delivery_ts IS NOT NULL
         AND b.target_delivery_ts IS NOT NULL
         AND b.actual_delivery_ts > b.target_delivery_ts THEN 'LATE'
        WHEN b.left_dp_ts IS NOT NULL
         AND b.actual_delivery_ts IS NULL
         AND b.shipment_status IN ('IN_TRANSIT', 'OUT_FOR_DELIVERY') THEN 'IN_TRANSIT'
        WHEN b.shipment_status = 'ARRIVED_DESTINATION' THEN 'AT_DESTINATION_DP'
        ELSE 'NOT_DISPATCHED'
    END AS delivery_class,
    CASE
        WHEN b.left_dp_ts IS NOT NULL
         AND b.actual_delivery_ts IS NULL
         AND b.shipment_status IN ('IN_TRANSIT', 'ARRIVED_DESTINATION', 'OUT_FOR_DELIVERY')
         AND b.target_delivery_ts IS NOT NULL
         AND b.reference_ts > b.target_delivery_ts
        THEN TRUE ELSE FALSE
    END AS is_overdue,
    CASE
        WHEN b.actual_delivery_ts IS NOT NULL AND b.left_dp_ts IS NOT NULL
        THEN ROUND(EXTRACT(EPOCH FROM (b.actual_delivery_ts - b.left_dp_ts)) / 3600.0, 2)
        ELSE NULL
    END AS delivery_hours,
    CASE
        WHEN b.actual_delivery_ts IS NOT NULL
         AND b.target_delivery_ts IS NOT NULL
         AND b.actual_delivery_ts > b.target_delivery_ts
        THEN ROUND(EXTRACT(EPOCH FROM (b.actual_delivery_ts - b.target_delivery_ts)) / 3600.0, 2)
        ELSE NULL
    END AS late_hours,
    CASE
        WHEN b.left_dp_ts IS NOT NULL
         AND b.actual_delivery_ts IS NULL
         AND b.target_delivery_ts IS NOT NULL
         AND b.reference_ts > b.target_delivery_ts
        THEN ROUND(EXTRACT(EPOCH FROM (b.reference_ts - b.target_delivery_ts)) / 3600.0, 2)
        ELSE NULL
    END AS overdue_hours,
    b.reference_ts
FROM base b
JOIN core.dim_drop_point odp ON b.origin_dp_id = odp.drop_point_id
JOIN core.dim_drop_point ddp ON b.destination_dp_id = ddp.drop_point_id
JOIN core.dim_seller s ON b.seller_id = s.seller_id
JOIN core.dim_staff sp ON s.seller_pic_id = sp.staff_id
LEFT JOIN core.dim_courier c ON b.courier_id = c.courier_id;

COMMIT;
