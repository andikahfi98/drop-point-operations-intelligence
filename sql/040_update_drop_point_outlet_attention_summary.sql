CREATE OR REPLACE VIEW analytics.vw_drop_point_outlet_attention_summary AS

SELECT
    -- Existing columns: keep order
    as_of_date,
    drop_point_id,
    drop_point_name,

    COUNT(*) AS total_monitored_outlet,

    COUNT(*) FILTER (
        WHERE attention_status = 'CRITICAL'
    ) AS critical_outlet,

    -- Legacy compatibility:
    -- WARNING is no longer used.
    -- This column temporarily represents WATCH.
    COUNT(*) FILTER (
        WHERE attention_status = 'WATCH'
    ) AS warning_outlet,

    COUNT(*) FILTER (
        WHERE attention_status = 'NORMAL'
    ) AS normal_outlet,

    COUNT(*) FILTER (
        WHERE activity_status = 'INACTIVE_14D'
    ) AS inactive_14d_outlet,

    COUNT(*) FILTER (
        WHERE activity_status = 'WATCH_7D'
    ) AS watch_7d_outlet,

    -- New proper terminology
    COUNT(*) FILTER (
        WHERE attention_status = 'WATCH'
    ) AS watch_outlet

FROM analytics.vw_outlet_attention

GROUP BY
    as_of_date,
    drop_point_id,
    drop_point_name;