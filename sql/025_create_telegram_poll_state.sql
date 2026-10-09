CREATE TABLE IF NOT EXISTS app.telegram_poll_state (

    bot_name VARCHAR(50) PRIMARY KEY,

    last_update_id BIGINT NOT NULL DEFAULT 0,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


INSERT INTO app.telegram_poll_state (
    bot_name,
    last_update_id
)
VALUES (
    'operations_bot',
    0
)
ON CONFLICT (bot_name)
DO NOTHING;