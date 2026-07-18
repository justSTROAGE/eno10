import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option}
import gleam/uri

pub const search_uri = "/s/users/"

pub type User {
  User(
    username: String,
    first_name: String,
    last_name: Option(String),
    bio: Option(String),
    available_for_hire: Bool,
    premium: Bool,
  )
}

pub type Error {
  LoggedOut
  Invalid
  NotFound
  PhotosNotFound
  Unauthorized
  RequireLogin
}

pub fn error_to_string(err: Error) -> String {
  case err {
    Unauthorized -> "Unauthorized"
    RequireLogin -> "You need to be logged in"
    Invalid -> "Invalid user data"
    NotFound -> "User doesn't exist"
    PhotosNotFound -> "Users photos weren't found"
    LoggedOut -> "You are logged out"
  }
}

pub fn error_to_uri(err: Error) -> String {
  err |> error_to_string |> uri.percent_encode
}

pub fn user_to_json(user: User) -> json.Json {
  let User(
    username:,
    first_name:,
    last_name:,
    bio:,
    available_for_hire:,
    premium:,
  ) = user
  json.object([
    #("username", json.string(username)),
    #("first_name", json.string(first_name)),
    #("last_name", case last_name {
      option.None -> json.null()
      option.Some(value) -> json.string(value)
    }),
    #("bio", case bio {
      option.None -> json.null()
      option.Some(value) -> json.string(value)
    }),
    #("available_for_hire", json.bool(available_for_hire)),
    #("premium", json.bool(premium)),
  ])
}

pub fn user_decoder() -> decode.Decoder(User) {
  use username <- decode.field("username", decode.string)
  use first_name <- decode.field("first_name", decode.string)
  use last_name <- decode.field("last_name", decode.optional(decode.string))
  use bio <- decode.field("bio", decode.optional(decode.string))
  use available_for_hire <- decode.field("available_for_hire", decode.bool)
  use premium <- decode.field("premium", decode.bool)
  decode.success(User(
    username:,
    first_name:,
    last_name:,
    bio:,
    available_for_hire:,
    premium:,
  ))
}
