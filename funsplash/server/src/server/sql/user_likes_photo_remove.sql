WITH deleted_like AS (
    DELETE FROM likes 
    WHERE user_id = $1 AND photo_id = $2
    RETURNING photo_id
)
UPDATE photos
SET likes_count = likes_count - 1 
FROM deleted_like
WHERE photos.id = deleted_like.photo_id
RETURNING photos.*;
