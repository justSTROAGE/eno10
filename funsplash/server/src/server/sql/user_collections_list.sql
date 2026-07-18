SELECT *
FROM collections
WHERE creator = $1
ORDER BY id DESC;
