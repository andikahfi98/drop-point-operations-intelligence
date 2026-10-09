-- ============================================================
-- 060 - Final expedition / logistics domain rebaseline
--
-- Purpose
-- - Outlet -> Seller.
-- - PIC master -> Staff master with Drop Point Manager + unit PICs.
-- - Add operational units, couriers, receiver context, origin/destination DP,
--   return lifecycle, parcel weight, and responsibility mapping.
-- - Add website roles/access for Drop Point Manager and Regional Manager.
-- - Rebuild analytics with seller / parcel / delivery semantics.
--
-- Expected prior state
-- - Migrations through 059 have been applied.
-- - core.dim_pic, core.dim_outlet, core.fact_revenue,
--   core.fact_pic_target, and core.fact_shipment exist.
--
-- IMPORTANT
-- - Stop API and n8n before applying this migration.
-- - This migration rebuilds the analytics schema and changes core names.
-- ============================================================

BEGIN;

-- ============================================================
-- 0. PRE-FLIGHT
-- ============================================================
DO $$
BEGIN
    IF to_regclass('core.dim_pic') IS NULL THEN
        RAISE EXCEPTION 'core.dim_pic not found. Apply prior migrations first.';
    END IF;

    IF to_regclass('core.dim_outlet') IS NULL THEN
        RAISE EXCEPTION 'core.dim_outlet not found. Apply prior migrations first.';
    END IF;

    IF to_regclass('core.fact_revenue') IS NULL THEN
        RAISE EXCEPTION 'core.fact_revenue not found. Apply prior migrations first.';
    END IF;

    IF to_regclass('core.fact_pic_target') IS NULL THEN
        RAISE EXCEPTION 'core.fact_pic_target not found. Apply prior migrations first.';
    END IF;

    IF to_regclass('core.fact_shipment') IS NULL THEN
        RAISE EXCEPTION 'core.fact_shipment not found. Apply prior migrations first.';
    END IF;
END $$;

-- Analytics is derived data. Rebuild it cleanly from the final domain.
DROP SCHEMA IF EXISTS analytics CASCADE;
CREATE SCHEMA analytics;

