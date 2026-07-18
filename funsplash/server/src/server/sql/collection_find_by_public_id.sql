SELECT *
FROM collections
WHERE public_id = $1
LIMIT 1;
