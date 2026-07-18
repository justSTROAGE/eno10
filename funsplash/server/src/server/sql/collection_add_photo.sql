INSERT INTO collections_photos (photo_id, collection_id)
VALUES ($1, $2)
ON CONFLICT DO NOTHING
RETURNING *;
