DELETE FROM collections
WHERE id = $1 AND creator = $2
RETURNING id;
