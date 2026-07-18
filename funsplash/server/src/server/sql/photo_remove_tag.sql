DELETE FROM photos_tags
WHERE tag = $1 AND photo_id = $2
RETURNING *;
