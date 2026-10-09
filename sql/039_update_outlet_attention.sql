CREATE OR REPLACE VIEW analytics.vw_outlet_attention AS

WITH base AS (
    SELECT
        a.as_of_date,
        a.drop_point_id,
        a.drop_point_name,

        -- Keep old source names for compatibility
        a.salesperson_id,
        a.salesperson_name,

        a.outlet_id,
        a.bp_code,
        a.outlet_name,

        a.last_transaction_date,
        a.days_since_last_transaction,
        a.current_month_transaction,
        a.current_month_sales,
        a.activity_status,

        COALESCE(d.total_delivery, 0)
            AS total_delivery,

        COALESCE(d.late_delivery, 0)
            AS late_delivery,

        COALESCE(d.failed_delivery, 0)
            AS failed_delivery,

        COALESCE(d.overdue_delivery, 0)
            AS overdue_delivery,

        COALESCE(d.completed_delivery, 0)
            AS completed_delivery,

        COALESCE(d.in_transit_delivery, 0)
            AS in_transit_delivery,

        COALESCE(d.total_issue, 0)
            AS total_issue,

        GREATEST(
            COALESCE(d.completed_delivery, 0)
            - COALESCE(d.late_delivery, 0)
            - COALESCE(d.failed_delivery, 0),
            0
        ) AS on_time_delivery,

        dp.sla_target_pct

    FROM analytics.vw_outlet_activity a

    LEFT JOIN analytics.vw_outlet_current_delivery_issues d
        ON a.outlet_id = d.outlet_id

    LEFT JOIN analytics.vw_drop_point_current_delivery dp
        ON a.drop_point_id = dp.drop_point_id

    WHERE a.active_flag = TRUE
),

metrics AS (
    SELECT
        *,

        CASE
            WHEN completed_delivery = 0
                THEN NULL
            ELSE ROUND(
                100.0
                * on_time_delivery
                / completed_delivery,
                2
            )
        END AS outlet_on_time_rate_pct

    FROM base
),

status_calc AS (
    SELECT
        *,

        -- Backend information only
        CASE
            WHEN completed_delivery = 0
                THEN 'NO_DATA'

            WHEN completed_delivery < 20
                THEN 'INSUFFICIENT_DATA'

            ELSE 'SUFFICIENT_DATA'
        END AS delivery_data_status,

        -- Operational status:
        -- only NORMAL / WATCH / CRITICAL
        CASE
            -- Small sample is not escalated operationally
            WHEN completed_delivery < 20
                THEN 'NORMAL'

            -- SLA shortfall < 10%
            WHEN outlet_on_time_rate_pct
                 > sla_target_pct - 10
                THEN 'NORMAL'

            -- SLA shortfall 10% - 20%
            WHEN outlet_on_time_rate_pct
                 >= sla_target_pct - 20
                THEN 'WATCH'

            -- SLA shortfall > 20%
            ELSE 'CRITICAL'
        END AS delivery_performance_status

    FROM metrics
)

SELECT
    -- =====================================================
    -- EXISTING COLUMNS
    -- Keep exact order for downstream dependencies
    -- =====================================================

    as_of_date,
    drop_point_id,
    drop_point_name,

    salesperson_id,
    salesperson_name,

    outlet_id,
    bp_code,
    outlet_name,

    last_transaction_date,
    days_since_last_transaction,
    current_month_transaction,
    current_month_sales,
    activity_status,

    total_delivery,
    late_delivery,
    failed_delivery,
    overdue_delivery,

    CASE
        WHEN activity_status IN (
            'NO_SALES_HISTORY',
            'INACTIVE_14D'
        )
            THEN 'CRITICAL'

        WHEN delivery_performance_status = 'CRITICAL'
            THEN 'CRITICAL'

        WHEN activity_status = 'WATCH_7D'
            THEN 'WATCH'

        WHEN delivery_performance_status = 'WATCH'
            THEN 'WATCH'

        ELSE 'NORMAL'
    END AS attention_status,

    completed_delivery,
    in_transit_delivery,
    on_time_delivery,

    outlet_on_time_rate_pct,
    sla_target_pct,

    -- Existing column: Actual - Target
    CASE
        WHEN outlet_on_time_rate_pct IS NULL
            THEN NULL
        ELSE ROUND(
            outlet_on_time_rate_pct - sla_target_pct,
            2
        )
    END AS delivery_sla_gap_pct,

    delivery_performance_status,

    total_issue,

    -- Reporting terminology
    salesperson_id AS pic_id,
    salesperson_name AS pic_name,

    -- =====================================================
    -- NEW BACKEND FIELDS - append only
    -- =====================================================

    CASE
        WHEN outlet_on_time_rate_pct IS NULL
            THEN NULL
        ELSE GREATEST(
            ROUND(
                sla_target_pct - outlet_on_time_rate_pct,
                2
            ),
            0
        )
    END AS sla_shortfall_pct,

    delivery_data_status

FROM status_calc;