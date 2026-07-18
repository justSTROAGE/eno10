UPDATE collections
SET name = $2, description = $3, private = $4
WHERE id = $1 AND creator = $5
RETURNING *;
