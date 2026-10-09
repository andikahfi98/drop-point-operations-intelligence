-- Website sessions contain only a SHA-256 digest of the bearer token.
-- Apply once after migration 060. Existing n8n workflows are unaffected.
BEGIN;

CREATE TABLE IF NOT EXISTS app.auth_session (
    token_hash CHAR(64) PRIMARY KEY,
    user_id VARCHAR(30) NOT NULL REFERENCES app.app_user(user_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    CONSTRAINT auth_session_expiry CHECK (expires_at > created_at)
);

CREATE INDEX IF NOT EXISTS idx_auth_session_user_active
    ON app.auth_session(user_id, expires_at) WHERE revoked_at IS NULL;

COMMIT;
