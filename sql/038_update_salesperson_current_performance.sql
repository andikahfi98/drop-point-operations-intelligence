-- ============================================================
-- 038 - PIC CURRENT PERFORMANCE
--
-- Purpose:
-- - Replace "salesperson" terminology at reporting layer
--   with "PIC".
-- - PIC performance is SALES / OUTLET responsibility only.
-- - Delivery performance belongs to Drop Point / Logistics.
--
-- Note:
-- Source view still uses salesperson_id / salesperson_name
-- internally for backward compatibility.
-- ============================================================


CREATE OR REPLACE VIEW analytics.vw_pic_current_performance AS

WITH period AS (
    SELECT
        as_of_date,
        month_start,
        expected_achievement_pct
    FROM analytics.vw_current_period
),

pic_base AS (
    SELECT
        p.as_of_date,
        s.month_start,

        s.drop_point_id,
        s.drop_point_name,

        -- Reporting terminology
        s.salesperson_id AS pic_id,
        s.salesperson_name AS pic_name,

        -- =====================================================
        -- SALES
        -- =====================================================

        s.net_sales,
        s.sales_target,
        s.sales_achievement_pct,

        p.expected_achievement_pct,

        ROUND(
            s.sales_achievement_pct
            - p.expected_achievement_pct,
            2
        ) AS sales_gap_pct,

        -- =====================================================
        -- OUTLET COVERAGE
        -- =====================================================

        s.active_outlet,
        s.active_outlet_target,
        s.active_outlet_achievement_pct

    FROM analytics.vw_salesperson_monthly_performance s

    CROSS JOIN period p

    WHERE s.month_start = p.month_start
)

SELECT
    as_of_date,
    month_start,

    drop_point_id,
    drop_point_name,

    pic_id,
    pic_name,

    net_sales,
    sales_target,
    sales_achievement_pct,

    expected_achievement_pct,
    sales_gap_pct,

    active_outlet,
    active_outlet_target,
    active_outlet_achievement_pct,

    -- =====================================================
    -- PIC STATUS
    --
    -- Based on sales pace only for now.
    --
    -- NORMAL   : actual >= expected
    -- WATCH    : gap < 0% and > -10%
    -- WARNING  : gap -10% to -20%
    -- CRITICAL : gap below -20%
    -- =====================================================

    CASE
        WHEN sales_target IS NULL
             OR sales_target <= 0
            THEN 'NO_DATA'

        WHEN sales_gap_pct <= -20
            THEN 'CRITICAL'

        WHEN sales_gap_pct <= -10
            THEN 'WARNING'

        WHEN sales_gap_pct < 0
            THEN 'WATCH'

        ELSE 'NORMAL'
    END AS pic_status

FROM pic_base;