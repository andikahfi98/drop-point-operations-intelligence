CREATE TABLE IF NOT EXISTS app.chat_session (

    chat_id BIGINT PRIMARY KEY,

    current_drop_point_id VARCHAR(30)
        REFERENCES core.dim_drop_point(drop_point_id),

    last_topic VARCHAR(50),

    conversation_summary TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


CREATE TABLE IF NOT EXISTS app.chat_message (

    message_id BIGSERIAL PRIMARY KEY,

    chat_id BIGINT NOT NULL
        REFERENCES app.chat_session(chat_id)
        ON DELETE CASCADE,

    role VARCHAR(20) NOT NULL
        CHECK (role IN ('user', 'assistant')),

    message TEXT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


CREATE INDEX IF NOT EXISTS idx_chat_message_history
ON app.chat_message (
    chat_id,
    created_at DESC
);