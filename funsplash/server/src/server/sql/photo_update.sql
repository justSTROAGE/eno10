UPDATE photos
SET description = $2, location = $3, camera = $4, privacy = $5, show_on_profile = $6
WHERE public_id = $1 AND creator = $7
RETURNING *;
