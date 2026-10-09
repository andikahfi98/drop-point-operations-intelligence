CREATE OR REPLACE VIEW analytics.vw_data_freshness AS

WITH simulation AS (
    SELECT
        current_business_date,
        current_business_time,
        current_business_date
            + current_business_time AS simulation_ts

    FROM app.simulation_state
    WHERE simulation_name = 'operations_demo'
),

freshness AS (
    SELECT

        -- SALES
        (
            SELECT MAX(f.sales_date)
            FROM core.fact_sales f
            CROSS JOIN simulation s
            WHERE f.transaction_ts <= s.simulation_ts
        ) AS latest_sales_date,

        (
            SELECT MAX(
                COALESCE(
                    d.shipment_ts::date,
                    d.order_date
                )
            )
            FROM core.fact_delivery d
            CROSS JOIN simulation s
            WHERE d.shipment_ts IS NULL
               OR d.shipment_ts <= s.simulation_ts
        ) AS latest_delivery_date,

        (
            SELECT MAX(i.snapshot_date)
            FROM core.fact_inventory i
            CROSS JOIN simulation s
            WHERE i.snapshot_date <= s.current_business_date
        ) AS latest_inventory_date,

        -- TIMESTAMP DETAIL
        (
            SELECT MAX(f.transaction_ts)
            FROM core.fact_sales f
            CROSS JOIN simulation s
            WHERE f.transaction_ts <= s.simulation_ts
        ) AS latest_sales_ts,

        (
            SELECT MAX(d.shipment_ts)
            FROM core.fact_delivery d
            CROSS JOIN simulation s
            WHERE d.shipment_ts <= s.simulation_ts
        ) AS latest_shipment_ts,

        (
            SELECT MAX(d.actual_delivery_ts)
            FROM core.fact_delivery d
            CROSS JOIN simulation s
            WHERE d.actual_delivery_ts <= s.simulation_ts
        ) AS latest_actual_delivery_ts
)

SELECT
    -- Existing column order
    f.latest_sales_date,
    f.latest_delivery_date,
    f.latest_inventory_date,

    f.latest_sales_ts,
    f.latest_shipment_ts,
    f.latest_actual_delivery_ts,

    s.simulation_ts,

    CASE
        WHEN f.latest_sales_ts IS NULL
            THEN NULL
        ELSE ROUND(
            EXTRACT(
                EPOCH FROM (
                    s.simulation_ts - f.latest_sales_ts
                )
            ) / 60.0,
            2
        )
    END AS sales_freshness_minutes,

    CASE
        WHEN f.latest_shipment_ts IS NULL
            THEN NULL
        ELSE ROUND(
            EXTRACT(
                EPOCH FROM (
                    s.simulation_ts - f.latest_shipment_ts
                )
            ) / 60.0,
            2
        )
    END AS delivery_freshness_minutes,

    CASE
        WHEN f.latest_inventory_date IS NULL
            THEN NULL
        ELSE
            s.current_business_date
            - f.latest_inventory_date
    END AS inventory_age_days

FROM freshness f
CROSS JOIN simulation s;