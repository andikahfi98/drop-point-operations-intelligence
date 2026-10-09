-- =========================================================
-- 024_create_alert_state.sql
-- Alert state & history
-- =========================================================

CREATE TABLE IF NOT EXISTS app.alert_state (

    drop_point_id VARCHAR(30) PRIMARY KEY
        REFERENCES core.dim_drop_point(drop_point_id),

    last_status VARCHAR(20) NOT NULL DEFAULT 'UNKNOWN',

    last_alerted_at TIMESTAMPTZ,

    last_status_changed_at TIMESTAMPTZ,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


CREATE TABLE IF NOT EXISTS app.alert_event_log (

    event_id BIGSERIAL PRIMARY KEY,

    drop_point_id VARCHAR(30) NOT NULL
        REFERENCES core.dim_drop_point(drop_point_id),

    previous_status VARCHAR(20),

    new_status VARCHAR(20) NOT NULL,

    event_type VARCHAR(30) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


INSERT INTO app.alert_state (
    drop_point_id,
    last_status
)

SELECT
    drop_point_id,
    'UNKNOWN'

FROM core.dim_drop_point

ON CONFLICT (drop_point_id)
DO NOTHING;