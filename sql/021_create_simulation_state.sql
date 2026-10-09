-- =========================================================
-- 021_create_simulation_state.sql
-- Synthetic Operational Data Simulation
-- =========================================================


CREATE TABLE IF NOT EXISTS app.simulation_state (

    simulation_name VARCHAR(50) PRIMARY KEY,

    current_business_date DATE NOT NULL,

    batch_no INTEGER NOT NULL DEFAULT 0,

    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,

    last_run_at TIMESTAMPTZ
);


CREATE TABLE IF NOT EXISTS app.simulation_run_log (

    run_id BIGSERIAL PRIMARY KEY,

    simulation_name VARCHAR(50) NOT NULL
        REFERENCES app.simulation_state(simulation_name),

    business_date DATE NOT NULL,

    batch_no INTEGER NOT NULL,

    sales_rows INTEGER NOT NULL DEFAULT 0,

    delivery_rows INTEGER NOT NULL DEFAULT 0,

    inventory_rows INTEGER NOT NULL DEFAULT 0,

    target_rows INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (
        simulation_name,
        batch_no
    )
);


-- Initial position = latest existing sales date

INSERT INTO app.simulation_state (
    simulation_name,
    current_business_date,
    batch_no,
    is_enabled
)

SELECT
    'operations_demo',
    MAX(sales_date),
    0,
    TRUE

FROM core.fact_sales

ON CONFLICT (simulation_name)
DO NOTHING;