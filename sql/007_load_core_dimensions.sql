-- =========================================================
-- Drop Point Operations Intelligence
-- 007_load_core_dimensions.sql
-- RAW -> CORE DIMENSIONS
-- =========================================================

BEGIN;


-- =========================================================
-- 1. DIM DATE
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
    TRIM(date_key)::INTEGER,

    LEFT(TRIM(date), 10)::DATE,

    TRIM(year)::SMALLINT,

    UPPER(TRIM(quarter)),

    TRIM(month_no)::SMALLINT,

    TRIM(month_name),

    LEFT(TRIM(month_start), 10)::DATE,

    TRIM(week_no)::SMALLINT,

    TRIM(day_of_month)::SMALLINT,

    TRIM(day_name),

    CASE
        WHEN UPPER(TRIM(is_weekend))
             IN ('Y', 'YES', 'TRUE', '1')
        THEN TRUE
        ELSE FALSE
    END,

    CASE
        WHEN UPPER(TRIM(is_holiday))
             IN ('Y', 'YES', 'TRUE', '1')
        THEN TRUE
        ELSE FALSE
    END,

    CASE
        WHEN UPPER(TRIM(is_working_day))
             IN ('Y', 'YES', 'TRUE', '1')
        THEN TRUE
        ELSE FALSE
    END

FROM raw.dim_date

ON CONFLICT (date_key)
DO UPDATE SET

    date =
        EXCLUDED.date,

    year =
        EXCLUDED.year,

    quarter =
        EXCLUDED.quarter,

    month_no =
        EXCLUDED.month_no,

    month_name =
        EXCLUDED.month_name,

    month_start =
        EXCLUDED.month_start,

    week_no =
        EXCLUDED.week_no,

    day_of_month =
        EXCLUDED.day_of_month,

    day_name =
        EXCLUDED.day_name,

    is_weekend =
        EXCLUDED.is_weekend,

    is_holiday =
        EXCLUDED.is_holiday,

    is_working_day =
        EXCLUDED.is_working_day,

    loaded_at =
        NOW();


-- =========================================================
-- 2. DIM DROP POINT
-- =========================================================

INSERT INTO core.dim_drop_point (
    drop_point_id,
    drop_point_name,
    region,
    area,
    manager_name,
    status
)
SELECT
    TRIM(drop_point_id),
    TRIM(drop_point_name),
    TRIM(region),
    TRIM(area),
    NULLIF(TRIM(manager_name), ''),
    UPPER(TRIM(status))

FROM raw.dim_drop_point

ON CONFLICT (drop_point_id)
DO UPDATE SET

    drop_point_name =
        EXCLUDED.drop_point_name,

    region =
        EXCLUDED.region,

    area =
        EXCLUDED.area,

    manager_name =
        EXCLUDED.manager_name,

    status =
        EXCLUDED.status,

    loaded_at =
        NOW();


-- =========================================================
-- 3. DIM SALESPERSON
-- =========================================================

INSERT INTO core.dim_salesperson (
    salesperson_id,
    salesperson_name,
    drop_point_id,
    role,
    join_date,
    status
)
SELECT
    TRIM(salesperson_id),

    TRIM(salesperson_name),

    TRIM(drop_point_id),

    TRIM(role),

    CASE
        WHEN NULLIF(TRIM(join_date), '') IS NULL
        THEN NULL
        ELSE LEFT(TRIM(join_date), 10)::DATE
    END,

    UPPER(TRIM(status))

FROM raw.dim_salesperson

ON CONFLICT (salesperson_id)
DO UPDATE SET

    salesperson_name =
        EXCLUDED.salesperson_name,

    drop_point_id =
        EXCLUDED.drop_point_id,

    role =
        EXCLUDED.role,

    join_date =
        EXCLUDED.join_date,

    status =
        EXCLUDED.status,

    loaded_at =
        NOW();


-- =========================================================
-- 4. DIM OUTLET
-- =========================================================

INSERT INTO core.dim_outlet (
    outlet_id,
    bp_code,
    outlet_name,
    drop_point_id,
    salesperson_id,
    segment,
    route_code,
    city_area,
    active_flag,
    open_date
)
SELECT
    TRIM(outlet_id),

    TRIM(bp_code),

    TRIM(outlet_name),

    TRIM(drop_point_id),

    TRIM(salesperson_id),

    NULLIF(TRIM(segment), ''),

    NULLIF(TRIM(route_code), ''),

    NULLIF(TRIM(city_area), ''),

    CASE
        WHEN UPPER(TRIM(active_flag))
             IN ('Y', 'YES', 'TRUE', '1')
        THEN TRUE
        ELSE FALSE
    END,

    CASE
        WHEN NULLIF(TRIM(open_date), '') IS NULL
        THEN NULL
        ELSE LEFT(TRIM(open_date), 10)::DATE
    END

FROM raw.dim_outlet

ON CONFLICT (outlet_id)
DO UPDATE SET

    bp_code =
        EXCLUDED.bp_code,

    outlet_name =
        EXCLUDED.outlet_name,

    drop_point_id =
        EXCLUDED.drop_point_id,

    salesperson_id =
        EXCLUDED.salesperson_id,

    segment =
        EXCLUDED.segment,

    route_code =
        EXCLUDED.route_code,

    city_area =
        EXCLUDED.city_area,

    active_flag =
        EXCLUDED.active_flag,

    open_date =
        EXCLUDED.open_date,

    loaded_at =
        NOW();


-- =========================================================
-- 5. DIM PRODUCT
-- =========================================================

INSERT INTO core.dim_product (
    product_id,
    product_name,
    category,
    list_price,
    standard_cogs,
    status
)
SELECT
    TRIM(product_id),

    TRIM(product_name),

    TRIM(category),

    TRIM(list_price)::NUMERIC(18,2),

    TRIM(standard_cogs)::NUMERIC(18,2),

    UPPER(TRIM(status))

FROM raw.dim_product

ON CONFLICT (product_id)
DO UPDATE SET

    product_name =
        EXCLUDED.product_name,

    category =
        EXCLUDED.category,

    list_price =
        EXCLUDED.list_price,

    standard_cogs =
        EXCLUDED.standard_cogs,

    status =
        EXCLUDED.status,

    loaded_at =
        NOW();


COMMIT;