import shared/shared_user

pub type Auth {
  LoggedIn(shared_user.User)
  LoggedOut
  Unknown
}

pub fn is_logged_in(auth: Auth) -> Bool {
  case auth {
    LoggedIn(_) -> True
    _ -> False
  }
}
