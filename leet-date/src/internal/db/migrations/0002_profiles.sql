ALTER TABLE users
    ADD COLUMN IF NOT EXISTS age                SMALLINT,
    ADD COLUMN IF NOT EXISTS gender             TEXT,
    ADD COLUMN IF NOT EXISTS looking_for        TEXT[],
    ADD COLUMN IF NOT EXISTS city               TEXT,
    ADD COLUMN IF NOT EXISTS bio                TEXT,
    ADD COLUMN IF NOT EXISTS interests          TEXT[],
    ADD COLUMN IF NOT EXISTS private_contact    TEXT,
    ADD COLUMN IF NOT EXISTS profile_updated_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS photos (
    id           BIGSERIAL PRIMARY KEY,
    user_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    filename     TEXT NOT NULL,
    content_type TEXT NOT NULL,
    sort_order   INT  NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS photos_user_id_idx ON photos(user_id, sort_order);
