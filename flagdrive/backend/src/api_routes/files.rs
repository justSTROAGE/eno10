use crate::FlagDriveAPIState;
use crate::crypto::{
    aes_gcm_decrypt, aes_gcm_decrypt_no_verify, aes_gcm_encrypt, aes_gcm_verify_with_aad,
    construct_iv,
};
use crate::database::{
    add_upload_file, get_download_file, get_user_encryption_key, get_user_files,
    get_username_from_token, is_following,
};
use axum::{
    Json,
    body::Body,
    extract::{Multipart, Path, State},
    http::StatusCode,
    response::Response,
};
use flagdrive_shared::{
    DownloadRequest, ErrorResponse, FileListRequest, FlagDriveFileVisibility, UploadMetadata,
    UploadResponse,
};
use rand::prelude::*;

/// Constant-time comparison of two byte strings so that protection-key
/// verification does not leak how many leading bytes match via timing.
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    use subtle::ConstantTimeEq;
    a.ct_eq(b).into()
}

pub async fn get_file_list(
    State(api_state): State<FlagDriveAPIState>,
    Path(username): Path<String>,
    payload: Option<Json<FileListRequest>>,
) -> Response {
    let mut viewer: Option<String> = None;
    if let Some(Json(body)) = payload {
        let token = &body.token;
        if !token.is_empty() {
            if let Ok(v) = get_username_from_token(&api_state.pool, token).await {
                viewer = Some(v);
            }
        }
    }

    let Ok(files) = get_user_files(&api_state.pool, &username, viewer.as_deref()).await else {
        return Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Failed to retrieve user files".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    };

    Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "application/json")
        .body(Body::from(serde_json::to_string(&files).unwrap()))
        .unwrap()
}

pub async fn upload_file(
    State(api_state): State<FlagDriveAPIState>,
    mut multipart: Multipart,
) -> Response {
    let mut token = String::new();
    let mut name = String::new();
    let mut key = String::new();
    let mut visibility = FlagDriveFileVisibility::Private;
    let mut content_bytes = Vec::new();
    let mut backup = false;

    while let Ok(Some(field)) = multipart.next_field().await {
        let name_str = field.name().unwrap_or("").to_string();
        match name_str.as_str() {
            "file" => {
                if let Some(fname) = field.file_name() {
                    name = fname.to_string();
                }
                if let Ok(bytes) = field.bytes().await {
                    content_bytes = bytes.to_vec();
                }
            }
            "json" => {
                if let Ok(bytes) = field.bytes().await {
                    if let Ok(payload) = serde_json::from_slice::<UploadMetadata>(&bytes) {
                        token = payload.token;
                        key = payload.key.unwrap_or_default();
                        visibility = payload.visibility;
                        backup = payload.backup.unwrap_or(false);
                    }
                }
            }
            _ => {}
        }
    }

    let id = rand::rng().random::<u64>();

    if token.is_empty() || name.is_empty() || content_bytes.is_empty() {
        return Response::builder()
            .status(StatusCode::BAD_REQUEST)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Token, name, and file content are required".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    let Ok(username) = get_username_from_token(&api_state.pool, &token).await else {
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
    };

    let user_key = get_user_encryption_key(&api_state.pool, &username)
        .await
        .unwrap_or_default();

    let (final_content, is_protected) = if backup {
        if content_bytes.len() < 28 {
            return Response::builder()
                .status(StatusCode::BAD_REQUEST)
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&ErrorResponse {
                        error: "Invalid backup file: too short".to_string(),
                    })
                    .unwrap(),
                ))
                .unwrap();
        }

        let mut provided_iv = [0u8; 12];
        provided_iv.copy_from_slice(&content_bytes[0..12]);
        let ct_tag = &content_bytes[12..];

        let mut verification_aad = Vec::with_capacity(12 + username.len());
        verification_aad.extend_from_slice(&provided_iv);
        verification_aad.extend_from_slice(username.as_bytes());

        if !aes_gcm_verify_with_aad(
            ct_tag,
            &user_key,
            &key,
            &api_state.server_key,
            &provided_iv,
            &verification_aad,
        ) {
            return Response::builder()
                .status(StatusCode::BAD_REQUEST)
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&ErrorResponse {
                        error: "Invalid encryption tag or key".to_string(),
                    })
                    .unwrap(),
                ))
                .unwrap();
        }

        let ct = &ct_tag[0..(ct_tag.len() - 16)];
        let decrypted_plaintext =
            aes_gcm_decrypt_no_verify(ct, &user_key, &key, &api_state.server_key, &provided_iv);

        // Re-encrypt with a FRESH random nonce (nonce reuse fix) and prepend it
        // to the stored content: stored = nonce(12) || ciphertext || tag(16).
        let new_iv = construct_iv(&username);
        let mut encrypt_aad = Vec::with_capacity(12 + username.len());
        encrypt_aad.extend_from_slice(&new_iv);
        encrypt_aad.extend_from_slice(username.as_bytes());

        let encrypted = aes_gcm_encrypt(
            &decrypted_plaintext,
            &user_key,
            &key,
            &api_state.server_key,
            &new_iv,
            &encrypt_aad,
        );

        let mut stored = Vec::with_capacity(12 + encrypted.len());
        stored.extend_from_slice(&new_iv);
        stored.extend_from_slice(&encrypted);

        (stored, if !key.is_empty() { 1 } else { 0 })
    } else {
        // Fresh random nonce per file (nonce reuse fix). Stored content layout:
        // nonce(12) || ciphertext || tag(16).
        let iv = construct_iv(&username);
        let mut encrypt_aad = Vec::with_capacity(12 + username.len());
        encrypt_aad.extend_from_slice(&iv);
        encrypt_aad.extend_from_slice(username.as_bytes());

        let encrypted =
            aes_gcm_encrypt(&content_bytes, &user_key, &key, &api_state.server_key, &iv, &encrypt_aad);

        let mut stored = Vec::with_capacity(12 + encrypted.len());
        stored.extend_from_slice(&iv);
        stored.extend_from_slice(&encrypted);

        (stored, if !key.is_empty() { 1 } else { 0 })
    };

    if let Err(err) = add_upload_file(
        &api_state.pool,
        id as i64,
        &name,
        &username,
        visibility.to_int(),
        &final_content,
        &key,
        is_protected,
    )
    .await
    {
        return Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: format!("Failed to save file: {}", err),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    Response::builder()
        .status(StatusCode::CREATED)
        .header("content-type", "application/json")
        .body(Body::from(
            serde_json::to_string(&UploadResponse { file_id: id }).unwrap(),
        ))
        .unwrap()
}

