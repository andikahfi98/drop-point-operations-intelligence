-- ============================================================
-- 028_backfill_delivery_timestamps.sql
-- Backfill legacy delivery data using timestamp-based SLA logic
-- ============================================================

-- 1. Legacy shipment timestamp
-- Historical data only has order_date, so use 09:00 as proxy.
UPDATE core.fact_delivery
SET shipment_ts = order_date::timestamp + TIME '09:00:00'
WHERE shipment_ts IS NULL;


-- 2. Calculate target delivery timestamp
UPDATE core.fact_delivery
SET target_delivery_ts =
    shipment_ts + (sla_hours * INTERVAL '1 hour')
WHERE shipment_ts IS NOT NULL
  AND sla_hours IS NOT NULL;


-- 3. Actual arrival only exists when shipment reached recipient
UPDATE core.fact_delivery
SET actual_delivery_ts =
    CASE
        WHEN delivery_status IN ('DELIVERED', 'DELIVERED LATE')
             AND actual_delivery_hours IS NOT NULL
        THEN shipment_ts + (actual_delivery_hours * INTERVAL '1 hour')

        WHEN delivery_status = 'FAILED'
        THEN NULL

        ELSE actual_delivery_ts
    END;


-- 4. Recalculate successful delivery status from timestamps
-- Timestamp becomes the source of truth.
UPDATE core.fact_delivery
SET delivery_status =
    CASE
        WHEN actual_delivery_ts <= target_delivery_ts
            THEN 'DELIVERED'
        WHEN actual_delivery_ts > target_delivery_ts
            THEN 'DELIVERED LATE'
        ELSE delivery_status
    END
WHERE actual_delivery_ts IS NOT NULL
  AND target_delivery_ts IS NOT NULL;


-- 5. FAILED means shipment never reached the recipient
UPDATE core.fact_delivery
SET actual_delivery_ts = NULL
WHERE delivery_status = 'FAILED';