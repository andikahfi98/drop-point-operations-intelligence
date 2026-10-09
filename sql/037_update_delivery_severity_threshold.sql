CREATE OR REPLACE VIEW analytics.vw_drop_point_current_delivery_status AS

SELECT
    d.*,

    CASE
        WHEN d.on_time_rate_pct IS NULL
            THEN NULL

        ELSE GREATEST(
            d.sla_target_pct - d.on_time_rate_pct,
            0
        )
    END AS sla_shortfall_pct,

    CASE
        -- Belum ada delivery selesai
        WHEN d.completed_delivery = 0
            THEN 'NO_DATA'

        -- Sampel masih terlalu kecil
        WHEN d.completed_delivery < 20
            THEN 'INSUFFICIENT_DATA'

        -- SLA tercapai
        WHEN d.on_time_rate_pct >= d.sla_target_pct
            THEN 'NORMAL'

        -- Selisih SLA < 10%
        WHEN d.on_time_rate_pct > d.sla_target_pct - 10
            THEN 'WATCH'

        -- Selisih SLA 10% s.d. 20%
        WHEN d.on_time_rate_pct >= d.sla_target_pct - 20
            THEN 'WARNING'

        -- Selisih SLA > 20%
        ELSE 'CRITICAL'
    END AS sla_performance_status

FROM analytics.vw_drop_point_current_delivery d;