SELECT *
FROM collections
WHERE id = $1
LIMIT 1;
