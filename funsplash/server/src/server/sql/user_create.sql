INSERT INTO users (username, first_name, last_name, password, bio, available_for_hire)
VALUES ($1,
	$2,
       	nullif($3,''),
	$4,
	nullif($5,''),
	$6
)
RETURNING *;
