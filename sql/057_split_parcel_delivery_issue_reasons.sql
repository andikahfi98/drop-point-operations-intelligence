-- ============================================================
-- 057 - Split parcel issue reason vs delivery issue reason
--
-- Parcel issue  = problem while parcel is still at Drop Point.
-- Delivery issue = problem after parcel has left Drop Point.
--
-- Existing issue_reason values are preserved as follows:
--   - parcel still at DP  -> parcel_issue_reason
--   - parcel already left -> delivery_issue_reason
-- Historical parcel issues that were previously cleared at dispatch
-- cannot be reconstructed; new simulator runs preserve both stages.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Physical tables
-- ------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'core'
          AND table_name = 'fact_shipment'
          AND column_name = 'issue_reason'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'core'
          AND table_name = 'fact_shipment'
          AND column_name = 'delivery_issue_reason'
    ) THEN
        ALTER TABLE core.fact_shipment
            RENAME COLUMN issue_reason TO delivery_issue_reason;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'raw'
          AND table_name = 'fact_shipment'
          AND column_name = 'issue_reason'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'raw'
          AND table_name = 'fact_shipment'
          AND column_name = 'delivery_issue_reason'
    ) THEN
        ALTER TABLE raw.fact_shipment
            RENAME COLUMN issue_reason TO delivery_issue_reason;
    END IF;
END $$;

ALTER TABLE core.fact_shipment
    ADD COLUMN IF NOT EXISTS parcel_issue_reason VARCHAR(40);

ALTER TABLE raw.fact_shipment
    ADD COLUMN IF NOT EXISTS parcel_issue_reason TEXT;

-- Existing unresolved DP issues belong to the parcel stage.
UPDATE core.fact_shipment
SET
    parcel_issue_reason = COALESCE(parcel_issue_reason, delivery_issue_reason),
    delivery_issue_reason = NULL
WHERE left_dp_ts IS NULL
  AND shipment_status IN ('RECEIVED', 'SORTING', 'READY')
  AND delivery_issue_reason IS NOT NULL;

UPDATE raw.fact_shipment
SET
    parcel_issue_reason = COALESCE(parcel_issue_reason, delivery_issue_reason),
    delivery_issue_reason = NULL
WHERE (left_dp_ts IS NULL OR BTRIM(left_dp_ts) = '')
  AND shipment_status IN ('RECEIVED', 'SORTING', 'READY')
  AND delivery_issue_reason IS NOT NULL;

-- ------------------------------------------------------------
-- 2. Constraints with explicit stage meaning
-- ------------------------------------------------------------
ALTER TABLE core.fact_shipment
    DROP CONSTRAINT IF EXISTS chk_shipment_issue_reason;

ALTER TABLE core.fact_shipment
    DROP CONSTRAINT IF EXISTS chk_shipment_parcel_issue_reason;

ALTER TABLE core.fact_shipment
    DROP CONSTRAINT IF EXISTS chk_shipment_delivery_issue_reason;

ALTER TABLE core.fact_shipment
    ADD CONSTRAINT chk_shipment_parcel_issue_reason
    CHECK (
        parcel_issue_reason IS NULL
        OR parcel_issue_reason IN (
            'OPERATIONAL_DELAY',
            'CAPACITY_ISSUE',
            'LINEHAUL_DELAY',
            'OTHER'
        )
    );

ALTER TABLE core.fact_shipment
    ADD CONSTRAINT chk_shipment_delivery_issue_reason
    CHECK (
        delivery_issue_reason IS NULL
        OR delivery_issue_reason IN (
            'ADDRESS_ISSUE',
            'RECEIVER_UNAVAILABLE',
            'OPERATIONAL_DELAY',
            'CAPACITY_ISSUE',
            'LINEHAUL_DELAY',
            'VEHICLE_ISSUE',
            'OUTLET_CLOSED',
            'OTHER'
        )
    );

-- ------------------------------------------------------------
-- 3. Rename the old analytics output to its real meaning.
--    Drop only views that directly depend on the old generic issue field.
-- ------------------------------------------------------------
DROP VIEW IF EXISTS analytics.vw_drop_point_issue_summary;
DROP VIEW IF EXISTS analytics.vw_shipment_issues;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'analytics'
          AND table_name = 'vw_shipment_detail'
          AND column_name = 'issue_reason'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'analytics'
          AND table_name = 'vw_shipment_detail'
          AND column_name = 'delivery_issue_reason'
    ) THEN
        ALTER VIEW analytics.vw_shipment_detail
            RENAME COLUMN issue_reason TO delivery_issue_reason;
    END IF;
END $$;

