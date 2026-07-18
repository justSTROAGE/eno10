use rand::prelude::*;
use sqlx::postgres::PgPool;
use std::time::{SystemTime, UNIX_EPOCH};

pub type DbPool = PgPool;

pub async fn connect_to_db(database_url: &str) -> DbPool {
    let pg_pool = PgPool::connect(database_url)
        .await
        .expect("Failed to connect to PostgreSQL database");

    sqlx::migrate!("./migrations/postgres")
        .run(&pg_pool)
        .await
        .expect("Failed to run PostgreSQL database migrations");

    pg_pool
}

pub async fn delete_old_data(pool: &DbPool, age_limit_seconds: u64) -> Result<u64, sqlx::Error> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as u64)
        .unwrap_or(0);

    let cutoff = now.saturating_sub(age_limit_seconds) as i64;

    let result = sqlx::query("DELETE FROM users WHERE created_at < $1")
        .bind(cutoff)
        .execute(pool)
        .await?;
    let rows = result.rows_affected();
    if rows > 0 {
        let _ = sqlx::query("VACUUM FULL").execute(pool).await;
    }
    Ok(rows)
}

pub async fn get_or_create_server_key(pool: &DbPool) -> Result<String, sqlx::Error> {
    let row = sqlx::query("SELECT value FROM server_config WHERE key = 'server_key'")
        .fetch_optional(pool)
        .await?;

    if let Some(row) = row {
        use sqlx::Row;
        Ok(row.get("value"))
    } else {
        let new_key = rand::rng()
            .sample_iter(&rand::distr::Alphanumeric)
            .take(128)
            .map(char::from)
            .collect::<String>();

        sqlx::query("INSERT INTO server_config (key, value) VALUES ('server_key', $1)")
            .bind(&new_key)
            .execute(pool)
            .await?;

        Ok(new_key)
    }
}
