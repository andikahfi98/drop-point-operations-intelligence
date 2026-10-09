-- ============================================================
-- 056 - Verify avg_dp_hours semantic
-- ============================================================

\echo '=== TANGERANG CURRENT PARCEL AGE CHECK ==='
WITH direct_check AS (
    SELECT
        drop_point_id,
        ROUND(
            AVG(parcel_age_hours) FILTER (WHERE is_at_dp),
            2
        ) AS expected_avg_dp_hours
    FROM analytics.vw_shipment_detail
    WHERE drop_point_id = 'DP-TGR-01'
    GROUP BY drop_point_id
)
SELECT
    p.drop_point_name,
    p.parcel_at_dp,
    p.parcel_under_6h,
    p.parcel_6_12h,
    p.parcel_12_24h,
    p.parcel_over_24h,
    p.oldest_parcel_hours,
    p.avg_dp_hours,
    d.expected_avg_dp_hours,
    p.parcel_status
FROM analytics.vw_drop_point_parcel_current p
LEFT JOIN direct_check d
    ON p.drop_point_id = d.drop_point_id
WHERE p.drop_point_id = 'DP-TGR-01';

\echo '=== ALL DROP POINTS ==='
SELECT
    drop_point_name,
    parcel_at_dp,
    avg_dp_hours,
    oldest_parcel_hours,
    parcel_over_24h,
    parcel_status
FROM analytics.vw_drop_point_parcel_current
ORDER BY drop_point_name;