-- ============================================================
-- 1. OPERATIONAL UNIT MASTER
-- ============================================================
CREATE TABLE core.dim_unit (
    unit_code       VARCHAR(30) PRIMARY KEY,
    unit_name       VARCHAR(100) NOT NULL,
    description     VARCHAR(255),
    active_flag     BOOLEAN NOT NULL DEFAULT TRUE,
    loaded_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO core.dim_unit (unit_code, unit_name, description)
VALUES
    ('MANAGEMENT', 'Management', 'Overall Drop Point management and escalation'),
    ('SELLER', 'Seller', 'Seller relationship, revenue, and active seller coverage'),
    ('INBOUND', 'Inbound', 'Parcel receiving at the Drop Point'),
    ('SORTING', 'Sorting', 'Parcel sorting and preparation'),
    ('OUTBOUND', 'Outbound', 'Parcel release from the Drop Point and linehaul handoff'),
    ('DELIVERY', 'Delivery', 'Last-mile delivery and courier execution'),
    ('CUSTOMER_SERVICE', 'Customer Service', 'Receiver, address, exception, and return follow-up')
ON CONFLICT (unit_code) DO UPDATE SET
    unit_name = EXCLUDED.unit_name,
    description = EXCLUDED.description,
    active_flag = TRUE;

-- ============================================================
-- 2. PIC -> STAFF; CREATE MANAGER + UNIT STRUCTURE
-- ============================================================
ALTER TABLE core.dim_pic RENAME TO dim_staff;
ALTER TABLE core.dim_staff RENAME COLUMN pic_id TO staff_id;
ALTER TABLE core.dim_staff RENAME COLUMN pic_name TO staff_name;
ALTER TABLE core.dim_staff RENAME COLUMN role TO role_code;

ALTER TABLE core.dim_staff
    ADD COLUMN unit_code VARCHAR(30),
    ADD COLUMN manager_staff_id VARCHAR(20);

-- Existing PICs came from the prior commercial/seller model.
UPDATE core.dim_staff
SET
    unit_code = 'SELLER',
    role_code = 'PIC';

-- One Drop Point Manager per DP. Use existing manager_name when available.
INSERT INTO core.dim_staff (
    staff_id,
    staff_name,
    drop_point_id,
    role_code,
    join_date,
    status,
    unit_code,
    manager_staff_id,
    loaded_at
)
SELECT
    'MGR-' || REPLACE(dp.drop_point_id, 'DP-', '') AS staff_id,
    COALESCE(NULLIF(BTRIM(dp.manager_name), ''), 'Manager ' || dp.drop_point_name) AS staff_name,
    dp.drop_point_id,
    'MANAGER',
    NULL,
    'ACTIVE',
    'MANAGEMENT',
    NULL,
    NOW()
FROM core.dim_drop_point dp
ON CONFLICT (staff_id) DO UPDATE SET
    staff_name = EXCLUDED.staff_name,
    drop_point_id = EXCLUDED.drop_point_id,
    role_code = 'MANAGER',
    status = 'ACTIVE',
    unit_code = 'MANAGEMENT',
    manager_staff_id = NULL;

-- Existing seller PICs report to their Drop Point Manager.
UPDATE core.dim_staff s
SET manager_staff_id = 'MGR-' || REPLACE(s.drop_point_id, 'DP-', '')
WHERE s.role_code = 'PIC'
  AND s.unit_code = 'SELLER';

-- Seed one operational PIC for each non-seller operational unit per Drop Point.
WITH unit_seed(unit_code, id_code, label) AS (
    VALUES
        ('INBOUND', 'INB', 'Inbound'),
        ('SORTING', 'SRT', 'Sorting'),
        ('OUTBOUND', 'OUT', 'Outbound'),
        ('DELIVERY', 'DEL', 'Delivery'),
        ('CUSTOMER_SERVICE', 'CS', 'Customer Service')
)
INSERT INTO core.dim_staff (
    staff_id,
    staff_name,
    drop_point_id,
    role_code,
    join_date,
    status,
    unit_code,
    manager_staff_id,
    loaded_at
)
SELECT
    'PIC-' || u.id_code || '-' || REPLACE(dp.drop_point_id, 'DP-', ''),
    'PIC ' || u.label || ' - ' || dp.drop_point_name,
    dp.drop_point_id,
    'PIC',
    NULL,
    'ACTIVE',
    u.unit_code,
    'MGR-' || REPLACE(dp.drop_point_id, 'DP-', ''),
    NOW()
FROM core.dim_drop_point dp
CROSS JOIN unit_seed u
ON CONFLICT (staff_id) DO UPDATE SET
    staff_name = EXCLUDED.staff_name,
    drop_point_id = EXCLUDED.drop_point_id,
    role_code = 'PIC',
    status = 'ACTIVE',
    unit_code = EXCLUDED.unit_code,
    manager_staff_id = EXCLUDED.manager_staff_id;

ALTER TABLE core.dim_staff
    ALTER COLUMN unit_code SET NOT NULL;

ALTER TABLE core.dim_staff
    ADD CONSTRAINT fk_staff_unit
        FOREIGN KEY (unit_code)
        REFERENCES core.dim_unit(unit_code),
    ADD CONSTRAINT fk_staff_manager
        FOREIGN KEY (manager_staff_id)
        REFERENCES core.dim_staff(staff_id);

CREATE UNIQUE INDEX uq_dim_staff_staff_dp
    ON core.dim_staff(staff_id, drop_point_id);

CREATE UNIQUE INDEX uq_dim_staff_dp_manager
    ON core.dim_staff(drop_point_id)
    WHERE role_code = 'MANAGER'
      AND unit_code = 'MANAGEMENT'
      AND status = 'ACTIVE';

CREATE INDEX idx_dim_staff_dp_unit
    ON core.dim_staff(drop_point_id, unit_code, role_code);

-- Manager is now normalized in dim_staff.
ALTER TABLE core.dim_drop_point
    DROP COLUMN manager_name;

ALTER TABLE raw.dim_drop_point
    DROP COLUMN IF EXISTS manager_name;

-- ============================================================
-- 3. OUTLET -> SELLER
-- ============================================================
ALTER TABLE core.dim_outlet RENAME TO dim_seller;
ALTER TABLE core.dim_seller RENAME COLUMN outlet_id TO seller_id;
ALTER TABLE core.dim_seller RENAME COLUMN bp_code TO seller_code;
ALTER TABLE core.dim_seller RENAME COLUMN outlet_name TO seller_name;
ALTER TABLE core.dim_seller RENAME COLUMN pic_id TO seller_pic_id;
ALTER TABLE core.dim_seller RENAME COLUMN segment TO seller_segment;
ALTER TABLE core.dim_seller DROP COLUMN route_code;

-- Make same-DP seller ownership explicit.
ALTER TABLE core.dim_seller
    DROP CONSTRAINT IF EXISTS fk_outlet_salesperson;

ALTER TABLE core.dim_seller
    ADD CONSTRAINT fk_seller_pic_dp
        FOREIGN KEY (seller_pic_id, drop_point_id)
        REFERENCES core.dim_staff(staff_id, drop_point_id);

CREATE UNIQUE INDEX uq_dim_seller_seller_dp
    ON core.dim_seller(seller_id, drop_point_id);

CREATE INDEX idx_dim_seller_dp
    ON core.dim_seller(drop_point_id);

CREATE INDEX idx_dim_seller_pic
    ON core.dim_seller(seller_pic_id);

-- ============================================================
-- 4. REVENUE + SELLER TARGET TERMINOLOGY
-- ============================================================
ALTER TABLE core.fact_revenue RENAME COLUMN pic_id TO seller_pic_id;
ALTER TABLE core.fact_revenue RENAME COLUMN outlet_id TO seller_id;

ALTER INDEX IF EXISTS core.idx_fact_revenue_pic
    RENAME TO idx_fact_revenue_seller_pic;
ALTER INDEX IF EXISTS core.idx_fact_revenue_outlet
    RENAME TO idx_fact_revenue_seller;

ALTER TABLE core.fact_pic_target RENAME TO fact_seller_target;
ALTER TABLE core.fact_seller_target RENAME COLUMN pic_id TO staff_id;
ALTER TABLE core.fact_seller_target RENAME COLUMN active_outlet_target TO active_seller_target;

-- RAW revenue / target terminology.
ALTER TABLE raw.fact_revenue RENAME COLUMN pic_id TO seller_pic_id;
ALTER TABLE raw.fact_revenue RENAME COLUMN outlet_id TO seller_id;
ALTER TABLE raw.fact_pic_target RENAME TO fact_seller_target;
ALTER TABLE raw.fact_seller_target RENAME COLUMN pic_id TO staff_id;
ALTER TABLE raw.fact_seller_target RENAME COLUMN active_outlet_target TO active_seller_target;

-- ============================================================
-- 5. COURIER MASTER
-- ============================================================
CREATE TABLE core.dim_courier (
    courier_id       VARCHAR(20) PRIMARY KEY,
    courier_name     VARCHAR(120) NOT NULL,
    drop_point_id    VARCHAR(20) NOT NULL,
    vehicle_type     VARCHAR(30) NOT NULL DEFAULT 'MOTOR',
    active_flag      BOOLEAN NOT NULL DEFAULT TRUE,
    loaded_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_courier_drop_point
        FOREIGN KEY (drop_point_id)
        REFERENCES core.dim_drop_point(drop_point_id),

    CONSTRAINT chk_courier_vehicle
        CHECK (vehicle_type IN ('MOTOR', 'CAR', 'VAN'))
);

INSERT INTO core.dim_courier (
    courier_id,
    courier_name,
    drop_point_id,
    vehicle_type
)
SELECT
    'CUR-' || REPLACE(dp.drop_point_id, 'DP-', '') || '-' || LPAD(g::text, 2, '0'),
    'Courier ' || g || ' - ' || dp.drop_point_name,
    dp.drop_point_id,
    CASE WHEN g = 3 THEN 'VAN' ELSE 'MOTOR' END
FROM core.dim_drop_point dp
CROSS JOIN generate_series(1, 3) AS g
ON CONFLICT (courier_id) DO NOTHING;

CREATE INDEX idx_dim_courier_dp
    ON core.dim_courier(drop_point_id, active_flag);

-- ============================================================
-- 6. SHIPMENT: SELLER, RECEIVER, ORIGIN/DESTINATION, COURIER,
--    WEIGHT, RETURN, AND EXTENDED LIFECYCLE
-- ============================================================
ALTER TABLE core.fact_shipment RENAME COLUMN drop_point_id TO origin_dp_id;
ALTER TABLE core.fact_shipment RENAME COLUMN outlet_id TO seller_id;

ALTER TABLE core.fact_shipment
    ADD COLUMN destination_dp_id VARCHAR(20),
    ADD COLUMN receiver_name VARCHAR(150),
    ADD COLUMN receiver_area VARCHAR(100),
    ADD COLUMN courier_id VARCHAR(20),
    ADD COLUMN weight_kg NUMERIC(8,2),
    ADD COLUMN arrived_destination_ts TIMESTAMP,
    ADD COLUMN out_for_delivery_ts TIMESTAMP,
    ADD COLUMN returned_ts TIMESTAMP,
    ADD COLUMN return_reason VARCHAR(40);

-- Existing prototype shipments are local-DP historical shipments.
UPDATE core.fact_shipment sh
SET
    destination_dp_id = sh.origin_dp_id,
    receiver_name = 'Receiver ' || RIGHT(sh.shipment_id, 6),
    receiver_area = dp.area,
    weight_kg = ROUND(
        (0.50 + MOD(ABS(hashtextextended(sh.shipment_id, 0)), 950)::numeric / 100.0),
        2
    ),
    arrived_destination_ts = CASE
        WHEN sh.left_dp_ts IS NOT NULL THEN sh.left_dp_ts
        ELSE NULL
    END,
    out_for_delivery_ts = CASE
        WHEN sh.left_dp_ts IS NOT NULL THEN sh.left_dp_ts
        ELSE NULL
    END
FROM core.dim_drop_point dp
WHERE dp.drop_point_id = sh.origin_dp_id;

-- Map the legacy seller/outlet-closed reason into receiver semantics.
UPDATE core.fact_shipment
SET delivery_issue_reason = 'RECEIVER_UNAVAILABLE'
WHERE delivery_issue_reason = 'OUTLET_CLOSED';

-- Deterministically assign a courier to historical shipments that left the DP.
WITH choices AS (
    SELECT
        sh.shipment_id,
        c.courier_id,
        ROW_NUMBER() OVER (
            PARTITION BY sh.shipment_id
            ORDER BY c.courier_id
        ) AS rn,
        1 + MOD(ABS(hashtextextended(sh.shipment_id, 1)), 3) AS pick
    FROM core.fact_shipment sh
    JOIN core.dim_courier c
      ON c.drop_point_id = sh.destination_dp_id
    WHERE sh.left_dp_ts IS NOT NULL
)
UPDATE core.fact_shipment sh
SET courier_id = c.courier_id
FROM choices c
WHERE c.shipment_id = sh.shipment_id
  AND c.rn = c.pick;

ALTER TABLE core.fact_shipment
    ALTER COLUMN destination_dp_id SET NOT NULL,
    ALTER COLUMN receiver_name SET NOT NULL,
    ALTER COLUMN receiver_area SET NOT NULL,
    ALTER COLUMN weight_kg SET NOT NULL;

ALTER TABLE core.fact_shipment
    DROP CONSTRAINT IF EXISTS chk_shipment_status,
    DROP CONSTRAINT IF EXISTS chk_shipment_delivery_issue_reason,
    DROP CONSTRAINT IF EXISTS chk_shipment_target_order,
    DROP CONSTRAINT IF EXISTS chk_shipment_actual_order;

ALTER TABLE core.fact_shipment
    ADD CONSTRAINT fk_shipment_destination_dp
        FOREIGN KEY (destination_dp_id)
        REFERENCES core.dim_drop_point(drop_point_id),
    ADD CONSTRAINT fk_shipment_courier
        FOREIGN KEY (courier_id)
        REFERENCES core.dim_courier(courier_id),
    ADD CONSTRAINT chk_shipment_weight
        CHECK (weight_kg > 0),
    ADD CONSTRAINT chk_shipment_status
        CHECK (
            shipment_status IN (
                'RECEIVED',
                'SORTING',
                'READY',
                'IN_TRANSIT',
                'ARRIVED_DESTINATION',
                'OUT_FOR_DELIVERY',
                'DELIVERED',
                'FAILED',
                'RETURN_TO_SELLER'
            )
        ),
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
                'OTHER'
            )
        ),
    ADD CONSTRAINT chk_shipment_return_reason
        CHECK (
            return_reason IS NULL
            OR return_reason IN (
                'MAX_ATTEMPT',
                'RECEIVER_REJECTED',
                'ADDRESS_INVALID',
                'DAMAGED',
                'OTHER'
            )
        ),
    ADD CONSTRAINT chk_shipment_target_order
        CHECK (
            target_delivery_ts IS NULL
            OR left_dp_ts IS NULL
            OR target_delivery_ts >= left_dp_ts
        ),
    ADD CONSTRAINT chk_shipment_arrival_order
        CHECK (
            arrived_destination_ts IS NULL
            OR left_dp_ts IS NULL
            OR arrived_destination_ts >= left_dp_ts
        ),
    ADD CONSTRAINT chk_shipment_out_for_delivery_order
        CHECK (
            out_for_delivery_ts IS NULL
            OR COALESCE(arrived_destination_ts, left_dp_ts) IS NULL
            OR out_for_delivery_ts >= COALESCE(arrived_destination_ts, left_dp_ts)
        ),
    ADD CONSTRAINT chk_shipment_actual_order
        CHECK (
            actual_delivery_ts IS NULL
            OR COALESCE(out_for_delivery_ts, left_dp_ts) IS NULL
            OR actual_delivery_ts >= COALESCE(out_for_delivery_ts, left_dp_ts)
        ),
    ADD CONSTRAINT chk_shipment_return_order
        CHECK (
            returned_ts IS NULL
            OR COALESCE(out_for_delivery_ts, left_dp_ts, received_ts) IS NULL
            OR returned_ts >= COALESCE(out_for_delivery_ts, left_dp_ts, received_ts)
        );

ALTER INDEX IF EXISTS core.idx_fact_shipment_drop_point
    RENAME TO idx_fact_shipment_origin_dp;
ALTER INDEX IF EXISTS core.idx_fact_shipment_outlet
    RENAME TO idx_fact_shipment_seller;

CREATE INDEX idx_fact_shipment_destination_dp
    ON core.fact_shipment(destination_dp_id);
CREATE INDEX idx_fact_shipment_courier
    ON core.fact_shipment(courier_id);
CREATE INDEX idx_fact_shipment_out_for_delivery_ts
    ON core.fact_shipment(out_for_delivery_ts);

-- ============================================================
-- 7. RAW DOMAIN REBUILD
-- ============================================================
DROP TABLE IF EXISTS raw.dim_pic;
DROP TABLE IF EXISTS raw.dim_outlet;
DROP TABLE IF EXISTS raw.dim_staff;
DROP TABLE IF EXISTS raw.dim_seller;
DROP TABLE IF EXISTS raw.dim_courier;
DROP TABLE IF EXISTS raw.dim_unit;

