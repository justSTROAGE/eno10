import formal/form.{type Form}
import gleam/option.{type Option}
import gleam/uri

pub type Error {
  InvalidData
  UsernameExists
  InternalError
}

pub fn error_to_string(err: Error) -> String {
  case err {
    InvalidData -> "Invalid Data"
    UsernameExists -> "Username is already taken"
    InternalError -> "Internal Error"
  }
}

pub fn error_to_uri(err: Error) -> String {
  err |> error_to_string |> uri.percent_encode
}

pub type User {
  UpdateUser(
    username: String,
    first_name: String,
    last_name: Option(String),
    bio: Option(String),
    available_for_hire: Bool,
  )
}

pub type ChangePasswordForm {
  ChangePasswordForm(old: String, new: String, confirm: String)
}

pub fn edit_form() -> Form(User) {
  form.new({
    use username <- form.field(
      "username",
      form.parse_string |> form.check_not_empty,
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
    form.success(UpdateUser(
      username:,
      first_name:,
      last_name:,
      bio:,
      available_for_hire:,
    ))
  })
}

pub fn change_password_form() -> Form(ChangePasswordForm) {
  form.new({
    use old <- form.field(
      "old_password",
      form.parse_string |> form.check_string_length_more_than(4),
    )
    use new <- form.field(
      "new_password",
      form.parse_string |> form.check_string_length_more_than(4),
    )

    use confirm <- form.field(
      "confirm",
      form.parse_string
        |> form.check(fn(confirm) {
          case confirm == new {
            True -> Ok(confirm)
            False -> Error("passwords don't match")
          }
        }),
    )

    form.success(ChangePasswordForm(old:, new:, confirm:))
  })
}
