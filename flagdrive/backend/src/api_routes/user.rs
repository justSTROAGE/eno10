use crate::FlagDriveAPIState;
use crate::auth::AuthToken;
use crate::database::{
    follow_user, get_followers_list, get_following_list, get_user_by_username,
    get_username_from_token, is_following, unfollow_user,
};
use axum::{
    Json,
    body::Body,
    extract::{Path, State},
    http::StatusCode,
    response::Response,
};
use flagdrive_shared::{
    ErrorResponse, FollowRequest, FollowResponse, FollowersResponse, FollowingResponse,
    UserInfoRequest,
};

pub async fn get_user_info(
    State(api_state): State<FlagDriveAPIState>,
    Path(viewer_username): Path<String>,
    payload: Option<Json<UserInfoRequest>>,
) -> Response {
    let viewed_username = payload
        .as_ref()
        .and_then(|Json(p)| p.username.as_deref())
        .unwrap_or(&viewer_username);

    let Ok(user) =
        get_user_by_username(&api_state.pool, viewed_username, Some(&viewer_username)).await
    else {
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
    };

    Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "application/json")
        .body(Body::from(serde_json::to_string(&user).unwrap()))
        .unwrap()
}

pub async fn follow_user_action(
    State(api_state): State<FlagDriveAPIState>,
    Path(target_username): Path<String>,
    Json(payload): Json<FollowRequest>,
) -> Response {
    let token = &payload.token;
    let followee = &payload.username;

    if token.is_empty() || followee.is_empty() {
        return Response::builder()
            .status(StatusCode::BAD_REQUEST)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Token and username are required".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    let auth_token: AuthToken = token.parse().unwrap_or_default();

    let Ok(username_from_token) =
        get_username_from_token(&api_state.pool, &auth_token.get_token()).await
    else {
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

    // Authorization: the authenticated user (resolved from the token) must be
    // the same user named in the path. The previous code allowed a client-set
    // `is_api_token` flag to bypass this check (see auth.rs overflow fix); the
    // "api token" concept does not exist, so the bypass is removed entirely.
    // The target_username (the user performing the follow) must always equal
    // the username resolved from the token.
    if username_from_token != target_username {
        return Response::builder()
            .status(StatusCode::FORBIDDEN)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Unauthorized action".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    if get_user_by_username(&api_state.pool, followee, None)
        .await
        .is_err()
    {
        return Response::builder()
            .status(StatusCode::NOT_FOUND)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "User to follow not found".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    if target_username == *followee {
        return Response::builder()
            .status(StatusCode::BAD_REQUEST)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "You cannot follow yourself".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    match is_following(&api_state.pool, &target_username, followee).await {
        Ok(true) => {
            return Response::builder()
                .status(StatusCode::BAD_REQUEST)
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&ErrorResponse {
                        error: format!("You already follow {}", followee),
                    })
                    .unwrap(),
                ))
                .unwrap();
        }
        Err(_) => {
            return Response::builder()
                .status(StatusCode::INTERNAL_SERVER_ERROR)
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&ErrorResponse {
                        error: "Database error checking relationship".to_string(),
                    })
                    .unwrap(),
                ))
                .unwrap();
        }
        Ok(false) => {}
    }

    if follow_user(&api_state.pool, &target_username, followee)
        .await
        .is_err()
    {
        return Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Failed to follow user".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "application/json")
        .body(Body::from(
            serde_json::to_string(&FollowResponse {
                status: "success".to_string(),
                message: format!("You are now following {}", followee),
            })
            .unwrap(),
        ))
        .unwrap()
}

pub async fn unfollow_user_action(
    State(api_state): State<FlagDriveAPIState>,
    Path(target_username): Path<String>,
    Json(payload): Json<FollowRequest>,
) -> Response {
    let token = &payload.token;
    let followee = &payload.username;

    if token.is_empty() || followee.is_empty() {
        return Response::builder()
            .status(StatusCode::BAD_REQUEST)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Token and username are required".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    let auth_token: AuthToken = token.parse().unwrap_or_default();

    let Ok(username_from_token) =
        get_username_from_token(&api_state.pool, &auth_token.get_token()).await
    else {
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

    // Authorization: the authenticated user (resolved from the token) must be
    // the same user named in the path. The client-influenceable `is_api_token`
    // bypass is removed entirely (see auth.rs overflow fix). The target user
    // performing the unfollow must always equal the token's user.
    if username_from_token != target_username {
        return Response::builder()
            .status(StatusCode::FORBIDDEN)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Unauthorized action".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    match is_following(&api_state.pool, &target_username, followee).await {
        Ok(false) => {
            return Response::builder()
                .status(StatusCode::BAD_REQUEST)
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&ErrorResponse {
                        error: format!("You do not follow {}", followee),
                    })
                    .unwrap(),
                ))
                .unwrap();
        }
        Err(_) => {
            return Response::builder()
                .status(StatusCode::INTERNAL_SERVER_ERROR)
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&ErrorResponse {
                        error: "Database error checking relationship".to_string(),
                    })
                    .unwrap(),
                ))
                .unwrap();
        }
        Ok(true) => {}
    }

    if unfollow_user(&api_state.pool, &target_username, followee)
        .await
        .is_err()
    {
        return Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Failed to unfollow user".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    }

    Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "application/json")
        .body(Body::from(
            serde_json::to_string(&FollowResponse {
                status: "success".to_string(),
                message: format!("You have unfollowed {}", followee),
            })
            .unwrap(),
        ))
        .unwrap()
}

pub async fn get_followers_action(
    State(api_state): State<FlagDriveAPIState>,
    Path(username): Path<String>,
) -> Response {
    let Ok(followers) = get_followers_list(&api_state.pool, &username).await else {
        return Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Database error retrieving followers".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    };

    Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "application/json")
        .body(Body::from(
            serde_json::to_string(&FollowersResponse { followers }).unwrap(),
        ))
        .unwrap()
}

pub async fn get_following_action(
    State(api_state): State<FlagDriveAPIState>,
    Path(username): Path<String>,
) -> Response {
    let Ok(following) = get_following_list(&api_state.pool, &username).await else {
        return Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::to_string(&ErrorResponse {
                    error: "Database error retrieving following list".to_string(),
                })
                .unwrap(),
            ))
            .unwrap();
    };

    Response::builder()
        .status(StatusCode::OK)
        .header("content-type", "application/json")
        .body(Body::from(
            serde_json::to_string(&FollowingResponse { following }).unwrap(),
        ))
        .unwrap()
}