CREATE TABLE raw.dim_unit (
    raw_row_id BIGSERIAL PRIMARY KEY,
    unit_code TEXT,
    unit_name TEXT,
    description TEXT,
    active_flag TEXT,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE raw.dim_staff (
    raw_row_id BIGSERIAL PRIMARY KEY,
    staff_id TEXT,
    staff_name TEXT,
    drop_point_id TEXT,
    unit_code TEXT,
    role_code TEXT,
    manager_staff_id TEXT,
    join_date TEXT,
    status TEXT,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE raw.dim_seller (
    raw_row_id BIGSERIAL PRIMARY KEY,
    seller_id TEXT,
    seller_code TEXT,
    seller_name TEXT,
    drop_point_id TEXT,
    seller_pic_id TEXT,
    seller_segment TEXT,
    city_area TEXT,
    active_flag TEXT,
    open_date TEXT,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE raw.dim_courier (
    raw_row_id BIGSERIAL PRIMARY KEY,
    courier_id TEXT,
    courier_name TEXT,
    drop_point_id TEXT,
    vehicle_type TEXT,
    active_flag TEXT,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO raw.dim_unit (unit_code, unit_name, description, active_flag)
SELECT unit_code, unit_name, description, active_flag::text
FROM core.dim_unit;

INSERT INTO raw.dim_staff (
    staff_id, staff_name, drop_point_id, unit_code, role_code,
    manager_staff_id, join_date, status
)
SELECT
    staff_id, staff_name, drop_point_id, unit_code, role_code,
    manager_staff_id, join_date::text, status
FROM core.dim_staff;

INSERT INTO raw.dim_seller (
    seller_id, seller_code, seller_name, drop_point_id, seller_pic_id,
    seller_segment, city_area, active_flag, open_date
)
SELECT
    seller_id, seller_code, seller_name, drop_point_id, seller_pic_id,
    seller_segment, city_area, active_flag::text, open_date::text
FROM core.dim_seller;

INSERT INTO raw.dim_courier (
    courier_id, courier_name, drop_point_id, vehicle_type, active_flag
)
SELECT courier_id, courier_name, drop_point_id, vehicle_type, active_flag::text
FROM core.dim_courier;

-- Rebuild raw shipment from final core structure.
DROP TABLE raw.fact_shipment;
CREATE TABLE raw.fact_shipment (
    raw_row_id BIGSERIAL PRIMARY KEY,
    shipment_id TEXT,
    invoice_id TEXT,
    origin_dp_id TEXT,
    destination_dp_id TEXT,
    seller_id TEXT,
    receiver_name TEXT,
    receiver_area TEXT,
    courier_id TEXT,
    weight_kg TEXT,
    created_ts TEXT,
    received_ts TEXT,
    sorted_ts TEXT,
    left_dp_ts TEXT,
    arrived_destination_ts TEXT,
    out_for_delivery_ts TEXT,
    target_delivery_ts TEXT,
    actual_delivery_ts TEXT,
    returned_ts TEXT,
    shipment_status TEXT,
    sla_hours TEXT,
    attempt_count TEXT,
    parcel_issue_reason TEXT,
    delivery_issue_reason TEXT,
    return_reason TEXT,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO raw.fact_shipment (
    shipment_id, invoice_id, origin_dp_id, destination_dp_id, seller_id,
    receiver_name, receiver_area, courier_id, weight_kg,
    created_ts, received_ts, sorted_ts, left_dp_ts,
    arrived_destination_ts, out_for_delivery_ts,
    target_delivery_ts, actual_delivery_ts, returned_ts,
    shipment_status, sla_hours, attempt_count,
    parcel_issue_reason, delivery_issue_reason, return_reason
)
SELECT
    shipment_id,
    invoice_id,
    origin_dp_id,
    destination_dp_id,
    seller_id,
    receiver_name,
    receiver_area,
    courier_id,
    weight_kg::text,
    created_ts::text,
    received_ts::text,
    sorted_ts::text,
    left_dp_ts::text,
    arrived_destination_ts::text,
    out_for_delivery_ts::text,
    target_delivery_ts::text,
    actual_delivery_ts::text,
    returned_ts::text,
    shipment_status,
    sla_hours::text,
    attempt_count::text,
    parcel_issue_reason,
    delivery_issue_reason,
    return_reason
FROM core.fact_shipment;

-- ============================================================
-- 8. RESPONSIBILITY RULE MASTER
-- ============================================================
CREATE TABLE core.dim_responsibility_rule (
    rule_code               VARCHAR(50) PRIMARY KEY,
    stage_code              VARCHAR(30) NOT NULL,
    status_code             VARCHAR(30),
    issue_reason            VARCHAR(40),
    responsible_unit_code   VARCHAR(30) NOT NULL,
    escalation_unit_code    VARCHAR(30) NOT NULL DEFAULT 'MANAGEMENT',
    description             VARCHAR(255) NOT NULL,
    priority                SMALLINT NOT NULL DEFAULT 100,
    active_flag             BOOLEAN NOT NULL DEFAULT TRUE,
    loaded_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_resp_unit
        FOREIGN KEY (responsible_unit_code)
        REFERENCES core.dim_unit(unit_code),
    CONSTRAINT fk_resp_escalation_unit
        FOREIGN KEY (escalation_unit_code)
        REFERENCES core.dim_unit(unit_code)
);

INSERT INTO core.dim_responsibility_rule (
    rule_code, stage_code, status_code, issue_reason,
    responsible_unit_code, description, priority
)
VALUES
    ('REV_BELOW_TARGET', 'REVENUE', NULL, NULL, 'SELLER', 'Revenue or active seller performance below target', 10),
    ('SELLER_INACTIVE', 'SELLER', NULL, NULL, 'SELLER', 'Seller inactivity or seller coverage issue', 10),
    ('PARCEL_RECEIVED', 'PARCEL', 'RECEIVED', NULL, 'INBOUND', 'Parcel waiting in receiving stage', 20),
    ('PARCEL_SORTING', 'PARCEL', 'SORTING', NULL, 'SORTING', 'Parcel waiting in sorting stage', 20),
    ('PARCEL_READY', 'PARCEL', 'READY', NULL, 'OUTBOUND', 'Parcel ready but not yet released from Drop Point', 20),
    ('PARCEL_CAPACITY', 'PARCEL', NULL, 'CAPACITY_ISSUE', 'OUTBOUND', 'Parcel held due to capacity issue', 5),
    ('PARCEL_LINEHAUL', 'PARCEL', NULL, 'LINEHAUL_DELAY', 'OUTBOUND', 'Parcel held due to linehaul delay', 5),
    ('DELIVERY_ADDRESS', 'DELIVERY', NULL, 'ADDRESS_ISSUE', 'CUSTOMER_SERVICE', 'Address issue requires receiver / address follow-up', 5),
    ('DELIVERY_RECEIVER', 'DELIVERY', NULL, 'RECEIVER_UNAVAILABLE', 'CUSTOMER_SERVICE', 'Receiver unavailable requires follow-up', 5),
    ('DELIVERY_VEHICLE', 'DELIVERY', NULL, 'VEHICLE_ISSUE', 'DELIVERY', 'Courier or vehicle execution issue', 5),
    ('DELIVERY_OPERATIONAL', 'DELIVERY', NULL, 'OPERATIONAL_DELAY', 'DELIVERY', 'Last-mile operational delay', 10),
    ('DELIVERY_LINEHAUL', 'DELIVERY', 'IN_TRANSIT', 'LINEHAUL_DELAY', 'OUTBOUND', 'Linehaul delay before destination delivery', 5),
    ('RETURN', 'RETURN', 'RETURN_TO_SELLER', NULL, 'CUSTOMER_SERVICE', 'Return-to-seller follow-up and closure', 5)
ON CONFLICT (rule_code) DO UPDATE SET
    stage_code = EXCLUDED.stage_code,
    status_code = EXCLUDED.status_code,
    issue_reason = EXCLUDED.issue_reason,
    responsible_unit_code = EXCLUDED.responsible_unit_code,
    escalation_unit_code = EXCLUDED.escalation_unit_code,
    description = EXCLUDED.description,
    priority = EXCLUDED.priority,
    active_flag = TRUE;

-- ============================================================
-- 9. WEBSITE AUTHORIZATION + MANAGER ACCOUNTS
-- ============================================================
ALTER TABLE app.app_user
    ADD COLUMN IF NOT EXISTS staff_id VARCHAR(20);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_app_user_staff'
          AND conrelid = 'app.app_user'::regclass
    ) THEN
        ALTER TABLE app.app_user
            ADD CONSTRAINT fk_app_user_staff
            FOREIGN KEY (staff_id)
            REFERENCES core.dim_staff(staff_id);
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS app.user_region_access (
    user_id         VARCHAR(30) NOT NULL,
    region          VARCHAR(100) NOT NULL,
    granted_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at      TIMESTAMPTZ,
    PRIMARY KEY (user_id, region),
    CONSTRAINT fk_user_region_user
        FOREIGN KEY (user_id)
        REFERENCES app.app_user(user_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_user_region_dates
        CHECK (revoked_at IS NULL OR revoked_at >= granted_at)
);

INSERT INTO app.app_role (
    role_code, role_name, description,
    can_view_all_dp, is_active, data_scope
)
VALUES
    ('DP_MANAGER', 'Drop Point Manager', 'Manager access limited to assigned Drop Point', FALSE, TRUE, 'DROP_POINT'),
    ('REGIONAL_MANAGER', 'Regional Manager', 'Regional access to all assigned Drop Points in a region', FALSE, TRUE, 'REGION')
ON CONFLICT (role_code) DO UPDATE SET
    role_name = EXCLUDED.role_name,
    description = EXCLUDED.description,
    can_view_all_dp = EXCLUDED.can_view_all_dp,
    is_active = TRUE,
    data_scope = EXCLUDED.data_scope;

-- One website account per Drop Point Manager.
INSERT INTO app.app_user (
    user_id,
    full_name,
    email,
    password_hash,
    role_code,
    staff_id,
    status,
    must_change_password,
    created_at,
    updated_at
)
SELECT
    'USR-MGR-' || REPLACE(dp.drop_point_id, 'DP-', ''),
    s.staff_name,
    'manager.' || LOWER(
        REGEXP_REPLACE(
            REGEXP_REPLACE(dp.drop_point_name, '^Drop Point[[:space:]]*', '', 'i'),
            '[^a-zA-Z0-9]+', '.', 'g'
        )
    ) || '@demo.local',
    NULL,
    'DP_MANAGER',
    s.staff_id,
    'ACTIVE',
    TRUE,
    NOW(),
    NOW()
FROM core.dim_drop_point dp
JOIN core.dim_staff s
  ON s.drop_point_id = dp.drop_point_id
 AND s.unit_code = 'MANAGEMENT'
 AND s.role_code = 'MANAGER'
ON CONFLICT (user_id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    email = EXCLUDED.email,
    role_code = 'DP_MANAGER',
    staff_id = EXCLUDED.staff_id,
    status = 'ACTIVE',
    updated_at = NOW();

INSERT INTO app.user_drop_point_access (
    user_id, drop_point_id, access_type, is_primary
)
SELECT
    'USR-MGR-' || REPLACE(dp.drop_point_id, 'DP-', ''),
    dp.drop_point_id,
    'VIEW',
    TRUE
FROM core.dim_drop_point dp
ON CONFLICT (user_id, drop_point_id) DO UPDATE SET
    access_type = 'VIEW',
    is_primary = TRUE,
    revoked_at = NULL;

-- One Regional Manager demo account per distinct region.
INSERT INTO app.app_user (
    user_id,
    full_name,
    email,
    password_hash,
    role_code,
    staff_id,
    status,
    must_change_password,
    created_at,
    updated_at
)
SELECT DISTINCT
    'USR-RM-' || UPPER(SUBSTRING(MD5(dp.region), 1, 8)),
    'Regional Manager - ' || dp.region,
    'regional.' || LOWER(REGEXP_REPLACE(dp.region, '[^a-zA-Z0-9]+', '.', 'g')) || '@demo.local',
    NULL,
    'REGIONAL_MANAGER',
    NULL,
    'ACTIVE',
    TRUE,
    NOW(),
    NOW()
FROM core.dim_drop_point dp
ON CONFLICT (user_id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    email = EXCLUDED.email,
    role_code = 'REGIONAL_MANAGER',
    status = 'ACTIVE',
    updated_at = NOW();

INSERT INTO app.user_region_access (user_id, region)
SELECT DISTINCT
    'USR-RM-' || UPPER(SUBSTRING(MD5(dp.region), 1, 8)),
    dp.region
FROM core.dim_drop_point dp
ON CONFLICT (user_id, region) DO UPDATE SET
    revoked_at = NULL;

INSERT INTO app.user_drop_point_access (
    user_id, drop_point_id, access_type, is_primary
)
SELECT
    'USR-RM-' || UPPER(SUBSTRING(MD5(dp.region), 1, 8)),
    dp.drop_point_id,
    'VIEW',
    FALSE
FROM core.dim_drop_point dp
ON CONFLICT (user_id, drop_point_id) DO UPDATE SET
    access_type = 'VIEW',
    is_primary = FALSE,
    revoked_at = NULL;

-- ============================================================
-- 10. ANALYTICS - FRESHNESS / PERIOD
-- ============================================================
CREATE VIEW analytics.vw_data_freshness AS
WITH simulation AS (
    SELECT
        current_business_date,
        current_business_time,
        current_business_date + current_business_time AS simulation_ts
    FROM app.simulation_state
    WHERE simulation_name = 'operations_demo'
),
freshness AS (
    SELECT
        (
            SELECT MAX(r.revenue_date)
            FROM core.fact_revenue r
            CROSS JOIN simulation s
            WHERE r.transaction_ts <= s.simulation_ts
        ) AS latest_revenue_date,
        (
            SELECT MAX(r.transaction_ts)
            FROM core.fact_revenue r
            CROSS JOIN simulation s
            WHERE r.transaction_ts <= s.simulation_ts
        ) AS latest_revenue_ts,
        (
            SELECT MAX(sh.received_ts)
            FROM core.fact_shipment sh
            CROSS JOIN simulation s
            WHERE sh.received_ts <= s.simulation_ts
        ) AS latest_received_ts,
        (
            SELECT MAX(sh.left_dp_ts)
            FROM core.fact_shipment sh
            CROSS JOIN simulation s
            WHERE sh.left_dp_ts <= s.simulation_ts
        ) AS latest_left_dp_ts,
        (
            SELECT MAX(sh.actual_delivery_ts)
            FROM core.fact_shipment sh
            CROSS JOIN simulation s
            WHERE sh.actual_delivery_ts <= s.simulation_ts
        ) AS latest_actual_delivery_ts
)
SELECT
    f.latest_revenue_date,
    f.latest_revenue_ts,
    f.latest_received_ts,
    f.latest_left_dp_ts,
    f.latest_actual_delivery_ts,
    s.simulation_ts,
    CASE
        WHEN f.latest_revenue_ts IS NULL THEN NULL
        ELSE ROUND(EXTRACT(EPOCH FROM (s.simulation_ts - f.latest_revenue_ts)) / 60.0, 2)
    END AS revenue_freshness_minutes,
    CASE
        WHEN f.latest_received_ts IS NULL THEN NULL
        ELSE ROUND(EXTRACT(EPOCH FROM (s.simulation_ts - f.latest_received_ts)) / 60.0, 2)
    END AS parcel_freshness_minutes
FROM freshness f
CROSS JOIN simulation s;

CREATE VIEW analytics.vw_current_period AS
WITH params AS (
    SELECT
        current_business_date AS as_of_date,
        DATE_TRUNC('month', current_business_date)::date AS month_start
    FROM app.simulation_state
    WHERE simulation_name = 'operations_demo'
)
SELECT
    p.as_of_date,
    p.month_start,
    (p.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_end,
    COUNT(*) FILTER (WHERE d.is_working_day = TRUE) AS total_working_days,
    COUNT(*) FILTER (
        WHERE d.is_working_day = TRUE
          AND d.date <= p.as_of_date
    ) AS elapsed_working_days,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE d.is_working_day = TRUE
              AND d.date <= p.as_of_date
        ) / NULLIF(COUNT(*) FILTER (WHERE d.is_working_day = TRUE), 0),
        2
    ) AS expected_achievement_pct
FROM params p
JOIN core.dim_date d
  ON d.month_start = p.month_start
GROUP BY p.as_of_date, p.month_start;

-- ============================================================
-- 11. ANALYTICS - TEAM / WEBSITE ACCESS
-- ============================================================
CREATE VIEW analytics.vw_drop_point_team AS
SELECT
    dp.drop_point_id,
    dp.drop_point_name,
    dp.region,
    s.staff_id,
    s.staff_name,
    s.unit_code,
    u.unit_name,
    s.role_code,
    s.manager_staff_id,
    m.staff_name AS manager_name,
    s.status
FROM core.dim_staff s
JOIN core.dim_drop_point dp
  ON s.drop_point_id = dp.drop_point_id
JOIN core.dim_unit u
  ON s.unit_code = u.unit_code
LEFT JOIN core.dim_staff m
  ON s.manager_staff_id = m.staff_id;

CREATE VIEW app.vw_user_access_scope AS
SELECT
    u.user_id,
    u.full_name,
    u.email,
    u.role_code,
    u.staff_id,
    a.drop_point_id,
    dp.drop_point_name,
    dp.region,
    a.is_primary,
    a.access_type
FROM app.app_user u
JOIN app.user_drop_point_access a
  ON u.user_id = a.user_id
 AND a.revoked_at IS NULL
JOIN core.dim_drop_point dp
  ON a.drop_point_id = dp.drop_point_id
WHERE u.status = 'ACTIVE';

-- ============================================================
-- 12. ANALYTICS - REVENUE / SELLER PIC
-- ============================================================
CREATE VIEW analytics.vw_seller_pic_monthly_performance AS
WITH revenue AS (
    SELECT
        DATE_TRUNC('month', revenue_date)::date AS month_start,
        drop_point_id,
        seller_pic_id AS staff_id,
        COUNT(*) AS total_transaction,
        COUNT(DISTINCT seller_id) AS active_seller,
        SUM(revenue) AS revenue
    FROM core.fact_revenue
    GROUP BY 1, 2, 3
)
SELECT
    t.month_start,
    t.drop_point_id,
    dp.drop_point_name,
    t.staff_id,
    s.staff_name,
    COALESCE(r.total_transaction, 0) AS total_transaction,
    COALESCE(r.active_seller, 0) AS active_seller,
    COALESCE(r.revenue, 0) AS revenue,
    t.revenue_target,
    t.active_seller_target,
    COALESCE(r.revenue, 0) - t.revenue_target AS revenue_variance,
    ROUND(100.0 * COALESCE(r.revenue, 0) / NULLIF(t.revenue_target, 0), 2)
        AS revenue_achievement_pct,
    COALESCE(r.active_seller, 0) - t.active_seller_target AS active_seller_variance,
    ROUND(100.0 * COALESCE(r.active_seller, 0) / NULLIF(t.active_seller_target, 0), 2)
        AS active_seller_achievement_pct
FROM core.fact_seller_target t
JOIN core.dim_drop_point dp
  ON t.drop_point_id = dp.drop_point_id
JOIN core.dim_staff s
  ON t.staff_id = s.staff_id
 AND s.unit_code = 'SELLER'
LEFT JOIN revenue r
  ON t.month_start = r.month_start
 AND t.drop_point_id = r.drop_point_id
 AND t.staff_id = r.staff_id;

CREATE VIEW analytics.vw_drop_point_revenue_monthly AS
WITH revenue AS (
    SELECT
        DATE_TRUNC('month', revenue_date)::date AS month_start,
        drop_point_id,
        COUNT(*) AS total_transaction,
        COUNT(DISTINCT seller_id) AS active_seller,
        SUM(revenue) AS revenue
    FROM core.fact_revenue
    GROUP BY 1, 2
),
target AS (
    SELECT
        month_start,
        drop_point_id,
        SUM(revenue_target) AS revenue_target,
        SUM(active_seller_target) AS active_seller_target
    FROM core.fact_seller_target
    GROUP BY 1, 2
)
SELECT
    t.month_start,
    t.drop_point_id,
    dp.drop_point_name,
    dp.region,
    dp.area,
    COALESCE(r.total_transaction, 0) AS total_transaction,
    COALESCE(r.active_seller, 0) AS active_seller,
    COALESCE(r.revenue, 0) AS revenue,
    t.revenue_target,
    t.active_seller_target,
    COALESCE(r.revenue, 0) - t.revenue_target AS revenue_variance,
    ROUND(100.0 * COALESCE(r.revenue, 0) / NULLIF(t.revenue_target, 0), 2)
        AS revenue_achievement_pct,
    COALESCE(r.active_seller, 0) - t.active_seller_target AS active_seller_variance,
    ROUND(100.0 * COALESCE(r.active_seller, 0) / NULLIF(t.active_seller_target, 0), 2)
        AS active_seller_achievement_pct
FROM target t
JOIN core.dim_drop_point dp
  ON t.drop_point_id = dp.drop_point_id
LEFT JOIN revenue r
  ON t.month_start = r.month_start
 AND t.drop_point_id = r.drop_point_id;

CREATE VIEW analytics.vw_drop_point_current_performance AS
WITH period AS (
    SELECT * FROM analytics.vw_current_period
)
SELECT
    p.as_of_date,
    p.month_start,
    p.total_working_days,
    p.elapsed_working_days,
    p.expected_achievement_pct,
    r.drop_point_id,
    r.drop_point_name,
    r.region,
    r.area,
    r.revenue,
    r.revenue_target,
    r.revenue_achievement_pct,
    ROUND(r.revenue_achievement_pct - p.expected_achievement_pct, 2) AS revenue_gap_pct,
    r.active_seller,
    r.active_seller_target,
    r.active_seller_achievement_pct,
    CASE
        WHEN r.revenue_achievement_pct - p.expected_achievement_pct <= -20 THEN 'CRITICAL'
        WHEN r.revenue_achievement_pct - p.expected_achievement_pct <= -10 THEN 'WATCH'
        ELSE 'NORMAL'
    END AS revenue_status
FROM analytics.vw_drop_point_revenue_monthly r
CROSS JOIN period p
WHERE r.month_start = p.month_start;

CREATE VIEW analytics.vw_seller_pic_current_performance AS
WITH period AS (
    SELECT as_of_date, month_start, expected_achievement_pct
    FROM analytics.vw_current_period
),
base AS (
    SELECT
        p.as_of_date,
        r.month_start,
        r.drop_point_id,
        r.drop_point_name,
        r.staff_id,
        r.staff_name,
        r.revenue,
        r.revenue_target,
        r.revenue_achievement_pct,
        p.expected_achievement_pct,
        ROUND(r.revenue_achievement_pct - p.expected_achievement_pct, 2) AS revenue_gap_pct,
        r.active_seller,
        r.active_seller_target,
        r.active_seller_achievement_pct
    FROM analytics.vw_seller_pic_monthly_performance r
    CROSS JOIN period p
    WHERE r.month_start = p.month_start
)
SELECT
    *,
    CASE
        WHEN revenue_target IS NULL OR revenue_target <= 0 THEN 'NO_DATA'
        ELSE 'SUFFICIENT_DATA'
    END AS pic_data_status,
    CASE
        WHEN revenue_target IS NULL OR revenue_target <= 0 THEN 'NORMAL'
        WHEN revenue_gap_pct <= -20 THEN 'CRITICAL'
        WHEN revenue_gap_pct < 0 THEN 'WATCH'
        ELSE 'NORMAL'
    END AS pic_status
FROM base;

-- ============================================================
-- 13. ANALYTICS - SHIPMENT DETAIL / CURRENT RESPONSIBILITY
-- ============================================================
CREATE VIEW analytics.vw_shipment_detail AS
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
         AND b.shipment_status IN ('IN_TRANSIT', 'ARRIVED_DESTINATION', 'OUT_FOR_DELIVERY') THEN 'IN_TRANSIT'
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

CREATE VIEW analytics.vw_shipment_responsibility AS
WITH classified AS (
    SELECT
        sh.*,
        CASE
            WHEN sh.shipment_status = 'RETURN_TO_SELLER' THEN 'RETURN'
            WHEN sh.is_at_dp THEN 'PARCEL'
            WHEN sh.delivery_class IN ('IN_TRANSIT', 'ON_TIME', 'LATE', 'FAILED', 'RETURNED') THEN 'DELIVERY'
            ELSE 'PARCEL'
        END AS stage_code,
        CASE
            WHEN sh.parcel_issue_reason = 'CAPACITY_ISSUE' THEN 'OUTBOUND'
            WHEN sh.parcel_issue_reason = 'LINEHAUL_DELAY' THEN 'OUTBOUND'
            WHEN sh.is_at_dp AND sh.shipment_status = 'RECEIVED' THEN 'INBOUND'
            WHEN sh.is_at_dp AND sh.shipment_status = 'SORTING' THEN 'SORTING'
            WHEN sh.is_at_dp AND sh.shipment_status = 'READY' THEN 'OUTBOUND'
            WHEN sh.shipment_status = 'IN_TRANSIT' THEN 'OUTBOUND'
            WHEN sh.shipment_status = 'ARRIVED_DESTINATION' THEN 'INBOUND'
            WHEN sh.delivery_issue_reason IN ('ADDRESS_ISSUE', 'RECEIVER_UNAVAILABLE') THEN 'CUSTOMER_SERVICE'
            WHEN sh.shipment_status = 'RETURN_TO_SELLER' THEN 'CUSTOMER_SERVICE'
            WHEN sh.delivery_issue_reason = 'LINEHAUL_DELAY' THEN 'OUTBOUND'
            WHEN sh.shipment_status IN ('OUT_FOR_DELIVERY', 'FAILED') THEN 'DELIVERY'
            ELSE 'DELIVERY'
        END AS responsible_unit_code,
        CASE
            WHEN sh.is_at_dp THEN sh.current_dp_id
            WHEN sh.shipment_status = 'IN_TRANSIT' THEN sh.origin_dp_id
            ELSE sh.destination_dp_id
        END AS responsible_dp_id
    FROM analytics.vw_shipment_detail sh
)
SELECT
    c.*,
    u.unit_name AS responsible_unit_name,
    pic.staff_id AS responsible_staff_id,
    pic.staff_name AS responsible_staff_name,
    mgr.staff_id AS manager_staff_id,
    mgr.staff_name AS manager_name
FROM classified c
JOIN core.dim_unit u
  ON c.responsible_unit_code = u.unit_code
LEFT JOIN LATERAL (
    SELECT s.staff_id, s.staff_name
    FROM core.dim_staff s
    WHERE s.drop_point_id = c.responsible_dp_id
      AND s.unit_code = c.responsible_unit_code
      AND s.role_code = 'PIC'
      AND s.status = 'ACTIVE'
    ORDER BY s.staff_id
    LIMIT 1
) pic ON TRUE
LEFT JOIN LATERAL (
    SELECT s.staff_id, s.staff_name
    FROM core.dim_staff s
    WHERE s.drop_point_id = c.responsible_dp_id
      AND s.unit_code = 'MANAGEMENT'
      AND s.role_code = 'MANAGER'
      AND s.status = 'ACTIVE'
    ORDER BY s.staff_id
    LIMIT 1
) mgr ON TRUE;

-- ============================================================
-- 14. ANALYTICS - PARCEL FLOW AT DROP POINT
-- ============================================================
CREATE VIEW analytics.vw_drop_point_parcel_current AS
WITH period AS (
    SELECT as_of_date, month_start
    FROM analytics.vw_current_period
),
flow_events AS (
    SELECT
        shipment_id,
        origin_dp_id AS drop_point_id,
        received_ts AS parcel_in_ts,
        left_dp_ts AS parcel_out_ts
    FROM core.fact_shipment

    UNION ALL

    SELECT
        shipment_id,
        destination_dp_id AS drop_point_id,
        arrived_destination_ts AS parcel_in_ts,
        out_for_delivery_ts AS parcel_out_ts
    FROM core.fact_shipment
    WHERE destination_dp_id <> origin_dp_id
      AND arrived_destination_ts IS NOT NULL
),
flow_stats AS (
    SELECT
        dp.drop_point_id,
        dp.drop_point_name,
        COUNT(f.shipment_id) FILTER (
            WHERE f.parcel_in_ts::date BETWEEN p.month_start AND p.as_of_date
        ) AS parcel_in_mtd,
        COUNT(f.shipment_id) FILTER (
            WHERE f.parcel_out_ts::date BETWEEN p.month_start AND p.as_of_date
        ) AS parcel_out_mtd,
        COUNT(f.shipment_id) FILTER (
            WHERE f.parcel_in_ts::date = p.as_of_date
        ) AS parcel_in_today,
        COUNT(f.shipment_id) FILTER (
            WHERE f.parcel_out_ts::date = p.as_of_date
        ) AS parcel_out_today
    FROM core.dim_drop_point dp
    CROSS JOIN period p
    LEFT JOIN flow_events f
      ON dp.drop_point_id = f.drop_point_id
    GROUP BY dp.drop_point_id, dp.drop_point_name
),
aging AS (
    SELECT
        dp.drop_point_id,
        COUNT(sh.shipment_id) FILTER (WHERE sh.is_at_dp) AS parcel_at_dp,
        COUNT(sh.shipment_id) FILTER (WHERE sh.is_at_dp AND sh.parcel_age_hours < 6) AS parcel_under_6h,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.is_at_dp AND sh.parcel_age_hours >= 6 AND sh.parcel_age_hours < 12
        ) AS parcel_6_12h,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.is_at_dp AND sh.parcel_age_hours >= 12 AND sh.parcel_age_hours < 24
        ) AS parcel_12_24h,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.is_at_dp AND sh.parcel_age_hours >= 24
        ) AS parcel_over_24h,
        MAX(sh.parcel_age_hours) FILTER (WHERE sh.is_at_dp) AS oldest_parcel_hours,
        ROUND(AVG(sh.parcel_age_hours) FILTER (WHERE sh.is_at_dp), 2) AS avg_dp_hours
    FROM core.dim_drop_point dp
    LEFT JOIN analytics.vw_shipment_detail sh
      ON dp.drop_point_id = sh.current_dp_id
    GROUP BY dp.drop_point_id
),
metrics AS (
    SELECT
        f.drop_point_id,
        f.drop_point_name,
        f.parcel_in_mtd,
        f.parcel_out_mtd,
        f.parcel_in_today,
        f.parcel_out_today,
        COALESCE(a.parcel_at_dp, 0) AS parcel_at_dp,
        COALESCE(a.parcel_under_6h, 0) AS parcel_under_6h,
        COALESCE(a.parcel_6_12h, 0) AS parcel_6_12h,
        COALESCE(a.parcel_12_24h, 0) AS parcel_12_24h,
        COALESCE(a.parcel_over_24h, 0) AS parcel_over_24h,
        a.oldest_parcel_hours,
        a.avg_dp_hours,
        ROUND(100.0 * f.parcel_out_mtd / NULLIF(f.parcel_in_mtd, 0), 2) AS parcel_out_pct,
        ROUND(100.0 * COALESCE(a.parcel_over_24h, 0) / NULLIF(a.parcel_at_dp, 0), 2)
            AS parcel_over_24h_pct
    FROM flow_stats f
    LEFT JOIN aging a
      ON f.drop_point_id = a.drop_point_id
)
SELECT
    *,
    CASE
        WHEN parcel_over_24h >= 10 OR COALESCE(oldest_parcel_hours, 0) >= 48 THEN 'CRITICAL'
        WHEN parcel_over_24h >= 3 OR COALESCE(oldest_parcel_hours, 0) >= 24 THEN 'WATCH'
        ELSE 'NORMAL'
    END AS parcel_status
FROM metrics;

-- ============================================================
-- 15. ANALYTICS - DELIVERY / SLA
-- ============================================================
CREATE VIEW analytics.vw_drop_point_current_delivery AS
WITH period AS (
    SELECT as_of_date, month_start
    FROM analytics.vw_current_period
),
target AS (
    SELECT
        p.as_of_date,
        p.month_start,
        t.drop_point_id,
        ROUND(t.delivery_sla_target_pct * 100, 2) AS sla_target_pct
    FROM core.fact_delivery_target t
    CROSS JOIN period p
    WHERE t.month_start = p.month_start
),
delivery AS (
    SELECT
        sh.destination_dp_id AS drop_point_id,
        COUNT(*) AS total_shipment,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'ON_TIME') AS on_time_delivery,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'LATE') AS late_delivery,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'FAILED') AS failed_delivery,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'RETURNED') AS returned_delivery,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'IN_TRANSIT') AS in_transit_delivery,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'IN_TRANSIT' AND sh.is_overdue) AS overdue_delivery,
        COUNT(*) FILTER (WHERE sh.delivery_class IN ('ON_TIME', 'LATE', 'FAILED', 'RETURNED')) AS completed_delivery,
        COUNT(*) FILTER (WHERE sh.delivery_class IN ('ON_TIME', 'LATE')) AS successful_delivery,
        ROUND(AVG(sh.delivery_hours) FILTER (WHERE sh.delivery_class IN ('ON_TIME', 'LATE')), 2)
            AS avg_delivery_hours,
        ROUND(AVG(sh.late_hours) FILTER (WHERE sh.delivery_class = 'LATE'), 2) AS avg_delay_hours
    FROM analytics.vw_shipment_detail sh
    CROSS JOIN period p
    WHERE sh.left_dp_ts::date BETWEEN p.month_start AND p.as_of_date
    GROUP BY sh.destination_dp_id
),
base AS (
    SELECT
        t.as_of_date,
        t.month_start,
        t.drop_point_id,
        dp.drop_point_name,
        COALESCE(d.total_shipment, 0) AS total_shipment,
        COALESCE(d.on_time_delivery, 0) AS on_time_delivery,
        COALESCE(d.late_delivery, 0) AS late_delivery,
        COALESCE(d.failed_delivery, 0) AS failed_delivery,
        COALESCE(d.returned_delivery, 0) AS returned_delivery,
        COALESCE(d.overdue_delivery, 0) AS overdue_delivery,
        COALESCE(d.completed_delivery, 0) AS completed_delivery,
        COALESCE(d.successful_delivery, 0) AS successful_delivery,
        COALESCE(d.in_transit_delivery, 0) AS in_transit_delivery,
        d.avg_delivery_hours,
        d.avg_delay_hours,
        t.sla_target_pct
    FROM target t
    JOIN core.dim_drop_point dp ON t.drop_point_id = dp.drop_point_id
    LEFT JOIN delivery d ON t.drop_point_id = d.drop_point_id
)
SELECT
    *,
    ROUND(100.0 * on_time_delivery / NULLIF(completed_delivery, 0), 2) AS on_time_rate_pct,
    ROUND(100.0 * late_delivery / NULLIF(completed_delivery, 0), 2) AS late_rate_pct,
    ROUND(100.0 * failed_delivery / NULLIF(completed_delivery, 0), 2) AS failure_rate_pct,
    ROUND(100.0 * successful_delivery / NULLIF(completed_delivery, 0), 2) AS delivery_success_rate_pct
