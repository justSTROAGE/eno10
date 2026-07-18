use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum FlagDriveFileVisibility {
    Private,
    Public,
    Following,
    Followers,
}

impl FlagDriveFileVisibility {
    pub fn to_int(&self) -> i32 {
        match self {
            Self::Private => 0,
            Self::Public => 1,
            Self::Following => 2,
            Self::Followers => 3,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FlagDriveFile {
    pub id: u64,
    pub name: String,
    pub owner: String,
    pub visibility: FlagDriveFileVisibility,
    pub size: u64,
    pub created_at: u64,
    #[serde(rename = "protected")]
    pub is_protected: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FlagDriveUser {
    pub username: String,
    pub followers_count: usize,
    pub following_count: usize,
    pub is_followed: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AuthRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AuthResponse {
    pub token: String,
    pub username: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ErrorResponse {
    pub error: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TokenRequest {
    pub token: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TokenVerifyResponse {
    pub username: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SuccessMessageResponse {
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UserInfoRequest {
    pub username: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FollowRequest {
    pub token: String,
    pub username: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FollowResponse {
    pub status: String,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FollowersResponse {
    pub followers: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FollowingResponse {
    pub following: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GdprRequest {
    pub token: String,
    pub username: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GdprRequestResponse {
    pub gdpr_id: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GdprExportData {
    pub exported_at: u64,
    pub username: String,
    pub files: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FileListRequest {
    pub token: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UploadMetadata {
    pub token: String,
    #[serde(default)]
    pub key: Option<String>,
    pub visibility: FlagDriveFileVisibility,
    #[serde(default)]
    pub backup: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UploadResponse {
    pub file_id: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DownloadRequest {
    #[serde(default)]
    pub token: String,
    #[serde(default)]
    pub key: Option<String>,
    #[serde(default)]
    pub backup: Option<bool>,
}
