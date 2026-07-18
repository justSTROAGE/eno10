SELECT p.* 
FROM collections_photos cp
JOIN photos p ON p.id = cp.photo_id
WHERE cp.collection_id = $1;
