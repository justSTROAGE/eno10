SELECT *
FROM photos
WHERE asset_id = $1
LIMIT 1;
