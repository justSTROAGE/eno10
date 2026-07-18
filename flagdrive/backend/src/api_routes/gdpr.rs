use crate::{
    FlagDriveAPIState,
    database::{
        get_gdpr_data, get_user_by_username, get_user_files, get_username_from_token,
        insert_gdpr_data,
    },
};
use axum::{
    Json,
    body::Body,
    extract::{Path, State},
    http::StatusCode,
    response::Response,
};
use flagdrive_shared::{ErrorResponse, GdprExportData, GdprRequest, GdprRequestResponse};
use rand::prelude::*;
use std::time::{SystemTime, UNIX_EPOCH};

pub async fn gdpr_request_user_data(
    State(api_state): State<FlagDriveAPIState>,
    Json(payload): Json<GdprRequest>,
) -> Response {
    let token = &payload.token;
    if token.is_empty() {
        return Response::builder()
            .status(StatusCode::BAD_REQUEST)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Token is required".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    let username = match get_username_from_token(&api_state.pool, token).await {
        Ok(name) => name,
        Err(_) => {
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
    };

    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as u64)
        .unwrap_or(0);

    let nonce: String =
        std::iter::repeat_with(|| *b"0123456789abcdef".choose(&mut rand::rng()).unwrap() as char)
            .take(32)
            .collect();

    let filenames: Vec<String> = get_user_files(&api_state.pool, &username, Some(&username))
        .await
        .unwrap_or_default()
        .into_iter()
        .map(|f| f.name)
        .collect();

    let content_str = serde_json::to_string(&GdprExportData {
        exported_at: timestamp,
        username: username.clone(),
        files: filenames,
    })
    .unwrap();

    let gdpr_id = format!("{}-{}-{}", &username, timestamp, &nonce);

    if insert_gdpr_data(
        &api_state.pool,
        &username,
        timestamp as i64,
        &nonce,
        &content_str,
    )
    .await
    .is_err()
    {
        return Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Failed to store GDPR request in database".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "application/json")
        .body(Body::from(
            serde_json::to_string(&GdprRequestResponse { gdpr_id }).unwrap(),
        ))
        .unwrap()
}

pub async fn gdpr_download_user_data(
    State(api_state): State<FlagDriveAPIState>,
    Path(gdpr_id): Path<String>,
) -> Response {
    let parts: Vec<&str> = gdpr_id.split('-').collect();
    if parts.len() < 3 {
        return Response::builder()
            .status(StatusCode::BAD_REQUEST)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Invalid GDPR ID format".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    let username = parts[0];
    let timestamp_or_latest = parts[1];
    let nonce = parts[2];

    if get_user_by_username(&api_state.pool, username, None)
        .await
        .is_err()
    {
        return Response::builder()
            .status(StatusCode::NOT_FOUND)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "User not found".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    if nonce.is_empty() || !nonce.chars().all(|c| c.is_ascii_hexdigit()) {
        return Response::builder()
            .status(StatusCode::NOT_FOUND)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Invalid GDPR ID format".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    let Ok(content_str) =
        get_gdpr_data(&api_state.pool, username, timestamp_or_latest, nonce).await
    else {
        return Response::builder()
            .status(StatusCode::NOT_FOUND)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "GDPR export request not found or expired".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    };

    Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "application/json")
        .header(
            "content-disposition",
            "attachment; filename=\"gdpr_export.json\"",
        )
        .body(Body::from(content_str))
        .unwrap()
}
