import formal/form
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string
import shared/shared_privacy
import shared/shared_stats
import shared/shared_thumbnail

pub type Photo {
  Photo(
    thumbnail: shared_thumbnail.Thumbnail,
    stats: shared_stats.Stats,
    description: Option(String),
    location: Option(String),
    camera: Option(String),
    created_at: Float,
    tags: List(String),
  )
}

pub fn photo_to_json(photo: Photo) -> json.Json {
  let Photo(
    thumbnail:,
    stats:,
    description:,
    location:,
    camera:,
    created_at:,
    tags:,
  ) = photo
  json.object([
    #("thumbnail", shared_thumbnail.thumbnail_to_json(thumbnail)),
    #("stats", shared_stats.stats_to_json(stats)),
    #("description", case description {
      option.None -> json.null()
      option.Some(value) -> json.string(value)
    }),
    #("location", case location {
      option.None -> json.null()
      option.Some(value) -> json.string(value)
    }),
    #("camera", case camera {
      option.None -> json.null()
      option.Some(value) -> json.string(value)
    }),
    #("created_at", json.float(created_at)),
    #("tags", json.array(tags, json.string)),
  ])
}

pub fn photo_decoder() -> decode.Decoder(Photo) {
  use thumbnail <- decode.field(
    "thumbnail",
    shared_thumbnail.thumbnail_decoder(),
  )
  use stats <- decode.field("stats", shared_stats.stats_decoder())
  use description <- decode.field("description", decode.optional(decode.string))
  use location <- decode.field("location", decode.optional(decode.string))
  use camera <- decode.field("camera", decode.optional(decode.string))
  use created_at <- decode.field("created_at", decode.float)
  use tags <- decode.field("tags", decode.list(decode.string))

  decode.success(Photo(
    thumbnail:,
    stats:,
    description:,
    location:,
    camera:,
    created_at:,
    tags:,
  ))
}

pub type PhotoUpdateRequest {
  PhotoUpdateRequest(
    description: String,
    location: String,
    camera: String,
    privacy: shared_privacy.Privacy,
    show_on_profile: Bool,
    tags: List(String),
  )
}

pub fn photo_update_form() -> form.Form(PhotoUpdateRequest) {
  form.new({
    use description <- form.field(
      "description",
      form.parse_optional(form.parse_string),
    )
    use location <- form.field(
      "location",
      form.parse_optional(form.parse_string),
    )
    use camera <- form.field("camera", form.parse_optional(form.parse_string))
    use privacy_str <- form.field("privacy", form.parse_string)
    let privacy = shared_privacy.from_string(privacy_str)

    use show_on_profile <- form.field("show_on_profile", form.parse_checkbox)
    use tags_str <- form.field("tags", form.parse_optional(form.parse_string))
    let tags =
      string.split(option.unwrap(tags_str, ""), ",")
      |> list.map(string.trim)
      |> list.filter(fn(t) { t != "" })

    form.success(PhotoUpdateRequest(
      description: option.unwrap(description, ""),
      location: option.unwrap(location, ""),
      camera: option.unwrap(camera, ""),
      privacy:,
      show_on_profile:,
      tags:,
    ))
  })
}
