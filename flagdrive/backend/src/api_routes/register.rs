use crate::FlagDriveAPIState;
use crate::database::{create_new_token, create_new_user};
use axum::{Json, body::Body, extract::State, http::StatusCode, response::Response};
use flagdrive_shared::{AuthRequest, AuthResponse, ErrorResponse};
use rand::prelude::*;

pub async fn register_new_user(
    State(api_state): State<FlagDriveAPIState>,
    Json(payload): Json<AuthRequest>,
) -> Response {
    let username = payload.username.trim();
    let password = payload.password.trim();

    if username.is_empty() || password.is_empty() {
        return Response::builder()
            .status(StatusCode::BAD_REQUEST)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Username and password are required".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    let encryption_key = rand::rng()
        .sample_iter(&rand::distr::Alphanumeric)
        .take(256)
        .map(char::from)
        .collect::<String>();

    if create_new_user(&api_state.pool, username, password, &encryption_key)
        .await
        .is_err()
    {
        return Response::builder()
            .status(StatusCode::CONFLICT)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "User already exists".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    let Ok(token) = create_new_token(&api_state.pool, username).await else {
        return Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Failed to generate secure session token".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    };

    Response::builder()
        .status(StatusCode::CREATED)
        .header("content-type", "application/json")
        .body(Body::from(
            serde_json::to_string(&AuthResponse {
                token,
                username: username.to_string(),
            })
            .unwrap(),
        ))
        .unwrap()
}
