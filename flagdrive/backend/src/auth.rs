use std::{convert::Infallible, str::FromStr};

/// Maximum length of a session token. Session tokens are generated as
/// 128 alphanumeric characters (see database::users::create_new_token).
/// Any input longer than this is rejected outright so that a client can
/// never overflow an internal buffer or set a privileged flag.
pub const TOKEN_MAX_LEN: usize = 128;

/// A parsed session token.
///
/// This is a plain, safe Rust struct. There is intentionally no
/// `is_api_token` field or `repr(C)` layout: the previous implementation
/// used a `repr(C)` { token:[u8;128], is_api_token:u8 } buffer that could
/// be overflowed by a 129-byte token string, letting a client set the
/// `is_api_token` byte and bypass the follow/unfollow authorization check.
/// The "api token" concept does not exist anywhere else in the codebase, so
/// the privileged path is removed entirely.
#[derive(Default)]
pub struct AuthToken {
    token: String,
}

impl AuthToken {
    /// Returns the trimmed token string for DB lookup.
    pub fn get_token(&self) -> String {
        self.token.trim_end_matches('\0').to_string()
    }

    /// There is no longer any "api token" concept. Always false.
    #[allow(dead_code)]
    pub fn is_api_token(&self) -> bool {
        false
    }
}

impl FromStr for AuthToken {
    type Err = Infallible;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        // Bounds check: reject any token longer than the legitimate 128-char
        // length. This is the one-byte overflow fix: previously a 129+ byte
        // input overwrote the is_api_token byte. Returning an empty token makes
        // the subsequent DB lookup fail (401 Unauthorized) for any overlong
        // input, so the follow/unfollow bypass is impossible. We never copy
        // more than TOKEN_MAX_LEN bytes and never write past token storage.
        if s.len() > TOKEN_MAX_LEN {
            return Ok(Self::default());
        }

        Ok(Self {
            token: s.to_string(),
        })
    }
}
