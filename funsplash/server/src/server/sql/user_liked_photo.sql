SELECT true AS user_liked
FROM likes
WHERE user_id = $1 
AND photo_id = $2;