FROM base;

CREATE VIEW analytics.vw_drop_point_current_delivery_status AS
SELECT
    d.*,
    ROUND(d.on_time_rate_pct - d.sla_target_pct, 2) AS sla_gap_pct,
    CASE
        WHEN d.on_time_rate_pct IS NULL THEN NULL
        ELSE GREATEST(d.sla_target_pct - d.on_time_rate_pct, 0)
    END AS sla_shortfall_pct,
    CASE
        WHEN d.completed_delivery < 20 THEN 'NORMAL'
        WHEN d.on_time_rate_pct > d.sla_target_pct - 10 THEN 'NORMAL'
        WHEN d.on_time_rate_pct >= d.sla_target_pct - 20 THEN 'WATCH'
        ELSE 'CRITICAL'
    END AS delivery_status,
    CASE
        WHEN d.completed_delivery = 0 THEN 'NO_DATA'
        WHEN d.completed_delivery < 20 THEN 'INSUFFICIENT_DATA'
        ELSE 'SUFFICIENT_DATA'
    END AS delivery_data_status
FROM analytics.vw_drop_point_current_delivery d;

-- ============================================================
-- 16. ANALYTICS - SELLER ACTIVITY / ATTENTION
-- ============================================================
CREATE VIEW analytics.vw_seller_activity AS
WITH params AS (
    SELECT as_of_date, month_start
    FROM analytics.vw_current_period
),
revenue_activity AS (
    SELECT
        r.seller_id,
        MAX(r.revenue_date) AS last_transaction_date,
        COUNT(*) FILTER (
            WHERE r.revenue_date >= (SELECT month_start FROM params)
        ) AS current_month_transaction,
        SUM(r.revenue) FILTER (
            WHERE r.revenue_date >= (SELECT month_start FROM params)
        ) AS current_month_revenue
    FROM core.fact_revenue r
    GROUP BY r.seller_id
)
SELECT
    p.as_of_date,
    s.drop_point_id,
    dp.drop_point_name,
    s.seller_pic_id,
    st.staff_name AS seller_pic_name,
    s.seller_id,
    s.seller_code,
    s.seller_name,
    s.seller_segment,
    s.city_area,
    s.active_flag,
    r.last_transaction_date,
    CASE
        WHEN r.last_transaction_date IS NULL THEN NULL
        ELSE p.as_of_date - r.last_transaction_date
    END AS days_since_last_transaction,
    COALESCE(r.current_month_transaction, 0) AS current_month_transaction,
    COALESCE(r.current_month_revenue, 0) AS current_month_revenue,
    CASE
        WHEN s.active_flag = FALSE THEN 'INACTIVE_MASTER'
        WHEN r.last_transaction_date IS NULL THEN 'NO_REVENUE_HISTORY'
        WHEN p.as_of_date - r.last_transaction_date >= 14 THEN 'INACTIVE_14D'
        WHEN p.as_of_date - r.last_transaction_date >= 7 THEN 'WATCH_7D'
        ELSE 'ACTIVE'
    END AS activity_status
