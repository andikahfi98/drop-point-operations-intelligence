-- =========================================================
-- Drop Point Operations Intelligence
-- 009_extend_app_access.sql
-- Extend application authorization model
-- =========================================================

ALTER TABLE app.app_role
ADD COLUMN IF NOT EXISTS data_scope VARCHAR(30);


ALTER TABLE app.user_drop_point_access
ADD COLUMN IF NOT EXISTS access_type VARCHAR(30) NOT NULL DEFAULT 'VIEW';


ALTER TABLE app.user_drop_point_access
ADD COLUMN IF NOT EXISTS is_primary BOOLEAN NOT NULL DEFAULT FALSE;