-- ------------------------------------------------------------
-- 4. Parcel issues: only while parcel is physically still at DP.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.vw_parcel_issues AS
SELECT
    sh.shipment_id,
    sh.invoice_id,
    sh.drop_point_id,
    sh.drop_point_name,
    sh.outlet_id,
    sh.bp_code,
    sh.outlet_name,
    sh.pic_id,
    sh.pic_name,
    sh.shipment_status,
    CASE
        WHEN sh.parcel_age_hours >= 24 THEN 'PARCEL_STUCK'
        ELSE 'PARCEL_DELAY_RISK'
    END AS issue_type,
    f.parcel_issue_reason,
    sh.parcel_age_hours,
    sh.received_ts,
    sh.sorted_ts,
    sh.left_dp_ts
FROM analytics.vw_shipment_detail sh
JOIN core.fact_shipment f
  ON f.shipment_id = sh.shipment_id
WHERE sh.is_at_dp
  AND (
        sh.parcel_age_hours >= 24
        OR f.parcel_issue_reason IS NOT NULL
      );

-- ------------------------------------------------------------
-- 5. Delivery issues: only after parcel has left the DP.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.vw_delivery_issues AS
SELECT
    sh.shipment_id,
    sh.invoice_id,
    sh.drop_point_id,
    sh.drop_point_name,
    sh.outlet_id,
    sh.bp_code,
    sh.outlet_name,
    sh.pic_id,
    sh.pic_name,
    sh.shipment_status,
    sh.delivery_class,
    CASE
        WHEN sh.delivery_class = 'FAILED' THEN 'FAILED'
        WHEN sh.delivery_class = 'LATE' THEN 'LATE'
        WHEN sh.delivery_class = 'IN_TRANSIT' AND sh.is_overdue THEN 'OVERDUE'
        ELSE NULL
    END AS issue_type,
    sh.delivery_issue_reason,
    CASE
        WHEN sh.delivery_class = 'LATE' THEN sh.late_hours
        WHEN sh.delivery_class = 'IN_TRANSIT' AND sh.is_overdue THEN sh.overdue_hours
        ELSE NULL
    END AS issue_hours,
    sh.received_ts,
    sh.left_dp_ts,
    sh.target_delivery_ts,
    sh.actual_delivery_ts
FROM analytics.vw_shipment_detail sh
WHERE sh.left_dp_ts IS NOT NULL
  AND (
        sh.delivery_class IN ('LATE', 'FAILED')
        OR (sh.delivery_class = 'IN_TRANSIT' AND sh.is_overdue)
      );

-- ------------------------------------------------------------
-- 6. Compatibility view for any older downstream consumer.
--    New code uses the two stage-specific views above.
-- ------------------------------------------------------------
CREATE VIEW analytics.vw_shipment_issues AS
SELECT
    p.shipment_id,
    p.invoice_id,
    p.drop_point_id,
    p.drop_point_name,
    p.outlet_id,
    p.bp_code,
    p.outlet_name,
    p.pic_id,
    p.pic_name,
    p.shipment_status,
    'NOT_DISPATCHED'::text AS delivery_class,
    p.issue_type,
    p.parcel_issue_reason AS issue_reason,
    p.parcel_age_hours AS issue_hours,
    p.received_ts,
    p.left_dp_ts,
    NULL::timestamp AS target_delivery_ts,
    NULL::timestamp AS actual_delivery_ts,
    'PARCEL'::text AS issue_stage
FROM analytics.vw_parcel_issues p

UNION ALL

SELECT
    d.shipment_id,
    d.invoice_id,
    d.drop_point_id,
    d.drop_point_name,
    d.outlet_id,
    d.bp_code,
    d.outlet_name,
    d.pic_id,
    d.pic_name,
    d.shipment_status,
    d.delivery_class,
    d.issue_type,
    d.delivery_issue_reason AS issue_reason,
    d.issue_hours,
    d.received_ts,
    d.left_dp_ts,
    d.target_delivery_ts,
    d.actual_delivery_ts,
    'DELIVERY'::text AS issue_stage
FROM analytics.vw_delivery_issues d;

CREATE VIEW analytics.vw_drop_point_issue_summary AS
SELECT
    drop_point_id,
    drop_point_name,
    issue_stage,
    issue_type,
    COALESCE(issue_reason, 'OTHER') AS issue_reason,
    COUNT(*) AS issue_count
FROM analytics.vw_shipment_issues
GROUP BY
    drop_point_id,
    drop_point_name,
    issue_stage,
    issue_type,
    COALESCE(issue_reason, 'OTHER');

COMMIT;
