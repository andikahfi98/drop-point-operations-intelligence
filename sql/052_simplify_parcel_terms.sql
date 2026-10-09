-- ============================================================
-- 052 - Simplify parcel terminology
--
-- Only rename the terms requested:
--   on hand  -> at DP
--   dwell    -> DP hours
--   dispatch -> left DP / parcel out
--
-- No KPI logic or thresholds are changed.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Physical shipment tables
-- ------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'core'
          AND table_name = 'fact_shipment'
          AND column_name = 'dispatched_ts'
    ) THEN
        ALTER TABLE core.fact_shipment
            RENAME COLUMN dispatched_ts TO left_dp_ts;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'raw'
          AND table_name = 'fact_shipment'
          AND column_name = 'dispatched_ts'
    ) THEN
        ALTER TABLE raw.fact_shipment
            RENAME COLUMN dispatched_ts TO left_dp_ts;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'app'
          AND table_name = 'simulation_run_log'
          AND column_name = 'dispatched_rows'
    ) THEN
        ALTER TABLE app.simulation_run_log
            RENAME COLUMN dispatched_rows TO left_dp_rows;
    END IF;
END $$;

-- Keep index / constraint names readable too.
DO $$
BEGIN
    IF to_regclass('core.idx_fact_shipment_dispatched_ts') IS NOT NULL THEN
        ALTER INDEX core.idx_fact_shipment_dispatched_ts
            RENAME TO idx_fact_shipment_left_dp_ts;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'core'
          AND t.relname = 'fact_shipment'
          AND c.conname = 'chk_shipment_dispatched_order'
    ) THEN
        ALTER TABLE core.fact_shipment
            RENAME CONSTRAINT chk_shipment_dispatched_order
            TO chk_shipment_left_dp_order;
    END IF;
END $$;

-- ------------------------------------------------------------
-- 2. Analytics view output names
--
-- PostgreSQL keeps dependencies by object/column identity, so the
-- existing logic remains intact; we only rename exposed columns.
-- ------------------------------------------------------------
DO $$
DECLARE
    m RECORD;
    v RECORD;
BEGIN
    FOR m IN
        SELECT *
        FROM (
            VALUES
                ('dispatched_ts',        'left_dp_ts'),
                ('latest_dispatched_ts', 'latest_left_dp_ts'),
                ('is_on_hand',           'is_at_dp'),
                ('dwell_hours',          'dp_hours'),
                ('parcel_on_hand',       'parcel_at_dp'),
                ('avg_dwell_hours',      'avg_dp_hours'),
                ('dispatch_rate_pct',    'parcel_out_pct')
        ) AS x(old_name, new_name)
    LOOP
        FOR v IN
            SELECT c.table_schema, c.table_name
            FROM information_schema.columns c
            JOIN information_schema.views vw
              ON vw.table_schema = c.table_schema
             AND vw.table_name = c.table_name
            WHERE c.table_schema = 'analytics'
              AND c.column_name = m.old_name
            ORDER BY c.table_name
        LOOP
            EXECUTE format(
                'ALTER VIEW %I.%I RENAME COLUMN %I TO %I',
                v.table_schema,
                v.table_name,
                m.old_name,
                m.new_name
            );
        END LOOP;
    END LOOP;
END $$;

COMMIT;
