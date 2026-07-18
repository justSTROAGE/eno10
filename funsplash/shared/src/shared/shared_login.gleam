import formal/form.{type Form}
import gleam/uri

pub type LoginForm {
  LoginForm(username: String, password: String)
}

pub fn form() -> Form(LoginForm) {
  form.new({
    use username <- form.field(
      "username",
      form.parse_string |> form.check_not_empty,
    )
    use password <- form.field(
      "password",
      form.parse_string |> form.check_not_empty,
    )
    form.success(LoginForm(username:, password:))
  })
}

pub type Error {
  InvalidData
  UserNotFound
  InvalidCredentials
  InternalError
}

pub fn error_to_uri(err: Error) -> String {
  err |> error_to_string |> uri.percent_encode
}

pub fn error_to_string(err: Error) -> String {
  case err {
    InvalidData -> "Invalid data"
    InternalError -> "Internal Error"
    UserNotFound -> "User not found"
    InvalidCredentials -> "Username or Password wrong"
  }
}
