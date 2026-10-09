-- ============================================================
-- 061 - Seed temporary passwords for website manager accounts
--
-- Usage with psql:
--   psql ... -v demo_password='YOUR_TEMP_PASSWORD' -f 061_seed_manager_passwords.sql
--
-- The plaintext password is NOT stored. PostgreSQL pgcrypto creates
-- a bcrypt-compatible hash. Existing non-null hashes are not overwritten.
-- ============================================================

\set ON_ERROR_STOP on

\if :{?demo_password}
\else
    \echo 'ERROR: psql variable demo_password is required.'
    \quit
\endif

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

UPDATE app.app_user
SET
    password_hash = crypt(:'demo_password', gen_salt('bf', 12)),
    must_change_password = TRUE,
    updated_at = NOW()
WHERE role_code IN ('DP_MANAGER', 'REGIONAL_MANAGER')
  AND password_hash IS NULL;

COMMIT;