FROM core.dim_seller s
JOIN core.dim_drop_point dp ON s.drop_point_id = dp.drop_point_id
JOIN core.dim_staff st ON s.seller_pic_id = st.staff_id
LEFT JOIN revenue_activity r ON s.seller_id = r.seller_id
CROSS JOIN params p;

CREATE VIEW analytics.vw_seller_attention AS
SELECT
    a.*,
    CASE
        WHEN a.activity_status IN ('NO_REVENUE_HISTORY', 'INACTIVE_14D') THEN 'CRITICAL'
        WHEN a.activity_status = 'WATCH_7D' THEN 'WATCH'
        ELSE 'NORMAL'
    END AS attention_status
FROM analytics.vw_seller_activity a
WHERE a.active_flag = TRUE;

CREATE VIEW analytics.vw_drop_point_seller_attention_summary AS
SELECT
    as_of_date,
    drop_point_id,
    drop_point_name,
    COUNT(*) AS total_monitored_seller,
    COUNT(*) FILTER (WHERE attention_status = 'NORMAL') AS normal_seller,
    COUNT(*) FILTER (WHERE attention_status = 'WATCH') AS watch_seller,
    COUNT(*) FILTER (WHERE attention_status = 'CRITICAL') AS critical_seller,
    COUNT(*) FILTER (WHERE activity_status = 'INACTIVE_14D') AS inactive_14d_seller,
    COUNT(*) FILTER (WHERE activity_status = 'WATCH_7D') AS watch_7d_seller
