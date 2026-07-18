use crate::database::DbPool;
use flagdrive_shared::{FlagDriveFile, FlagDriveFileVisibility};
use sqlx::Row;
use std::time::{SystemTime, UNIX_EPOCH};

pub async fn get_user_files(
    pool: &DbPool,
    username: &str,
    viewer: Option<&str>,
) -> Result<Vec<FlagDriveFile>, sqlx::Error> {
    let viewer_str = viewer.unwrap_or("");

    let rows = sqlx::query(
        "SELECT id, name, owner, visibility, size, created_at, protection_key, is_protected FROM files \
         WHERE owner = $1 \
           AND ( \
               visibility = 1 \
               OR $2 = $1 \
               OR ($2 IN (SELECT follower FROM follows WHERE followee = $1) AND (visibility = 1 OR visibility = 3)) \
               OR ($2 IN (SELECT followee FROM follows WHERE follower = $1) AND visibility = 2) \
           ) \
         UNION ALL \
         SELECT id, name, owner, visibility, size, created_at, protection_key, is_protected FROM files \
         WHERE owner IN (SELECT followee FROM follows WHERE follower = $1) \
           AND ( \
               visibility = 1 \
               OR (visibility = 3 AND (owner = $2 OR $2 IN (SELECT follower FROM follows WHERE followee = owner))) \
           ) \
         UNION ALL \
         SELECT id, name, owner, visibility, size, created_at, protection_key, is_protected FROM files \
         WHERE owner IN (SELECT follower FROM follows WHERE followee = $1) \
           AND visibility = 2 \
           AND (owner = $2 OR $2 IN (SELECT followee FROM follows WHERE follower = owner))"
    )
    .bind(username)
    .bind(viewer_str)
    .fetch_all(pool)
    .await?;

    let files = rows
        .into_iter()
        .map(|row| FlagDriveFile {
            id: row.get::<i64, _>("id") as u64,
            name: row.get("name"),
            owner: row.get("owner"),
            visibility: match row.get("visibility") {
                1 => FlagDriveFileVisibility::Public,
                2 => FlagDriveFileVisibility::Following,
                3 => FlagDriveFileVisibility::Followers,
                _ => FlagDriveFileVisibility::Private,
            },
            size: row.get::<i64, _>("size") as u64,
            created_at: row.get::<i64, _>("created_at") as u64,
            is_protected: row.get::<bool, _>("is_protected"),
        })
        .collect();

    Ok(files)
}

pub async fn add_upload_file(
    pool: &DbPool,
    id: i64,
    name: &str,
    owner: &str,
    visibility: i32,
    content: &[u8],
    protection_key: &str,
    is_protected: i32,
) -> Result<(), sqlx::Error> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as u64)
        .unwrap_or(0);

    let size = content.len();

    sqlx::query(
        "INSERT INTO files (id, name, owner, visibility, size, content, created_at, protection_key, is_protected) \
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
    )
    .bind(id)
    .bind(name)
    .bind(owner)
    .bind(visibility)
    .bind(size as i64)
    .bind(content)
    .bind(now as i64)
    .bind(protection_key)
    .bind(is_protected != 0)
    .execute(pool)
    .await?;

    Ok(())
}

pub async fn get_download_file(
    pool: &DbPool,
    id: i64,
) -> Result<(FlagDriveFile, Vec<u8>, String), sqlx::Error> {
    let row = sqlx::query(
        "SELECT id, name, owner, visibility, size, content, created_at, protection_key, is_protected FROM files \
         WHERE id = $1",
    )
    .bind(id)
    .fetch_one(pool)
    .await?;

    Ok((
        FlagDriveFile {
            id: row.get::<i64, _>("id") as u64,
            name: row.get("name"),
            owner: row.get("owner"),
            visibility: match row.get("visibility") {
                1 => FlagDriveFileVisibility::Public,
                2 => FlagDriveFileVisibility::Following,
                3 => FlagDriveFileVisibility::Followers,
                _ => FlagDriveFileVisibility::Private,
            },
            size: row.get::<i64, _>("size") as u64,
            created_at: row.get::<i64, _>("created_at") as u64,
            is_protected: row.get::<bool, _>("is_protected"),
        },
        row.get("content"),
        row.get("protection_key"),
    ))
}
