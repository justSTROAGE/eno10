use crate::database::DbPool;
use sqlx::Row;

pub async fn insert_gdpr_data(
    pool: &DbPool,
    username: &str,
    timestamp: i64,
    nonce: &str,
    content: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO gdpr_data (username, timestamp, nonce, content) VALUES ($1, $2, $3, $4)")
        .bind(username)
        .bind(timestamp)
        .bind(nonce)
        .bind(content)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn get_gdpr_data(
    pool: &DbPool,
    username: &str,
    timestamp_or_latest: &str,
    nonce: &str,
) -> Result<String, sqlx::Error> {
    // SECURITY: require an EXACT nonce match. The previous implementation used a
    // range query (`nonce >= $2 AND nonce < $3`) so that any nonce in a wide
    // range would match, making the GDPR download IDOR enumerable. With an
    // exact match against the 128-bit random nonce, the export is unguessable
    // without the exact gdpr_id returned to the owner at request time.
    if nonce.len() != 32 || !nonce.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(sqlx::Error::RowNotFound);
    }

    let row = if timestamp_or_latest == "latest" {
        sqlx::query(
            "SELECT content FROM gdpr_data WHERE username = $1 AND nonce = $2 \
             ORDER BY timestamp DESC LIMIT 1",
        )
        .bind(username)
        .bind(nonce)
        .fetch_one(pool)
        .await?
    } else {
        let timestamp: i64 = timestamp_or_latest
            .parse()
            .map_err(|_| sqlx::Error::RowNotFound)?;

        sqlx::query(
            "SELECT content FROM gdpr_data WHERE username = $1 AND timestamp = $2 AND nonce = $3",
        )
        .bind(username)
        .bind(timestamp)
        .bind(nonce)
        .fetch_one(pool)
        .await?
    };
    Ok(row.get("content"))
}
