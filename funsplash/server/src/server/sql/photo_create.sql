WITH updated_user AS (
     UPDATE users
     SET storage_quota_used = storage_quota_used + $7
     WHERE id = $2
)
INSERT INTO photos (description, creator, privacy, location, camera, show_on_profile, file_size, mimetype, public_id)
VALUES (nullif($1,''),
	$2,
	$3,
	nullif($4,''),
	nullif($5,''),
	$6,
	$7,
	$8,
	$9)
RETURNING *;
