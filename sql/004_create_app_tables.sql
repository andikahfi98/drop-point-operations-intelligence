-- =========================================================
-- Drop Point Operations Intelligence
-- 004_create_app_tables.sql
-- Authentication & Authorization
-- =========================================================


-- =========================================================
-- ROLE MASTER
-- =========================================================

CREATE TABLE IF NOT EXISTS app.app_role (
    role_code           VARCHAR(30) PRIMARY KEY,
    role_name           VARCHAR(100) NOT NULL,
    description         VARCHAR(255),
    can_view_all_dp     BOOLEAN NOT NULL DEFAULT FALSE,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =========================================================
-- APPLICATION USER
-- =========================================================

CREATE TABLE IF NOT EXISTS app.app_user (
    user_id                 VARCHAR(30) PRIMARY KEY,
    full_name               VARCHAR(150) NOT NULL,
    email                   VARCHAR(255) NOT NULL,
    password_hash           VARCHAR(255),
    role_code               VARCHAR(30) NOT NULL,

    status                  VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    must_change_password    BOOLEAN NOT NULL DEFAULT TRUE,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at           TIMESTAMPTZ,

    CONSTRAINT uq_app_user_email
        UNIQUE (email),

    CONSTRAINT fk_app_user_role
        FOREIGN KEY (role_code)
        REFERENCES app.app_role(role_code),

    CONSTRAINT chk_app_user_status
        CHECK (status IN ('ACTIVE', 'INACTIVE', 'LOCKED'))
);


-- =========================================================
-- USER <-> DROP POINT ACCESS
-- Allows one user to access one or multiple Drop Points
-- =========================================================

CREATE TABLE IF NOT EXISTS app.user_drop_point_access (
    user_id             VARCHAR(30) NOT NULL,
    drop_point_id       VARCHAR(20) NOT NULL,

    granted_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at          TIMESTAMPTZ,

    PRIMARY KEY (
        user_id,
        drop_point_id
    ),

    CONSTRAINT fk_user_dp_user
        FOREIGN KEY (user_id)
        REFERENCES app.app_user(user_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_user_dp_drop_point
        FOREIGN KEY (drop_point_id)
        REFERENCES core.dim_drop_point(drop_point_id),

    CONSTRAINT chk_user_dp_dates
        CHECK (
            revoked_at IS NULL
            OR revoked_at >= granted_at
        )
);


-- =========================================================
-- INDEXES
-- =========================================================

CREATE INDEX IF NOT EXISTS idx_app_user_role
    ON app.app_user(role_code);

CREATE INDEX IF NOT EXISTS idx_user_dp_drop_point
    ON app.user_drop_point_access(drop_point_id);