FROM analytics.vw_seller_attention
GROUP BY as_of_date, drop_point_id, drop_point_name;

-- ============================================================
-- 17. ANALYTICS - ISSUE VIEWS WITH RESPONSIBILITY
-- ============================================================
CREATE VIEW analytics.vw_parcel_issues AS
SELECT
    r.shipment_id,
    r.invoice_id,
    r.current_dp_id AS drop_point_id,
    r.current_dp_name AS drop_point_name,
    r.seller_id,
    r.seller_code,
    r.seller_name,
    r.seller_pic_id,
    r.seller_pic_name,
    r.shipment_status,
    CASE
        WHEN r.parcel_age_hours >= 24 THEN 'PARCEL_STUCK'
        ELSE 'PARCEL_DELAY_RISK'
    END AS issue_type,
    r.parcel_issue_reason,
    r.parcel_age_hours,
    r.received_ts,
    r.sorted_ts,
    r.left_dp_ts,
    r.responsible_unit_code,
    r.responsible_unit_name,
    r.responsible_staff_id,
    r.responsible_staff_name,
    r.manager_staff_id,
    r.manager_name
FROM analytics.vw_shipment_responsibility r
WHERE r.is_at_dp
  AND (r.parcel_age_hours >= 24 OR r.parcel_issue_reason IS NOT NULL);

