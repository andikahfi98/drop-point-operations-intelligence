-- ============================================================
-- 045 ALIGN DELIVERY STATE WITH SIMULATION CLOCK
--
-- Legacy/backfilled delivery records may contain final outcomes
-- that occur after the current simulation timestamp.
--
-- Those shipments must remain IN_TRANSIT until their event time
-- is actually reached by the simulator.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Successful deliveries whose actual arrival is still
--    in the future -> revert to IN_TRANSIT
-- ------------------------------------------------------------

WITH sim AS (
    SELECT
        current_business_date
        + current_business_time AS simulation_ts
    FROM app.simulation_state
    WHERE simulation_name = 'operations_demo'
)

UPDATE core.fact_delivery d
SET
    delivery_status = 'IN_TRANSIT',
    actual_delivery_date = NULL,
    actual_delivery_ts = NULL,
    actual_delivery_hours = NULL,
    on_time_flag = NULL,
    attempt_count = 1,
    failure_reason = NULL

FROM sim

WHERE d.delivery_status IN (
        'DELIVERED',
        'DELIVERED LATE'
    )
  AND d.actual_delivery_ts > sim.simulation_ts;


-- ------------------------------------------------------------
-- 2. Legacy FAILED shipments where old duration indicates the
--    failure event has not happened yet -> IN_TRANSIT
-- ------------------------------------------------------------

WITH sim AS (
    SELECT
        current_business_date
        + current_business_time AS simulation_ts
    FROM app.simulation_state
    WHERE simulation_name = 'operations_demo'
)

UPDATE core.fact_delivery d
SET
    delivery_status = 'IN_TRANSIT',
    actual_delivery_date = NULL,
    actual_delivery_ts = NULL,
    actual_delivery_hours = NULL,
    on_time_flag = NULL,
    attempt_count = 1,
    failure_reason = NULL

FROM sim

WHERE d.delivery_status = 'FAILED'
  AND d.shipment_ts IS NOT NULL
  AND (
        (
            d.actual_delivery_hours IS NOT NULL
            AND d.shipment_ts
                + (d.actual_delivery_hours * INTERVAL '1 hour')
                > sim.simulation_ts
        )
        OR
        (
            d.actual_delivery_hours IS NULL
            AND d.target_delivery_ts > sim.simulation_ts
        )
    );


-- ------------------------------------------------------------
-- 3. Keep raw prototype aligned
-- ------------------------------------------------------------

UPDATE raw.fact_delivery r
SET
    actual_delivery_date = NULL,
    delivery_status = 'IN_TRANSIT',
    actual_delivery_hours = NULL,
    on_time_flag = NULL,
    attempt_count = '1',
    failure_reason = NULL

FROM core.fact_delivery c

WHERE r.shipment_id = c.shipment_id
  AND c.delivery_status = 'IN_TRANSIT';