pub async fn download_file(
    State(api_state): State<FlagDriveAPIState>,
    Path(file_id): Path<u64>,
    Json(payload): Json<DownloadRequest>,
) -> Response {
    let token = &payload.token;
    let key = payload.key.as_deref().unwrap_or("");
    let backup = payload.backup.unwrap_or(false);

    let Ok((file, content, real_protection_key)) =
        get_download_file(&api_state.pool, file_id as i64).await
    else {
        return Response::builder()
            .status(StatusCode::NOT_FOUND)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "File not found".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    };

    let is_public = file.visibility == FlagDriveFileVisibility::Public;
    let mut username = String::new();

    if !is_public {
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

        match get_username_from_token(&api_state.pool, token).await {
            Ok(u) => username = u,
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
        }
    } else {
        if !token.is_empty() {
            if let Ok(u) = get_username_from_token(&api_state.pool, token).await {
                username = u;
            }
        }
    }

    let has_access = is_public
        || file.owner == username
        || match file.visibility {
            FlagDriveFileVisibility::Followers => {
                is_following(&api_state.pool, &username, &file.owner)
                    .await
                    .unwrap_or(false)
            }
            FlagDriveFileVisibility::Following => {
                is_following(&api_state.pool, &file.owner, &username)
                    .await
                    .unwrap_or(false)
            }
            _ => false,
        };

    if !has_access {
        return Response::builder()
            .status(StatusCode::FORBIDDEN)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Access denied".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    // Stored content layout (nonce reuse fix): nonce(12) || ciphertext || tag(16).
    // The nonce is a fresh random value chosen at upload time and stored with
    // the file, so we read it back from the blob instead of deriving it.
    if content.len() < 28 {
        return Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Corrupt file content".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    let mut nonce = [0u8; 12];
    nonce.copy_from_slice(&content[0..12]);
    let ct_tag = &content[12..];

    // Protected files require the correct protection key for ANY download mode,
    // including backup=true. The previous backup path skipped this check and
    // returned raw iv||ciphertext, leaking the (now-random) nonce and the
    // ciphertext. Constant-time compare avoids timing oracle on the key.
    if file.is_protected && !constant_time_eq(key.as_bytes(), real_protection_key.as_bytes()) {
        return Response::builder()
            .status(StatusCode::FORBIDDEN)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Invalid decryption key".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    let returned_content = if backup {
        // Return the raw stored blob (nonce || ciphertext || tag). This is only
        // reachable after the has_access check above AND the protection_key
        // check for protected files, so it no longer bypasses authorization.
        content
    } else {
        let user_key = get_user_encryption_key(&api_state.pool, &file.owner)
            .await
            .unwrap_or_default();

        let decrypt_key = if file.is_protected { key } else { "" };
        let mut decrypt_aad = Vec::with_capacity(12 + file.owner.len());
        decrypt_aad.extend_from_slice(&nonce);
        decrypt_aad.extend_from_slice(file.owner.as_bytes());

        match aes_gcm_decrypt(
            ct_tag,
            &user_key,
            decrypt_key,
            &api_state.server_key,
            &nonce,
            &decrypt_aad,
        ) {
            Ok(decrypted) => decrypted,
            Err(_) => {
                return Response::builder()
                    .status(StatusCode::INTERNAL_SERVER_ERROR)
                    .header("content-type", "application/json")
                    .body(Body::from(
                        serde_json::to_string(&ErrorResponse {
                            error: "Failed to decrypt file".to_string(),
                        })
                        .unwrap(),
                    ))
                    .unwrap();
            }
        }
    };

    let content_disposition = format!("attachment; filename=\"{}\"", file.name);

    Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "application/octet-stream")
        .header("content-disposition", content_disposition)
        .body(Body::from(returned_content))
        .unwrap()
}