CREATE VIEW analytics.vw_delivery_issues AS
SELECT
    r.shipment_id,
    r.invoice_id,
    r.destination_dp_id AS drop_point_id,
    r.destination_dp_name AS drop_point_name,
    r.seller_id,
    r.seller_code,
    r.seller_name,
    r.receiver_name,
    r.receiver_area,
    r.courier_id,
    r.courier_name,
    r.shipment_status,
    r.delivery_class,
    CASE
        WHEN r.delivery_class = 'RETURNED' THEN 'RETURNED'
        WHEN r.delivery_class = 'FAILED' THEN 'FAILED'
        WHEN r.delivery_class = 'LATE' THEN 'LATE'
        WHEN r.delivery_class = 'IN_TRANSIT' AND r.is_overdue THEN 'OVERDUE'
        ELSE NULL
    END AS issue_type,
    r.delivery_issue_reason,
    CASE
        WHEN r.delivery_class = 'LATE' THEN r.late_hours
        WHEN r.delivery_class = 'IN_TRANSIT' AND r.is_overdue THEN r.overdue_hours
        ELSE NULL
    END AS issue_hours,
    r.left_dp_ts,
    r.target_delivery_ts,
    r.actual_delivery_ts,
    r.returned_ts,
    r.responsible_unit_code,
    r.responsible_unit_name,
    r.responsible_staff_id,
    r.responsible_staff_name,
    r.manager_staff_id,
    r.manager_name
FROM analytics.vw_shipment_responsibility r
WHERE r.left_dp_ts IS NOT NULL
  AND (
        r.delivery_class IN ('LATE', 'FAILED', 'RETURNED')
        OR (r.delivery_class = 'IN_TRANSIT' AND r.is_overdue)
      );

CREATE VIEW analytics.vw_drop_point_issue_summary AS
SELECT
    drop_point_id,
    drop_point_name,
    'PARCEL'::text AS issue_stage,
    issue_type,
    COALESCE(parcel_issue_reason, 'OTHER') AS issue_reason,
    responsible_unit_code,
    COUNT(*) AS issue_count
FROM analytics.vw_parcel_issues
GROUP BY
    drop_point_id, drop_point_name, issue_type,
    COALESCE(parcel_issue_reason, 'OTHER'), responsible_unit_code

UNION ALL

SELECT
    drop_point_id,
    drop_point_name,
    'DELIVERY'::text AS issue_stage,
    issue_type,
    COALESCE(delivery_issue_reason, 'OTHER') AS issue_reason,
    responsible_unit_code,
    COUNT(*) AS issue_count
FROM analytics.vw_delivery_issues
GROUP BY
    drop_point_id, drop_point_name, issue_type,
    COALESCE(delivery_issue_reason, 'OTHER'), responsible_unit_code;

-- ============================================================
-- 18. DAILY OPERATIONAL SUMMARY
-- ============================================================
CREATE VIEW analytics.vw_daily_operational_summary AS
WITH revenue AS (
    SELECT * FROM analytics.vw_drop_point_current_performance
),
seller AS (
    SELECT
        s.*,
        ROUND(100.0 * s.critical_seller / NULLIF(s.total_monitored_seller, 0), 2)
            AS critical_seller_pct,
        ROUND(
            100.0 * (s.critical_seller + s.watch_seller)
            / NULLIF(s.total_monitored_seller, 0),
            2
        ) AS attention_seller_pct
    FROM analytics.vw_drop_point_seller_attention_summary s
),
manager AS (
    SELECT
        drop_point_id,
        MAX(staff_id) FILTER (WHERE unit_code = 'MANAGEMENT' AND role_code = 'MANAGER') AS manager_staff_id,
        MAX(staff_name) FILTER (WHERE unit_code = 'MANAGEMENT' AND role_code = 'MANAGER') AS manager_name
    FROM analytics.vw_drop_point_team
    GROUP BY drop_point_id
),
combined AS (
    SELECT
        r.as_of_date,
        r.month_start,
        r.drop_point_id,
        r.drop_point_name,
        r.region,
        r.area,
        m.manager_staff_id,
        m.manager_name,
        r.revenue,
        r.revenue_target,
        r.revenue_achievement_pct,
        r.expected_achievement_pct,
        r.revenue_gap_pct,
        r.revenue_status,
        r.active_seller,
        r.active_seller_target,
        r.active_seller_achievement_pct,
        COALESCE(s.normal_seller, 0) AS normal_seller,
        COALESCE(s.watch_seller, 0) AS watch_seller,
        COALESCE(s.critical_seller, 0) AS critical_seller,
        COALESCE(s.total_monitored_seller, 0) AS total_monitored_seller,
        COALESCE(s.inactive_14d_seller, 0) AS inactive_14d_seller,
        COALESCE(s.critical_seller_pct, 0) AS critical_seller_pct,
        COALESCE(s.attention_seller_pct, 0) AS attention_seller_pct,
        CASE
            WHEN COALESCE(s.critical_seller_pct, 0) > 20 THEN 'CRITICAL'
            WHEN COALESCE(s.attention_seller_pct, 0) >= 10 THEN 'WATCH'
            ELSE 'NORMAL'
        END AS seller_status,
        COALESCE(p.parcel_in_mtd, 0) AS parcel_in_mtd,
        COALESCE(p.parcel_out_mtd, 0) AS parcel_out_mtd,
        COALESCE(p.parcel_at_dp, 0) AS parcel_at_dp,
        COALESCE(p.parcel_under_6h, 0) AS parcel_under_6h,
        COALESCE(p.parcel_6_12h, 0) AS parcel_6_12h,
        COALESCE(p.parcel_12_24h, 0) AS parcel_12_24h,
        COALESCE(p.parcel_over_24h, 0) AS parcel_over_24h,
        p.oldest_parcel_hours,
        p.avg_dp_hours,
        p.parcel_out_pct,
        COALESCE(p.parcel_status, 'NORMAL') AS parcel_status,
        COALESCE(d.total_shipment, 0) AS total_shipment,
        COALESCE(d.completed_delivery, 0) AS completed_delivery,
        COALESCE(d.in_transit_delivery, 0) AS in_transit_delivery,
        COALESCE(d.successful_delivery, 0) AS successful_delivery,
        COALESCE(d.on_time_delivery, 0) AS on_time_delivery,
        COALESCE(d.late_delivery, 0) AS late_delivery,
        COALESCE(d.failed_delivery, 0) AS failed_delivery,
        COALESCE(d.returned_delivery, 0) AS returned_delivery,
        COALESCE(d.overdue_delivery, 0) AS overdue_delivery,
        d.on_time_rate_pct,
        d.delivery_success_rate_pct,
        d.sla_target_pct AS delivery_sla_target_pct,
        d.sla_gap_pct AS delivery_sla_gap_pct,
        d.avg_delay_hours,
        COALESCE(d.delivery_status, 'NORMAL') AS delivery_status,
        d.delivery_data_status
    FROM revenue r
    LEFT JOIN seller s
      ON r.drop_point_id = s.drop_point_id
     AND r.as_of_date = s.as_of_date
    LEFT JOIN analytics.vw_drop_point_parcel_current p
      ON r.drop_point_id = p.drop_point_id
    LEFT JOIN analytics.vw_drop_point_current_delivery_status d
      ON r.drop_point_id = d.drop_point_id
    LEFT JOIN manager m
      ON r.drop_point_id = m.drop_point_id
),
final AS (
    SELECT
        *,
        CASE
            WHEN revenue_status = 'CRITICAL'
              OR seller_status = 'CRITICAL'
              OR parcel_status = 'CRITICAL'
              OR delivery_status = 'CRITICAL' THEN 'CRITICAL'
            WHEN revenue_status = 'WATCH'
              OR seller_status = 'WATCH'
              OR parcel_status = 'WATCH'
              OR delivery_status = 'WATCH' THEN 'WATCH'
            ELSE 'NORMAL'
        END AS overall_status
    FROM combined
)
SELECT * FROM final;

