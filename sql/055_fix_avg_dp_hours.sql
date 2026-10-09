-- ============================================================
-- 055 - Fix avg_dp_hours semantic
--
-- avg_dp_hours now means:
--   average current age (hours) of parcels still at the Drop Point.
--
-- This aligns the metric with:
--   parcel_at_dp
--   parcel aging buckets
--   oldest_parcel_hours
--   parcel_status
--
-- Historical time-to-leave-DP for already departed parcels is not
-- exposed by this current-state view.
-- ============================================================

BEGIN;

CREATE OR REPLACE VIEW analytics.vw_drop_point_parcel_current AS
WITH period AS (
    SELECT as_of_date, month_start
    FROM analytics.vw_current_period
),
stats AS (
    SELECT
        dp.drop_point_id,
        dp.drop_point_name,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.received_ts::date BETWEEN p.month_start AND p.as_of_date
        ) AS parcel_in_mtd,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.left_dp_ts::date BETWEEN p.month_start AND p.as_of_date
        ) AS parcel_out_mtd,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.received_ts::date = p.as_of_date
        ) AS parcel_in_today,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.left_dp_ts::date = p.as_of_date
        ) AS parcel_out_today,
        COUNT(sh.shipment_id) FILTER (WHERE sh.is_at_dp) AS parcel_at_dp,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.is_at_dp
              AND sh.parcel_age_hours < 6
        ) AS parcel_under_6h,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.is_at_dp
              AND sh.parcel_age_hours >= 6
              AND sh.parcel_age_hours < 12
        ) AS parcel_6_12h,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.is_at_dp
              AND sh.parcel_age_hours >= 12
              AND sh.parcel_age_hours < 24
        ) AS parcel_12_24h,
        COUNT(sh.shipment_id) FILTER (
            WHERE sh.is_at_dp
              AND sh.parcel_age_hours >= 24
        ) AS parcel_over_24h,
        MAX(sh.parcel_age_hours) FILTER (WHERE sh.is_at_dp)
            AS oldest_parcel_hours,
        ROUND(
            AVG(sh.parcel_age_hours) FILTER (WHERE sh.is_at_dp),
            2
        ) AS avg_dp_hours
    FROM core.dim_drop_point dp
    CROSS JOIN period p
    LEFT JOIN analytics.vw_shipment_detail sh
        ON dp.drop_point_id = sh.drop_point_id
    GROUP BY
        dp.drop_point_id,
        dp.drop_point_name
),
metrics AS (
    SELECT
        *,
        ROUND(
            100.0 * parcel_out_mtd / NULLIF(parcel_in_mtd, 0),
            2
        ) AS parcel_out_pct,
        ROUND(
            100.0 * parcel_over_24h / NULLIF(parcel_at_dp, 0),
            2
        ) AS parcel_over_24h_pct
    FROM stats
)
SELECT
    *,
    CASE
        WHEN parcel_over_24h >= 10
          OR COALESCE(oldest_parcel_hours, 0) >= 48
            THEN 'CRITICAL'
        WHEN parcel_over_24h >= 3
          OR COALESCE(oldest_parcel_hours, 0) >= 24
            THEN 'WATCH'
        ELSE 'NORMAL'
    END AS parcel_status
FROM metrics;

COMMIT;
