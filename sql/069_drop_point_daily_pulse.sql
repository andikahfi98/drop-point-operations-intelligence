-- Daily operational series for the dashboard. Uses the simulator clock and
-- existing shipment/revenue facts; no source rows or workflow schedules change.
BEGIN;

CREATE OR REPLACE VIEW analytics.vw_drop_point_daily_pulse AS
WITH clock AS (
    SELECT current_business_date + current_business_time AS reference_ts
    FROM app.simulation_state
    WHERE simulation_name = 'operations_demo'
), days AS (
    SELECT generate_series(
        reference_ts::date - INTERVAL '13 days',
        reference_ts::date,
        INTERVAL '1 day'
    )::date AS business_date
    FROM clock
), parcel_events AS (
    SELECT origin_dp_id AS drop_point_id, received_ts AS event_ts, 'IN' AS direction
    FROM core.fact_shipment WHERE received_ts IS NOT NULL
    UNION ALL
    SELECT origin_dp_id, left_dp_ts, 'OUT'
    FROM core.fact_shipment WHERE left_dp_ts IS NOT NULL
    UNION ALL
    SELECT destination_dp_id, arrived_destination_ts, 'IN'
    FROM core.fact_shipment
    WHERE destination_dp_id <> origin_dp_id AND arrived_destination_ts IS NOT NULL
    UNION ALL
    SELECT destination_dp_id, out_for_delivery_ts, 'OUT'
    FROM core.fact_shipment
    WHERE destination_dp_id <> origin_dp_id AND out_for_delivery_ts IS NOT NULL
), parcel_daily AS (
    SELECT e.drop_point_id, e.event_ts::date AS business_date,
           COUNT(*) FILTER (WHERE e.direction = 'IN') AS parcel_in,
           COUNT(*) FILTER (WHERE e.direction = 'OUT') AS parcel_out
    FROM parcel_events e CROSS JOIN clock c
    WHERE e.event_ts > c.reference_ts - INTERVAL '14 days'
      AND e.event_ts <= c.reference_ts
    GROUP BY e.drop_point_id, e.event_ts::date
), revenue_daily AS (
    SELECT r.drop_point_id, r.transaction_ts::date AS business_date,
           SUM(r.revenue) AS revenue, COUNT(*) AS invoices
    FROM core.fact_revenue r CROSS JOIN clock c
    WHERE r.transaction_ts > c.reference_ts - INTERVAL '14 days'
      AND r.transaction_ts <= c.reference_ts
    GROUP BY r.drop_point_id, r.transaction_ts::date
), delivery_daily AS (
    SELECT s.destination_dp_id AS drop_point_id,
           s.actual_delivery_ts::date AS business_date,
           COUNT(*) AS delivered,
           COUNT(*) FILTER (WHERE s.actual_delivery_ts <= s.target_delivery_ts) AS on_time
    FROM core.fact_shipment s CROSS JOIN clock c
    WHERE s.actual_delivery_ts > c.reference_ts - INTERVAL '14 days'
      AND s.actual_delivery_ts <= c.reference_ts
    GROUP BY s.destination_dp_id, s.actual_delivery_ts::date
)
SELECT d.business_date, dp.drop_point_id,
       COALESCE(p.parcel_in, 0) AS parcel_in,
       COALESCE(p.parcel_out, 0) AS parcel_out,
       COALESCE(r.revenue, 0) AS revenue,
       COALESCE(r.invoices, 0) AS invoices,
       COALESCE(v.delivered, 0) AS delivered,
       COALESCE(v.on_time, 0) AS on_time
FROM days d CROSS JOIN core.dim_drop_point dp
LEFT JOIN parcel_daily p ON p.drop_point_id = dp.drop_point_id AND p.business_date = d.business_date
LEFT JOIN revenue_daily r ON r.drop_point_id = dp.drop_point_id AND r.business_date = d.business_date
LEFT JOIN delivery_daily v ON v.drop_point_id = dp.drop_point_id AND v.business_date = d.business_date
WHERE dp.status = 'ACTIVE';

COMMIT;
