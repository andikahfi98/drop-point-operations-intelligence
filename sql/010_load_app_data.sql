-- =========================================================
-- Drop Point Operations Intelligence
-- 010_load_app_data.sql
-- RAW -> APP
-- =========================================================

BEGIN;


-- =========================================================
-- 1. APP ROLE
-- =========================================================

INSERT INTO app.app_role (
    role_code,
    role_name,
    description,
    can_view_all_dp,
    is_active,
    data_scope
)
SELECT
    UPPER(TRIM(role_code)),

    TRIM(role_name),

    NULLIF(TRIM(description), ''),

    CASE
        WHEN UPPER(TRIM(can_view_all_drop_points))
             IN ('Y', 'YES', 'TRUE', '1')
        THEN TRUE
        ELSE FALSE
    END,

    TRUE,

    UPPER(TRIM(data_scope))

FROM raw.app_role

ON CONFLICT (role_code)
DO UPDATE SET

    role_name =
        EXCLUDED.role_name,

    description =
        EXCLUDED.description,

    can_view_all_dp =
        EXCLUDED.can_view_all_dp,

    is_active =
        EXCLUDED.is_active,

    data_scope =
        EXCLUDED.data_scope;


-- =========================================================
-- 2. APP USER
-- Password hash may remain NULL until authentication setup
-- =========================================================

INSERT INTO app.app_user (
    user_id,
    full_name,
    email,
    password_hash,
    role_code,
    status,
    must_change_password,
    created_at,
    updated_at
)
SELECT
    TRIM(user_id),

    TRIM(full_name),

    LOWER(TRIM(email)),

    NULLIF(TRIM(password_hash), ''),

    UPPER(TRIM(role_code)),

    UPPER(TRIM(status)),

    CASE
        WHEN UPPER(TRIM(must_change_password))
             IN ('Y', 'YES', 'TRUE', '1')
        THEN TRUE
        ELSE FALSE
    END,

    CASE
        WHEN NULLIF(TRIM(created_at), '') IS NULL
        THEN NOW()
        ELSE TRIM(created_at)::TIMESTAMPTZ
    END,

    NOW()

FROM raw.app_user

ON CONFLICT (user_id)
DO UPDATE SET

    full_name =
        EXCLUDED.full_name,

    email =
        EXCLUDED.email,

    password_hash =
        EXCLUDED.password_hash,

    role_code =
        EXCLUDED.role_code,

    status =
        EXCLUDED.status,

    must_change_password =
        EXCLUDED.must_change_password,

    updated_at =
        NOW();


-- =========================================================
-- 3. USER DROP POINT ACCESS
-- =========================================================

INSERT INTO app.user_drop_point_access (
    user_id,
    drop_point_id,
    access_type,
    is_primary
)
SELECT
    TRIM(user_id),

    TRIM(drop_point_id),

    UPPER(TRIM(access_type)),

    CASE
        WHEN UPPER(TRIM(is_primary))
             IN ('Y', 'YES', 'TRUE', '1')
        THEN TRUE
        ELSE FALSE
    END

FROM raw.user_drop_point_access

ON CONFLICT (user_id, drop_point_id)
DO UPDATE SET

    access_type =
        EXCLUDED.access_type,

    is_primary =
        EXCLUDED.is_primary,

    revoked_at =
        NULL;


COMMIT;