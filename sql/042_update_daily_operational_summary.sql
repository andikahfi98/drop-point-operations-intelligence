CREATE OR REPLACE VIEW analytics.vw_daily_operational_summary AS

WITH sales AS (
    SELECT
        s.*,

        CASE
            WHEN s.performance_status = 'CRITICAL'
                THEN 'CRITICAL'

            WHEN s.performance_status IN ('WARNING', 'WATCH')
                THEN 'WATCH'

            ELSE 'NORMAL'
        END AS sales_status_new

    FROM analytics.vw_drop_point_current_performance s
),

outlet AS (
    SELECT
        o.*,

        ROUND(
            100.0
            * o.critical_outlet
            / NULLIF(o.total_monitored_outlet, 0),
            2
        ) AS critical_outlet_pct,

        ROUND(
            100.0
            * (o.critical_outlet + o.watch_outlet)
            / NULLIF(o.total_monitored_outlet, 0),
            2
        ) AS attention_outlet_pct

    FROM analytics.vw_drop_point_outlet_attention_summary o
),

combined AS (
    SELECT
        s.as_of_date,
        s.month_start,

        s.drop_point_id,
        s.drop_point_name,
        s.region,
        s.area,

        -- =====================================================
        -- SALES
        -- =====================================================

        s.net_sales,
        s.sales_target,
        s.sales_achievement_pct,
        s.expected_achievement_pct,

        ROUND(
            s.sales_achievement_pct
            - s.expected_achievement_pct,
            2
        ) AS sales_pace_gap_pp,

        s.sales_status_new AS sales_status,

        s.active_outlet,
        s.active_outlet_target,
        s.active_outlet_achievement_pct,

        -- =====================================================
        -- OUTLET
        -- =====================================================

        COALESCE(o.critical_outlet, 0)
            AS critical_outlet,

        -- legacy column name kept for compatibility
        COALESCE(o.watch_outlet, 0)
            AS warning_outlet,

        COALESCE(o.inactive_14d_outlet, 0)
            AS inactive_14d_outlet,

        COALESCE(o.normal_outlet, 0)
            AS normal_outlet,

        COALESCE(o.watch_outlet, 0)
            AS watch_outlet,

        COALESCE(o.total_monitored_outlet, 0)
            AS total_monitored_outlet,

        COALESCE(o.critical_outlet_pct, 0)
            AS critical_outlet_pct,

        COALESCE(o.attention_outlet_pct, 0)
            AS attention_outlet_pct,

        CASE
            WHEN COALESCE(o.critical_outlet_pct, 0) > 20
                THEN 'CRITICAL'

            WHEN COALESCE(o.attention_outlet_pct, 0) >= 10
                THEN 'WATCH'

            ELSE 'NORMAL'
        END AS outlet_status,

        -- =====================================================
        -- DELIVERY
        -- =====================================================

        COALESCE(d.total_shipment, 0)
            AS total_shipment,

        COALESCE(d.on_time_delivery, 0)
            AS on_time_delivery,

        COALESCE(d.late_delivery, 0)
            AS late_delivery,

        COALESCE(d.failed_delivery, 0)
            AS failed_delivery,

        COALESCE(d.overdue_delivery, 0)
            AS overdue_delivery,

        d.on_time_rate_pct,

        d.sla_target_pct
            AS delivery_sla_target_pct,

        CASE
            WHEN d.on_time_rate_pct IS NULL
                THEN NULL

            ELSE ROUND(
                d.on_time_rate_pct
                - d.sla_target_pct,
                2
            )
        END AS delivery_sla_gap_pp,

        d.avg_delay_hours,

        d.completed_delivery,
        d.in_transit_delivery,
        d.successful_delivery,
        d.delivery_success_rate_pct,

        d.sla_performance_status
            AS delivery_status,

        d.delivery_data_status

    FROM sales s

    LEFT JOIN analytics.vw_drop_point_current_delivery_status d
        ON s.drop_point_id = d.drop_point_id

    LEFT JOIN outlet o
        ON s.drop_point_id = o.drop_point_id
       AND s.as_of_date = o.as_of_date
),

final AS (
    SELECT
        *,

        CASE
            WHEN sales_status = 'CRITICAL'
              OR outlet_status = 'CRITICAL'
              OR delivery_status = 'CRITICAL'
                THEN 'CRITICAL'

            WHEN sales_status = 'WATCH'
              OR outlet_status = 'WATCH'
              OR delivery_status = 'WATCH'
                THEN 'WATCH'

            ELSE 'NORMAL'
        END AS overall_status_new

    FROM combined
)

SELECT
    -- =====================================================
    -- EXISTING COLUMNS
    -- Preserve order for downstream dependencies
    -- =====================================================

    as_of_date,
    month_start,

    drop_point_id,
    drop_point_name,
    region,
    area,

    net_sales,
    sales_target,
    sales_achievement_pct,
    expected_achievement_pct,
    sales_pace_gap_pp,
    sales_status,

    active_outlet,
    active_outlet_target,
    active_outlet_achievement_pct,

    critical_outlet,
    warning_outlet,
    inactive_14d_outlet,

    total_shipment,
    on_time_delivery,
    late_delivery,
    failed_delivery,
    overdue_delivery,

    on_time_rate_pct,
    delivery_sla_target_pct,
    delivery_sla_gap_pp,
    avg_delay_hours,

    overall_status_new AS overall_status,

    -- =====================================================
    -- NEW COLUMNS
    -- Append only
    -- =====================================================

    normal_outlet,
    watch_outlet,
    total_monitored_outlet,
    critical_outlet_pct,
    attention_outlet_pct,
    outlet_status,

    completed_delivery,
    in_transit_delivery,
    successful_delivery,
    delivery_success_rate_pct,
    delivery_status,
    delivery_data_status

FROM final;