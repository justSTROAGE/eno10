SELECT collection_id
FROM collections_photos
JOIN collections ON collections.id = collections_photos.collection_id
WHERE collections.creator = $1 AND collections_photos.photo_id = $2;
