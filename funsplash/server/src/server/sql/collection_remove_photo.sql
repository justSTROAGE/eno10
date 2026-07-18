DELETE FROM collections_photos
WHERE photo_id = $1 AND collection_id = $2
RETURNING *;
