use crate::database::DbPool;
use flagdrive_shared::FlagDriveUser;
use rand::prelude::*;
use sha2::{Digest, Sha256};
use sqlx::Row;
use std::time::{SystemTime, UNIX_EPOCH};

/// PBKDF-style password hashing using SHA-256 (no extra dependency needed).
///
/// SECURITY: passwords were previously stored in plaintext, so any DB read
/// (e.g. via the known postgres credentials or another SQL-extraction bug)
/// exposed every user's password and allowed direct login as any user. We now
/// store a salted, iterated hash instead. The format is `salt$hash` (both
/// lowercase hex). Verification is constant-time over the final comparison.
///
/// This is a defense-in-depth hardening, not a replacement for a real KDF like
/// argon2, but it eliminates plaintext storage using only the already-present
/// sha2 crate.
const HASH_ITERATIONS: u32 = 100_000;

fn random_salt_hex() -> String {
    let bytes: [u8; 16] = rand::rng().random();
    hex_encode(&bytes)
}

fn hex_encode(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{:02x}", b));
    }
    s
}

fn pbkdf_sha256(password: &str, salt: &str, iterations: u32) -> [u8; 32] {
    // First iteration: H(salt || password)
    let mut hasher = Sha256::new();
    hasher.update(salt.as_bytes());
    hasher.update(password.as_bytes());
    let mut acc = hasher.finalize();
    // Remaining iterations
    for _ in 0..iterations {
        let mut h = Sha256::new();
        h.update(&acc);
        h.update(password.as_bytes());
        acc = h.finalize();
    }
    acc.into()
}

pub fn hash_password(password: &str) -> String {
    let salt = random_salt_hex();
    let hash = pbkdf_sha256(password, &salt, HASH_ITERATIONS);
    format!("{}${}", salt, hex_encode(&hash))
}

pub fn verify_password(password: &str, stored: &str) -> bool {
    let Some((salt, hash_hex)) = stored.split_once('$') else {
        return false;
    };
    let computed = pbkdf_sha256(password, salt, HASH_ITERATIONS);
    let computed_hex = hex_encode(&computed);
    // Constant-time compare to avoid a timing oracle on password verification.
    constant_time_eq_str(&computed_hex, hash_hex)
}

fn constant_time_eq_str(a: &str, b: &str) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff: u8 = 0;
    for (x, y) in a.bytes().zip(b.bytes()) {
        diff |= x ^ y;
    }
    diff == 0
}

pub async fn create_new_user(
    pool: &DbPool,
    username: &str,
    user_password: &str,
    encryption_key: &str,
) -> Result<(), sqlx::Error> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as u64)
        .unwrap_or(0);

    let password_hash = hash_password(user_password);

    sqlx::query("INSERT INTO users (username, user_password, created_at, encryption_key) VALUES ($1, $2, $3, $4)")
        .bind(username)
        .bind(password_hash)
        .bind(now as i64)
        .bind(encryption_key)
        .execute(pool)
        .await?;

    Ok(())
}

pub async fn create_new_token(pool: &DbPool, username: &str) -> Result<String, sqlx::Error> {
    let token = rand::rng()
        .sample_iter(&rand::distr::Alphanumeric)
        .take(128)
        .map(char::from)
        .collect::<String>();

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as u64)
        .unwrap_or(0);

    sqlx::query("INSERT INTO auth_token (username, token, created_at) VALUES ($1, $2, $3)")
        .bind(username)
        .bind(token.clone())
        .bind(now as i64)
        .execute(pool)
        .await?;

    Ok(token)
}

pub async fn check_user_password(
    pool: &DbPool,
    username: &str,
    password: &str,
) -> Result<bool, sqlx::Error> {
    let row = sqlx::query("SELECT user_password FROM users WHERE username = $1")
        .bind(username)
        .fetch_one(pool)
        .await?;
    let user_password: String = row.get("user_password");

    // Verify against the stored salted hash (constant-time). Legacy plaintext
    // rows (if any) won't match the `salt$hash` format and are rejected; on a
    // fresh DB all rows are hashed.
    Ok(verify_password(password, &user_password))
}

pub async fn get_user_by_username(
    pool: &DbPool,
    username: &str,
    viewer: Option<&str>,
) -> Result<FlagDriveUser, sqlx::Error> {
    let viewer_str = viewer.unwrap_or("");

    let row = sqlx::query(
        "SELECT \
         username, \
         (SELECT COUNT(*) FROM follows WHERE followee = users.username) as followers_count, \
         (SELECT COUNT(*) FROM follows WHERE follower = users.username) as following_count, \
         (SELECT EXISTS(SELECT 1 FROM follows WHERE followee = users.username AND follower = $1)) as is_followed \
         FROM users WHERE username = $2",
    )
    .bind(viewer_str)
    .bind(username)
    .fetch_one(pool)
    .await?;

    let username_str: String = row.get("username");
    let followers: i64 = row.get("followers_count");
    let following: i64 = row.get("following_count");
    let is_followed: bool = row.get("is_followed");

    Ok(FlagDriveUser {
        username: username_str,
        followers_count: followers as usize,
        following_count: following as usize,
        is_followed,
    })
}

pub async fn get_username_from_token(pool: &DbPool, token: &str) -> Result<String, sqlx::Error> {
    let row = sqlx::query("SELECT username FROM auth_token WHERE token = $1")
        .bind(token)
        .fetch_one(pool)
        .await?;
    Ok(row.get("username"))
}

pub async fn get_user_encryption_key(pool: &DbPool, username: &str) -> Result<String, sqlx::Error> {
    let row = sqlx::query("SELECT encryption_key FROM users WHERE username = $1")
        .bind(username)
        .fetch_one(pool)
        .await?;
    Ok(row.get("encryption_key"))
}

pub async fn delete_token(pool: &DbPool, token: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM auth_token WHERE token = $1")
        .bind(token)
        .execute(pool)
        .await?;
    Ok(())
}
