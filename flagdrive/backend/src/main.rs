mod api_routes;
mod auth;
mod cli;
mod crypto;
mod database;

use api_routes::{
    files::{download_file, get_file_list, upload_file},
    gdpr::gdpr_download_user_data,
    gdpr::gdpr_request_user_data,
    login::login_as_user,
    register::register_new_user,
    token::{logout_token, verify_token},
    user::{
        follow_user_action, get_followers_action, get_following_action, get_user_info,
        unfollow_user_action,
    },
};
use axum::{
    Json, Router,
    routing::{get, post},
};
use clap::Parser;
use cli::Args;
use database::DbPool;
use serde_json::{Value, json};
use std::time::{SystemTime, UNIX_EPOCH};
use tower_http::services::ServeDir;

#[tokio::main]
async fn main() {
    let args = Args::parse();
    let database_url = std::env::var("DATABASE_URL").unwrap_or_else(|_| {
        if args.pg_host.is_some() || args.pg_user.is_some() || args.pg_dbname.is_some() {
            let host = args.pg_host.unwrap_or_else(|| "localhost".to_string());
            let port = args.pg_port.unwrap_or(5432);
            let user = args.pg_user.unwrap_or_else(|| "flagdrive".to_string());
            let password = args
                .pg_password
                .unwrap_or_else(|| "flagdrivepassword".to_string());
            let dbname = args.pg_dbname.unwrap_or_else(|| "flagdrive".to_string());
            format!(
                "postgres://{}:{}@{}:{}/{}",
                user, password, host, port, dbname
            )
        } else if args.database.starts_with("postgres://")
            || args.database.starts_with("postgresql://")
        {
            args.database.clone()
        } else {
            "postgres://flagdrive:flagdrivepassword@localhost:5432/flagdrive".to_string()
        }
    });

    println!("Database type: PostgreSQL");

    let pool = database::connect_to_db(&database_url).await;
    let server_key = database::get_or_create_server_key(&pool)
        .await
        .expect("Failed to get or create server key");

    let flag_drive_api_state = FlagDriveAPIState {
        pool: pool.clone(),
        server_key,
    };

    let cleanup_pool = pool.clone();
    tokio::spawn(async move {
        loop {
            if let Err(e) = database::delete_old_data(&cleanup_pool, 12 * 60).await {
                eprintln!("Failed to clean up old users: {}", e);
            }
            tokio::time::sleep(std::time::Duration::from_secs(60)).await;
        }
    });

    let app = Router::new()
        .route("/api/health", get(health_handler))
        .route("/api/auth/register", post(register_new_user))
        .route("/api/auth/login", post(login_as_user))
        .route("/api/token/verify", post(verify_token))
        .route("/api/token/logout", post(logout_token))
        .route("/api/user/{username}", get(get_user_info))
        .route("/api/user/{username}/follow", post(follow_user_action))
        .route("/api/user/{username}/unfollow", post(unfollow_user_action))
        .route("/api/user/{username}/followers", get(get_followers_action))
        .route("/api/user/{username}/following", get(get_following_action))
        .route("/api/gdpr/request", post(gdpr_request_user_data))
        .route(
            "/api/gdpr/download/{user_link}",
            get(gdpr_download_user_data),
        )
        .route(
            "/api/files/{username}",
            get(get_file_list).post(get_file_list),
        )
        .route("/api/file/upload", post(upload_file))
        .route(
            "/api/file/download/{file_id}",
            get(download_file).post(download_file),
        )
        .with_state(flag_drive_api_state)
        .fallback_service(ServeDir::new(&args.dist));

    let listener = tokio::net::TcpListener::bind(&args.addr).await.unwrap();
    println!("Frontend dir: {}", args.dist);
    println!("Listening on: http://{}", args.addr);
    axum::serve(listener, app).await.unwrap();
}

#[derive(Clone)]
pub struct FlagDriveAPIState {
    pub pool: DbPool,
    pub server_key: String,
}

async fn health_handler() -> Json<Value> {
    Json(json!({
        "status": "ok",
        "time": SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map(|d| d.as_secs() as u64)
                    .unwrap_or(0)
    }))
}
