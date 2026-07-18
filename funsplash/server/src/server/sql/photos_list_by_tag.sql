SELECT photos.public_id
FROM photos
JOIN photos_tags ON photos.id = photos_tags.photo_id
WHERE photos_tags.tag = $1;
