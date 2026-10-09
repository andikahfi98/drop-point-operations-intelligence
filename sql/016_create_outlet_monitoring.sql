-- =========================================================
-- Drop Point Operations Intelligence
-- 016_create_outlet_monitoring.sql
-- OUTLET ACTIVITY & ATTENTION MONITORING
-- =========================================================


-- =========================================================
-- 1. OUTLET ACTIVITY
-- Grain:
-- 1 row = 1 Outlet
-- =========================================================

CREATE OR REPLACE VIEW analytics.vw_outlet_activity AS

WITH params AS (

    SELECT
        latest_sales_date AS as_of_date,
        DATE_TRUNC(
            'month',
            latest_sales_date
        )::DATE AS month_start

    FROM analytics.vw_data_freshness
),

sales_activity AS (

    SELECT
        outlet_id,

        MAX(sales_date) AS last_transaction_date,

        COUNT(DISTINCT invoice_id)
            FILTER (
                WHERE sales_date >= (
                    SELECT month_start
                    FROM params
                )
            ) AS current_month_transaction,

        SUM(net_sales)
            FILTER (
                WHERE sales_date >= (
                    SELECT month_start
                    FROM params
                )
            ) AS current_month_sales

    FROM core.fact_sales

    GROUP BY outlet_id
)

SELECT
    p.as_of_date,

    o.drop_point_id,
    dp.drop_point_name,

    o.salesperson_id,
    sp.salesperson_name,

    o.outlet_id,
    o.bp_code,
    o.outlet_name,
    o.segment,
    o.route_code,
    o.active_flag,

    s.last_transaction_date,

    CASE
        WHEN s.last_transaction_date IS NULL
            THEN NULL

        ELSE
            p.as_of_date - s.last_transaction_date
    END AS days_since_last_transaction,

    COALESCE(
        s.current_month_transaction,
        0
    ) AS current_month_transaction,

    COALESCE(
        s.current_month_sales,
        0
    ) AS current_month_sales,

    CASE
        WHEN o.active_flag = FALSE
            THEN 'INACTIVE_MASTER'

        WHEN s.last_transaction_date IS NULL
            THEN 'NO_SALES_HISTORY'

        WHEN
            p.as_of_date
            - s.last_transaction_date >= 14
            THEN 'INACTIVE_14D'

        WHEN
            p.as_of_date
            - s.last_transaction_date >= 7
            THEN 'WATCH_7D'

        ELSE 'ACTIVE'

    END AS activity_status

FROM core.dim_outlet o

JOIN core.dim_drop_point dp
    ON o.drop_point_id = dp.drop_point_id

JOIN core.dim_salesperson sp
    ON o.salesperson_id = sp.salesperson_id

LEFT JOIN sales_activity s
    ON o.outlet_id = s.outlet_id

CROSS JOIN params p;

-- =========================================================
-- 2. CURRENT MONTH OUTLET DELIVERY ISSUES
-- =========================================================

CREATE OR REPLACE VIEW
analytics.vw_outlet_current_delivery_issues AS

WITH params AS (

    SELECT
        latest_sales_date AS as_of_date,
        DATE_TRUNC(
            'month',
            latest_sales_date
        )::DATE AS month_start

    FROM analytics.vw_data_freshness
)

SELECT
    d.outlet_id,

    COUNT(*) AS total_delivery,

    COUNT(*) FILTER (
        WHERE d.delivery_class = 'LATE'
    ) AS late_delivery,

    COUNT(*) FILTER (
        WHERE d.delivery_class = 'FAILED'
    ) AS failed_delivery,

    COUNT(*) FILTER (
        WHERE d.delivery_class = 'OVERDUE'
    ) AS overdue_delivery

FROM analytics.vw_delivery_detail d

CROSS JOIN params p

WHERE
    d.order_date >= p.month_start
    AND d.order_date <= p.as_of_date

GROUP BY
    d.outlet_id;

-- =========================================================
-- 3. OUTLET ATTENTION MONITORING
-- =========================================================

CREATE OR REPLACE VIEW analytics.vw_outlet_attention AS

SELECT
    a.as_of_date,

    a.drop_point_id,
    a.drop_point_name,

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

    CASE

        WHEN a.activity_status IN (
            'NO_SALES_HISTORY',
            'INACTIVE_14D'
        )
        THEN 'CRITICAL'

        WHEN COALESCE(d.failed_delivery, 0) >= 2
        THEN 'CRITICAL'

        WHEN COALESCE(d.overdue_delivery, 0) >= 1
        THEN 'CRITICAL'

        WHEN a.activity_status = 'WATCH_7D'
        THEN 'WARNING'

        WHEN COALESCE(d.late_delivery, 0) >= 2
        THEN 'WARNING'

        WHEN COALESCE(d.failed_delivery, 0) = 1
        THEN 'WARNING'

        ELSE 'NORMAL'

    END AS attention_status

FROM analytics.vw_outlet_activity a

LEFT JOIN analytics.vw_outlet_current_delivery_issues d
    ON a.outlet_id = d.outlet_id

WHERE
    a.active_flag = TRUE;

