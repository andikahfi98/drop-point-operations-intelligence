CREATE OR REPLACE VIEW analytics.vw_drop_point_current_delivery_status AS

SELECT
    d.*,

    -- =====================================================
    -- SLA SHORTFALL
    -- Positive number = how far actual is below target.
    -- =====================================================

    CASE
        WHEN d.on_time_rate_pct IS NULL
            THEN NULL

        ELSE GREATEST(
            d.sla_target_pct - d.on_time_rate_pct,
            0
        )
    END AS sla_shortfall_pct,


    -- =====================================================
    -- SLA PERFORMANCE STATUS
    --
    -- Minimum 20 completed deliveries before judging SLA.
    -- This prevents 1/1 delivery = 100% being treated
    -- as a stable operational performance.
    -- =====================================================

    CASE
        WHEN d.completed_delivery = 0
            THEN 'NO_DATA'

        WHEN d.completed_delivery < 20
            THEN 'INSUFFICIENT_DATA'

        WHEN d.on_time_rate_pct >= d.sla_target_pct
            THEN 'NORMAL'

        WHEN d.on_time_rate_pct >= d.sla_target_pct - 5
            THEN 'WARNING'

        ELSE 'CRITICAL'
    END AS sla_performance_status

FROM analytics.vw_drop_point_current_delivery d;