CREATE TABLE IF NOT EXISTS swipes (
    user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_id  BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    direction  TEXT   NOT NULL CHECK (direction IN ('like','pass')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, target_id),
    CHECK (user_id <> target_id)
);

CREATE INDEX IF NOT EXISTS swipes_target_id_idx ON swipes(target_id);

CREATE OR REPLACE VIEW matches AS
SELECT
    LEAST(a.user_id, a.target_id)    AS user_a,
    GREATEST(a.user_id, a.target_id) AS user_b,
    GREATEST(a.created_at, b.created_at) AS matched_at
FROM swipes a
JOIN swipes b
  ON b.user_id = a.target_id
 AND b.target_id = a.user_id
WHERE a.direction = 'like'
  AND b.direction = 'like'
  AND a.user_id < a.target_id;
