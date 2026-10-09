-- =========================================================
-- Drop Point Operations Intelligence
-- 014_extend_date_dimension.sql
-- Extend Date Dimension
-- =========================================================

INSERT INTO core.dim_date (
    date_key,
    date,
    year,
    quarter,
    month_no,
    month_name,
    month_start,
    week_no,
    day_of_month,
    day_name,
    is_weekend,
    is_holiday,
    is_working_day
)

SELECT
    TO_CHAR(d, 'YYYYMMDD')::INTEGER AS date_key,

    d::DATE AS date,

    EXTRACT(YEAR FROM d)::SMALLINT AS year,

    'Q' || EXTRACT(QUARTER FROM d)::INTEGER AS quarter,

    EXTRACT(MONTH FROM d)::SMALLINT AS month_no,

    TO_CHAR(d, 'FMMonth') AS month_name,

    DATE_TRUNC('month', d)::DATE AS month_start,

    EXTRACT(WEEK FROM d)::SMALLINT AS week_no,

    EXTRACT(DAY FROM d)::SMALLINT AS day_of_month,

    TO_CHAR(d, 'FMDay') AS day_name,

    CASE
        WHEN EXTRACT(ISODOW FROM d) IN (6, 7)
        THEN TRUE
        ELSE FALSE
    END AS is_weekend,

    FALSE AS is_holiday,

    CASE
        WHEN EXTRACT(ISODOW FROM d) IN (6, 7)
        THEN FALSE
        ELSE TRUE
    END AS is_working_day

FROM GENERATE_SERIES(
    DATE '2026-01-01',
    DATE '2027-12-31',
    INTERVAL '1 day'
) AS g(d)

ON CONFLICT (date)
DO NOTHING;