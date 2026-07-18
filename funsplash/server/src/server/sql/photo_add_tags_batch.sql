WITH unnested_tags AS (
    SELECT unnest($1::text[]) AS tag
),
inserted_tags AS (
    INSERT INTO tags (tag)
    SELECT tag FROM unnested_tags
    ON CONFLICT DO NOTHING
)
INSERT INTO photos_tags (tag, photo_id)
SELECT tag, $2 FROM unnested_tags
ON CONFLICT DO NOTHING
RETURNING *;
