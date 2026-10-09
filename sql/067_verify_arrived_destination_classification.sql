-- The two overlap checks should both be zero.
SELECT
    COUNT(*) FILTER (
        WHERE is_at_dp = TRUE AND delivery_class = 'IN_TRANSIT'
    ) AS at_dp_still_in_transit,
    COUNT(*) FILTER (
        WHERE shipment_status = 'ARRIVED_DESTINATION'
          AND delivery_class <> 'AT_DESTINATION_DP'
    ) AS arrived_wrong_delivery_class,
    COUNT(*) FILTER (
        WHERE shipment_status = 'ARRIVED_DESTINATION'
          AND delivery_class = 'AT_DESTINATION_DP'
    ) AS arrived_correctly_classified
FROM analytics.vw_shipment_detail;

-- Current classification distribution for arrived parcels.
SELECT delivery_class, COUNT(*) AS shipment_count
FROM analytics.vw_shipment_detail
WHERE shipment_status = 'ARRIVED_DESTINATION'
GROUP BY delivery_class ORDER BY delivery_class;

-- Current DP counts and delivery counts by destination location.
SELECT p.drop_point_name,
       p.parcel_at_dp,
       d.in_transit_delivery,
       d.overdue_delivery,
       d.on_time_rate_pct
FROM analytics.vw_drop_point_parcel_current p
JOIN analytics.vw_drop_point_current_delivery d
  ON p.drop_point_id = d.drop_point_id
ORDER BY p.drop_point_name;
