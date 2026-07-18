SELECT *
FROM users
WHERE username ILIKE $1 || '%' ORDER BY created_at ASC;
