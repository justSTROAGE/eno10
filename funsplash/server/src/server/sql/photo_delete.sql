DELETE FROM photos
WHERE public_id = $1 AND creator = $2
RETURNING *;
