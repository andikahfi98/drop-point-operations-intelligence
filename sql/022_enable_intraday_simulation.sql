-- =========================================================
-- 022_enable_intraday_simulation.sql
-- Intraday 5-minute simulation support
-- =========================================================


-- =========================================================
-- 1. SALES TRANSACTION TIMESTAMP
-- Existing model only had sales_date
-- =========================================================

ALTER TABLE core.fact_sales
ADD COLUMN IF NOT EXISTS transaction_ts TIMESTAMP;

UPDATE core.fact_sales
SET transaction_ts =
    sales_date::TIMESTAMP + INTERVAL '12 hours'
WHERE transaction_ts IS NULL;

CREATE INDEX IF NOT EXISTS
idx_fact_sales_transaction_ts
ON core.fact_sales (transaction_ts);


ALTER TABLE raw.fact_sales
ADD COLUMN IF NOT EXISTS transaction_ts TEXT;

UPDATE raw.fact_sales
SET transaction_ts =
    TRIM(date) || ' 12:00:00'
WHERE
    transaction_ts IS NULL
    OR TRIM(transaction_ts) = '';


-- =========================================================
-- 2. SIMULATION STATE
-- =========================================================

ALTER TABLE app.simulation_state
ADD COLUMN IF NOT EXISTS current_business_time TIME;

ALTER TABLE app.simulation_state
ADD COLUMN IF NOT EXISTS interval_no INTEGER;

ALTER TABLE app.simulation_state
ADD COLUMN IF NOT EXISTS simulation_mode VARCHAR(20);


-- =========================================================
-- Move simulation to the NEXT available working day.
-- Existing daily-generated data stays untouched.
--
-- 07:55 means first intraday run becomes 08:00.
-- =========================================================

WITH last_sales AS (

    SELECT MAX(sales_date) AS last_sales_date
    FROM core.fact_sales

),

next_working_day AS (

    SELECT MIN(d.date) AS next_date

    FROM core.dim_date d
    CROSS JOIN last_sales l

    WHERE
        d.date > l.last_sales_date
        AND d.is_working_day = TRUE
)

UPDATE app.simulation_state

SET
    current_business_date =
        COALESCE(
            (
                SELECT next_date
                FROM next_working_day
            ),
            current_business_date
        ),

    current_business_time = TIME '07:55:00',

    interval_no = 0,

    simulation_mode = 'INTRADAY'

WHERE
    simulation_name = 'operations_demo'

    AND current_business_time IS NULL;


UPDATE app.simulation_state
SET
    current_business_time =
        COALESCE(
            current_business_time,
            TIME '07:55:00'
        ),

    interval_no =
        COALESCE(interval_no, 0),

    simulation_mode =
        COALESCE(
            simulation_mode,
            'INTRADAY'
        );


ALTER TABLE app.simulation_state
ALTER COLUMN current_business_time
SET DEFAULT TIME '07:55:00';

ALTER TABLE app.simulation_state
ALTER COLUMN current_business_time
SET NOT NULL;


ALTER TABLE app.simulation_state
ALTER COLUMN interval_no
SET DEFAULT 0;

ALTER TABLE app.simulation_state
ALTER COLUMN interval_no
SET NOT NULL;


ALTER TABLE app.simulation_state
ALTER COLUMN simulation_mode
SET DEFAULT 'INTRADAY';

ALTER TABLE app.simulation_state
ALTER COLUMN simulation_mode
SET NOT NULL;


-- =========================================================
-- 3. SIMULATION RUN LOG
-- Previous daily logs remain valid
-- =========================================================

ALTER TABLE app.simulation_run_log
ADD COLUMN IF NOT EXISTS business_time TIME;

ALTER TABLE app.simulation_run_log
ADD COLUMN IF NOT EXISTS simulation_ts TIMESTAMP;

ALTER TABLE app.simulation_run_log
ADD COLUMN IF NOT EXISTS interval_no INTEGER;