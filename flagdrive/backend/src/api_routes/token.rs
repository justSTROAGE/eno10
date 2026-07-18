use crate::FlagDriveAPIState;
use crate::database::{delete_token, get_username_from_token};
use axum::{Json, body::Body, extract::State, http::StatusCode, response::Response};
use flagdrive_shared::{ErrorResponse, SuccessMessageResponse, TokenRequest, TokenVerifyResponse};

pub async fn verify_token(
    State(state): State<FlagDriveAPIState>,
    Json(payload): Json<TokenRequest>,
) -> Response {
    let token = &payload.token;

    match get_username_from_token(&state.pool, token).await {
        Ok(username) => Response::builder()
            .status(StatusCode::OK)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&TokenVerifyResponse { username }).unwrap(),
            ))
            .unwrap(),
        Err(_) => Response::builder()
            .status(StatusCode::UNAUTHORIZED)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Invalid token".to_string(),
                })
                .unwrap(),
            ))
            .unwrap(),
    }
}

pub async fn logout_token(
    State(state): State<FlagDriveAPIState>,
    Json(payload): Json<TokenRequest>,
) -> Response {
    let token = &payload.token;

    if get_username_from_token(&state.pool, token).await.is_err() {
        return Response::builder()
            .status(StatusCode::UNAUTHORIZED)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Invalid token".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    if delete_token(&state.pool, token).await.is_err() {
        return Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Failed to delete token".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "application/json")
        .body(Body::from(
            serde_json::to_string(&SuccessMessageResponse {
                message: "Logged out successfully".to_string(),
            })
            .unwrap(),
        ))
        .unwrap()
}
