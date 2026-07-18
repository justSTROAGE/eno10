UPDATE users SET storage_quota_used = storage_quota_used + $2 WHERE id = $1;
