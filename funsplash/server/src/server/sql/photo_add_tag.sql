WITH inserted_tag AS (
    INSERT INTO tags (tag) VALUES ($1) ON CONFLICT DO NOTHING
)
INSERT INTO photos_tags (tag, photo_id) VALUES ($1, $2) ON CONFLICT DO NOTHING
RETURNING *;
