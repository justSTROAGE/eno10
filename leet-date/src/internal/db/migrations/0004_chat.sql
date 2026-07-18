CREATE TABLE IF NOT EXISTS conversations (
    id              BIGSERIAL PRIMARY KEY,
    user_a          BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b          BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_message_at TIMESTAMPTZ,
    UNIQUE (user_a, user_b),
    CHECK (user_a < user_b)
);

CREATE INDEX IF NOT EXISTS conversations_user_a_idx ON conversations(user_a);
CREATE INDEX IF NOT EXISTS conversations_user_b_idx ON conversations(user_b);

CREATE TABLE IF NOT EXISTS messages (
    id              BIGSERIAL PRIMARY KEY,
    conversation_id BIGINT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body            TEXT   NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS messages_conversation_idx
    ON messages(conversation_id, created_at);

INSERT INTO conversations (user_a, user_b)
SELECT user_a, user_b FROM matches
ON CONFLICT (user_a, user_b) DO NOTHING;
