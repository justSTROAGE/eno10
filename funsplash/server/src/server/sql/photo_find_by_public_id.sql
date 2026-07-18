SELECT *
FROM photos
WHERE public_id = $1
LIMIT 1;
