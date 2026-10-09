CREATE OR REPLACE VIEW analytics.vw_drop_point_current_delivery_status AS

SELECT
    -- Existing columns from current delivery
    d.*,

    -- Existing column: how far actual is below SLA
    CASE
        WHEN d.on_time_rate_pct IS NULL
            THEN NULL

        ELSE GREATEST(
            d.sla_target_pct - d.on_time_rate_pct,
            0
        )
    END AS sla_shortfall_pct,

    -- =====================================================
    -- OPERATIONAL STATUS
    -- Only NORMAL / WATCH / CRITICAL
    -- =====================================================
    CASE
        -- Small/no sample is not escalated operationally
        WHEN d.completed_delivery < 20
            THEN 'NORMAL'

        -- SLA shortfall < 10%
        WHEN d.on_time_rate_pct
             > d.sla_target_pct - 10
            THEN 'NORMAL'

        -- SLA shortfall 10% - 20%
        WHEN d.on_time_rate_pct
             >= d.sla_target_pct - 20
            THEN 'WATCH'

        -- SLA shortfall > 20%
        ELSE 'CRITICAL'
    END AS sla_performance_status,

    -- =====================================================
    -- DATA QUALITY / SAMPLE STATUS
    -- Backend only, not shown as operational status
    -- =====================================================
    CASE
        WHEN d.completed_delivery = 0
            THEN 'NO_DATA'

        WHEN d.completed_delivery < 20
            THEN 'INSUFFICIENT_DATA'

        ELSE 'SUFFICIENT_DATA'
    END AS delivery_data_status

FROM analytics.vw_drop_point_current_delivery d;