-- ============================================================
-- 19. STATUS -> RESPONSIBLE UNIT / PIC / MANAGER
-- ============================================================
CREATE VIEW analytics.vw_drop_point_status_responsibility AS
WITH component AS (
    SELECT
        s.drop_point_id,
        s.drop_point_name,
        'REVENUE'::text AS component,
        s.revenue_status AS status,
        'SELLER'::text AS fallback_unit_code
    FROM analytics.vw_daily_operational_summary s
    WHERE s.revenue_status IN ('WATCH', 'CRITICAL')

    UNION ALL

    SELECT
        s.drop_point_id,
        s.drop_point_name,
        'SELLER'::text,
        s.seller_status,
        'SELLER'::text
    FROM analytics.vw_daily_operational_summary s
    WHERE s.seller_status IN ('WATCH', 'CRITICAL')

    UNION ALL

    SELECT
        s.drop_point_id,
        s.drop_point_name,
        'PARCEL'::text,
        s.parcel_status,
        'OUTBOUND'::text
    FROM analytics.vw_daily_operational_summary s
    WHERE s.parcel_status IN ('WATCH', 'CRITICAL')

    UNION ALL

    SELECT
        s.drop_point_id,
        s.drop_point_name,
        'DELIVERY'::text,
        s.delivery_status,
        'DELIVERY'::text
    FROM analytics.vw_daily_operational_summary s
    WHERE s.delivery_status IN ('WATCH', 'CRITICAL')
),
issue_rank AS (
    SELECT
        i.drop_point_id,
        i.issue_stage AS component,
        i.responsible_unit_code,
        SUM(i.issue_count) AS issue_count,
        ROW_NUMBER() OVER (
            PARTITION BY i.drop_point_id, i.issue_stage
            ORDER BY SUM(i.issue_count) DESC, i.responsible_unit_code
        ) AS rn
    FROM analytics.vw_drop_point_issue_summary i
    GROUP BY i.drop_point_id, i.issue_stage, i.responsible_unit_code
),
resolved AS (
    SELECT
        c.drop_point_id,
        c.drop_point_name,
        c.component,
        c.status,
        COALESCE(ir.responsible_unit_code, c.fallback_unit_code) AS responsible_unit_code
    FROM component c
    LEFT JOIN issue_rank ir
      ON c.drop_point_id = ir.drop_point_id
     AND c.component = ir.component
     AND ir.rn = 1
)
SELECT
    r.drop_point_id,
    r.drop_point_name,
    r.component,
    r.status,
    r.responsible_unit_code,
    u.unit_name AS responsible_unit_name,
    pic.staff_id AS responsible_staff_id,
    pic.staff_name AS responsible_staff_name,
    mgr.staff_id AS manager_staff_id,
    mgr.staff_name AS manager_name
FROM resolved r
JOIN core.dim_unit u
  ON r.responsible_unit_code = u.unit_code
LEFT JOIN LATERAL (
    SELECT s.staff_id, s.staff_name
    FROM core.dim_staff s
    WHERE s.drop_point_id = r.drop_point_id
      AND s.unit_code = r.responsible_unit_code
      AND s.role_code = 'PIC'
      AND s.status = 'ACTIVE'
    ORDER BY s.staff_id
    LIMIT 1
) pic ON TRUE
LEFT JOIN LATERAL (
    SELECT s.staff_id, s.staff_name
    FROM core.dim_staff s
    WHERE s.drop_point_id = r.drop_point_id
      AND s.unit_code = 'MANAGEMENT'
      AND s.role_code = 'MANAGER'
      AND s.status = 'ACTIVE'
    ORDER BY s.staff_id
    LIMIT 1
) mgr ON TRUE;

-- ============================================================
-- 20. DAILY REPORT
-- ============================================================
CREATE VIEW analytics.vw_daily_report AS
WITH params AS (
    SELECT current_business_date AS business_date
    FROM app.simulation_state
    WHERE simulation_name = 'operations_demo'
),
revenue AS (
    SELECT
        r.drop_point_id,
        SUM(r.revenue) AS daily_revenue,
        COUNT(*) AS daily_invoice,
        COUNT(DISTINCT r.seller_id) AS daily_active_seller
    FROM core.fact_revenue r
    CROSS JOIN params p
    WHERE r.revenue_date = p.business_date
    GROUP BY r.drop_point_id
),
delivery AS (
    SELECT
        sh.destination_dp_id AS drop_point_id,
        COUNT(*) AS daily_shipment,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'ON_TIME') AS daily_on_time,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'LATE') AS daily_late,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'FAILED') AS daily_failed,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'RETURNED') AS daily_returned,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'IN_TRANSIT') AS daily_in_transit,
        COUNT(*) FILTER (WHERE sh.delivery_class = 'IN_TRANSIT' AND sh.is_overdue) AS daily_overdue,
        COUNT(*) FILTER (WHERE sh.delivery_class IN ('ON_TIME', 'LATE', 'FAILED', 'RETURNED')) AS daily_completed,
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE sh.delivery_class = 'ON_TIME')
            / NULLIF(COUNT(*) FILTER (WHERE sh.delivery_class IN ('ON_TIME', 'LATE', 'FAILED', 'RETURNED')), 0),
            2
        ) AS daily_on_time_rate_pct
    FROM analytics.vw_shipment_detail sh
    CROSS JOIN params p
    WHERE sh.left_dp_ts::date = p.business_date
    GROUP BY sh.destination_dp_id
),
period AS (
    SELECT total_working_days
    FROM analytics.vw_current_period
)
SELECT
    p.business_date,
    s.drop_point_id,
    s.drop_point_name,
    s.manager_staff_id,
    s.manager_name,
    COALESCE(r.daily_revenue, 0::numeric) AS daily_revenue,
    COALESCE(r.daily_invoice, 0::bigint) AS daily_invoice,
    COALESCE(r.daily_active_seller, 0::bigint) AS daily_active_seller,
    ROUND(s.revenue_target / NULLIF(period.total_working_days, 0), 2) AS daily_revenue_target,
    ROUND(
        100.0 * COALESCE(r.daily_revenue, 0::numeric)
        / NULLIF(s.revenue_target / NULLIF(period.total_working_days, 0), 0),
        2
    ) AS daily_revenue_achievement_pct,
    pc.parcel_in_today AS daily_parcel_in,
    pc.parcel_out_today AS daily_parcel_out,
    pc.parcel_at_dp,
    pc.parcel_over_24h,
    pc.oldest_parcel_hours,
    pc.avg_dp_hours,
    pc.parcel_out_pct,
    pc.parcel_status,
    COALESCE(d.daily_shipment, 0::bigint) AS daily_shipment,
    COALESCE(d.daily_completed, 0::bigint) AS daily_completed,
    COALESCE(d.daily_in_transit, 0::bigint) AS daily_in_transit,
    COALESCE(d.daily_on_time, 0::bigint) AS daily_on_time,
    COALESCE(d.daily_late, 0::bigint) AS daily_late,
    COALESCE(d.daily_failed, 0::bigint) AS daily_failed,
    COALESCE(d.daily_returned, 0::bigint) AS daily_returned,
    COALESCE(d.daily_overdue, 0::bigint) AS daily_overdue,
    d.daily_on_time_rate_pct,
    s.revenue AS mtd_revenue,
    s.revenue_target AS monthly_revenue_target,
    s.revenue_achievement_pct AS mtd_revenue_achievement_pct,
    s.expected_achievement_pct,
    s.revenue_gap_pct,
    s.on_time_rate_pct AS mtd_on_time_rate_pct,
    s.completed_delivery AS mtd_completed_delivery,
    s.in_transit_delivery AS mtd_in_transit_delivery,
    s.late_delivery AS mtd_late_delivery,
    s.failed_delivery AS mtd_failed_delivery,
    s.returned_delivery AS mtd_returned_delivery,
    s.overdue_delivery AS mtd_overdue_delivery,
    s.delivery_sla_target_pct,
    s.delivery_status,
    s.normal_seller,
    s.watch_seller,
    s.critical_seller,
    s.seller_status,
    s.overall_status
FROM analytics.vw_daily_operational_summary s
CROSS JOIN params p
CROSS JOIN period
LEFT JOIN revenue r ON s.drop_point_id = r.drop_point_id
LEFT JOIN delivery d ON s.drop_point_id = d.drop_point_id
LEFT JOIN analytics.vw_drop_point_parcel_current pc ON s.drop_point_id = pc.drop_point_id;

-- ============================================================
-- 21. FINAL DOMAIN GUARDS
-- ============================================================
DO $$
BEGIN
    IF to_regclass('core.dim_outlet') IS NOT NULL
       OR to_regclass('core.dim_pic') IS NOT NULL
       OR to_regclass('core.fact_pic_target') IS NOT NULL
    THEN
        RAISE EXCEPTION 'Legacy outlet/PIC target domain objects still exist.';
    END IF;

    IF to_regclass('core.dim_seller') IS NULL
       OR to_regclass('core.dim_staff') IS NULL
       OR to_regclass('core.dim_unit') IS NULL
       OR to_regclass('core.dim_courier') IS NULL
       OR to_regclass('core.fact_seller_target') IS NULL
    THEN
        RAISE EXCEPTION 'Final logistics domain objects were not created.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM core.dim_seller s
        JOIN core.dim_staff st ON s.seller_pic_id = st.staff_id
        WHERE st.unit_code <> 'SELLER'
    ) THEN
        RAISE EXCEPTION 'One or more sellers are assigned to staff outside SELLER unit.';
    END IF;
END $$;

COMMIT;
