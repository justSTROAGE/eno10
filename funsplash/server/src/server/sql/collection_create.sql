INSERT INTO collections (public_id, name, description, creator, private)
VALUES ($1, $2, nullif($3, ''), $4, $5)
RETURNING *;
