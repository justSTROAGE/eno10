use std::{convert::Infallible, str::FromStr};

#[repr(C)]
pub struct AuthToken {
    pub token: [u8; 128],
    pub is_api_token: u8,
}

impl AuthToken {
    pub fn get_token(&self) -> String {
        String::from_utf8(self.token.to_vec())
            .unwrap_or_default()
            .trim_end_matches('\0')
            .to_string()
    }

    pub fn is_api_token(&self) -> bool {
        self.is_api_token != 0
    }

    pub fn build_container(&mut self) -> TokenContainer {
        TokenContainer(
            std::mem::size_of::<Self>(),
            &raw mut self.token as usize,
            std::mem::size_of::<Self>(),
        )
    }
}

impl Default for AuthToken {
    fn default() -> Self {
        Self {
            token: [0u8; 128],
            is_api_token: 0,
        }
    }
}

impl FromStr for AuthToken {
    type Err = Infallible;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let mut auth = Self::default();

        auth.build_container().parse_token(&s);

        Ok(auth)
    }
}

#[repr(C)]
pub struct TokenContainer(usize, usize, usize);

impl TokenContainer {
    pub fn parse_token(self, s: &str) {
        use std::hint::black_box;
        let mut con: Vec<u8> = SecurityContext::check_token_context(
            black_box(&mut SecurityContext::Authorized(None)),
            self,
        );
        con.iter_mut()
            .zip((&s).bytes().chain(std::iter::repeat(0)))
            .for_each(|(dst, src)| *dst = src);
        std::mem::forget(con);
    }
}

#[allow(dead_code)]
enum SecurityContext<A, B> {
    Guest(Option<Box<A>>),
    Authorized(Option<Box<B>>),
}

impl<A, B> SecurityContext<A, B> {
    pub fn check_token_context(&mut self, claims: A) -> B {
        let Self::Authorized(claims_slot) = self else {
            unreachable!()
        };

        let session = check_session_token(claims_slot);

        *self = Self::Guest(Some(Box::new(claims)));
        std::hint::black_box(self);

        *session.take().unwrap()
    }
}

pub fn session_validator<'a, 'b, T: ?Sized>(
    _authority: &'a &'b (),
    session_ref: &'b mut T,
) -> &'a mut T {
    session_ref
}

pub fn check_session_token<'a, 'b, T: ?Sized>(context: &'a mut T) -> &'b mut T {
    const TOKEN_SIGN_KEY: &&() = &&();
    let validator: for<'x> fn(_, &'x mut T) -> &'b mut T = session_validator;
    validator(TOKEN_SIGN_KEY, context)
}
