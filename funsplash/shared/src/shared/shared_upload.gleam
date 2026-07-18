import formal/form.{type Form}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/string
import gleam/uri
import shared/shared_privacy.{type Privacy}
import youid/uuid.{type Uuid}

pub const max_allowed_size = 1_024_000

pub type MimeType {
  Png
  Jpg
  Webp
  Other
}

pub type Data {
  InMemory(data: BitArray, mimetype: MimeType)
  File(path: String, size: Int)
}

pub type Upload {
  Upload(
    creator: Uuid,
    data: Data,
    description: Option(String),
    privacy: Privacy,
    location: Option(String),
    camera: Option(String),
    show_on_profile: Bool,
    tags: List(String),
  )
}

pub type Error {
  FileMissing
  FileReadError
  InternalError
  InvalidForm
  QuotaExceeded(quota_remaining: Int)
  ImageTooLarge(allowed_size: Int)
  AuthorizationError
}

pub fn error_to_uri(err: Error) -> String {
  err |> error_to_string |> uri.percent_encode
}

pub fn error_to_string(err: Error) -> String {
  case err {
    FileMissing -> "No photo file was selected."
    FileReadError -> "An error occurred while reading the uploaded file."
    InternalError -> "An internal error occurred while saving."
    InvalidForm -> "The form data provided was invalid."
    QuotaExceeded(remaining) ->
      "Storage quota exceeded. You have: "
      <> int.to_string(remaining / 1000)
      <> "KB remaining. Please delete some photos to upload more."
    ImageTooLarge(allowed) ->
      "Image is too large. The maximum allowed size is: "
      <> int.to_string(allowed / 1000)
      <> "KB"
    AuthorizationError -> "Something wrong with your user account"
  }
}

pub fn upload_form(creator: Uuid, data: Data) -> Form(Upload) {
  form.new({
    use _photo_check <- form.field(
      "photo",
      form.parse_optional(form.parse_string)
        |> form.check(fn(val) {
          case data {
            File(_, size) if size > max_allowed_size ->
              Error(
                "Image is too large. The maximum allowed size is: "
                <> int.to_string(max_allowed_size),
              )
            _ -> Ok(val)
          }
        }),
    )

    use description <- form.field(
      "description",
      form.parse_optional(form.parse_string),
    )
    use privacy_str <- form.field("privacy", form.parse_string)
    let privacy = shared_privacy.from_string(privacy_str)
    use location <- form.field(
      "location",
      form.parse_optional(form.parse_string),
    )
    use camera <- form.field("camera", form.parse_optional(form.parse_string))
    use show_on_profile <- form.field("show_on_profile", form.parse_checkbox)

    use tags_str <- form.field("tags", form.parse_optional(form.parse_string))
    let tags =
      string.split(option.unwrap(tags_str, ""), ",")
      |> list.map(string.trim)
      |> list.filter(fn(t) { t != "" })

    form.success(Upload(
      creator:,
      data:,
      description:,
      privacy:,
      location:,
      camera:,
      show_on_profile:,
      tags:,
    ))
  })
}
