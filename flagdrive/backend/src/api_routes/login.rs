use crate::FlagDriveAPIState;
use crate::database::{check_user_password, create_new_token};
use axum::{Json, body::Body, extract::State, http::StatusCode, response::Response};
use flagdrive_shared::{AuthRequest, AuthResponse, ErrorResponse};

pub async fn login_as_user(
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

    if !check_user_password(&api_state.pool, username, password)
        .await
        .unwrap_or(false)
    {
        return Response::builder()
            .status(StatusCode::UNAUTHORIZED)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Invalid credentials".to_string(),
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
        .status(StatusCode::OK)
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
