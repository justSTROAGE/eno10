use crate::database::DbPool;
use sqlx::Row;

pub async fn follow_user(pool: &DbPool, follower: &str, followee: &str) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO follows (follower, followee) VALUES ($1, $2) ON CONFLICT DO NOTHING",
    )
    .bind(follower)
    .bind(followee)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn is_following(
    pool: &DbPool,
    follower: &str,
    followee: &str,
) -> Result<bool, sqlx::Error> {
    let row = sqlx::query(
        "SELECT EXISTS(SELECT 1 FROM follows WHERE follower = $1 AND followee = $2)",
    )
    .bind(follower)
    .bind(followee)
    .fetch_one(pool)
    .await?;
    let exists: bool = row.get(0);
    Ok(exists)
}

pub async fn unfollow_user(
    pool: &DbPool,
    follower: &str,
    followee: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM follows WHERE follower = $1 AND followee = $2")
        .bind(follower)
        .bind(followee)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn get_following_list(pool: &DbPool, username: &str) -> Result<Vec<String>, sqlx::Error> {
    let rows = sqlx::query("SELECT followee FROM follows WHERE follower = $1")
        .bind(username)
        .fetch_all(pool)
        .await?;
    let following = rows.into_iter().map(|row| row.get("followee")).collect();
    Ok(following)
}

pub async fn get_followers_list(pool: &DbPool, username: &str) -> Result<Vec<String>, sqlx::Error> {
    let rows = sqlx::query("SELECT follower FROM follows WHERE followee = $1")
        .bind(username)
        .fetch_all(pool)
        .await?;
    let followers = rows.into_iter().map(|row| row.get("follower")).collect();
    Ok(followers)
}
