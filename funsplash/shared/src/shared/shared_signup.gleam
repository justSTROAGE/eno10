import formal/form.{type Form}
import gleam/option.{type Option}
import gleam/uri

pub type Error {
  InvalidData
  UserExists
  InternalError
}

pub fn error_to_string(err: Error) -> String {
  case err {
    InvalidData -> "Invalid form data"
    InternalError -> "Internal Error"
    UserExists -> "User exists"
  }
}

pub fn error_to_uri(err: Error) -> String {
  err |> error_to_string |> uri.percent_encode
}

pub type SignUpForm {
  SignUpForm(
    username: String,
    password: String,
    first_name: String,
    last_name: Option(String),
    bio: Option(String),
    available_for_hire: Bool,
  )
}

pub fn form() -> Form(SignUpForm) {
  form.new({
    use username <- form.field(
      "username",
      form.parse_string |> form.check_not_empty,
    )
    use password <- form.field(
      "password",
      form.parse_string
        |> form.check_string_length_more_than(4),
    )
    use first_name <- form.field(
      "first_name",
      form.parse_string |> form.check_not_empty,
    )
    use last_name <- form.field(
      "last_name",
      form.parse_string |> form.parse_optional,
    )
    use bio <- form.field("bio", form.parse_string |> form.parse_optional)
    use available_for_hire <- form.field(
      "available_for_hire",
      form.parse_checkbox,
    )
    form.success(SignUpForm(
      username:,
      password:,
      first_name:,
      last_name:,
      bio:,
      available_for_hire:,
    ))
  })
}
