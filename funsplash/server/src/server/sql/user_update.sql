UPDATE users
SET username = $2,
    first_name = $3 ,
    last_name = nullif($4,''),
    bio = nullif($5,''),
    available_for_hire = $6
where id = $1
RETURNING *;
