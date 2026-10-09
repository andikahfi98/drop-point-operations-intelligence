ALTER TABLE core.fact_delivery
ADD COLUMN IF NOT EXISTS shipment_ts TIMESTAMP,
ADD COLUMN IF NOT EXISTS sla_hours INTEGER,
ADD COLUMN IF NOT EXISTS target_delivery_ts TIMESTAMP,
ADD COLUMN IF NOT EXISTS actual_delivery_ts TIMESTAMP;
ALTER TABLE core.fact_delivery
DROP CONSTRAINT IF EXISTS chk_fact_delivery_sla_hours;

ALTER TABLE core.fact_delivery
ADD CONSTRAINT chk_fact_delivery_sla_hours
CHECK (sla_hours IS NULL OR sla_hours > 0);