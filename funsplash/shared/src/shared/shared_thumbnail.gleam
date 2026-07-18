import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option}
import shared/shared_collection
import shared/shared_privacy.{type Privacy}
import shared/shared_user

pub type Thumbnail {
  Thumbnail(
    public_id: String,
    asset_id: String,
    description: Option(String),
    creator: shared_user.User,
    privacy: Privacy,
    user_liked: Bool,
    show_on_profile: Bool,
    current_user_collections: List(shared_collection.PublicId),
  )
}

pub fn thumbnail_to_json(thumbnail: Thumbnail) -> json.Json {
  let Thumbnail(
    public_id:,
    asset_id:,
    description:,
    creator:,
    privacy:,
    user_liked:,
    show_on_profile:,
    current_user_collections:,
  ) = thumbnail
  json.object([
    #("public_id", json.string(public_id)),
    #("asset_id", json.string(asset_id)),
    #("description", case description {
      option.None -> json.null()
      option.Some(value) -> json.string(value)
    }),
    #("creator", shared_user.user_to_json(creator)),
    #("privacy", shared_privacy.privacy_to_json(privacy)),
    #("user_liked", json.bool(user_liked)),
    #("show_on_profile", json.bool(show_on_profile)),
    #(
      "current_user_collections",
      json.array(current_user_collections, json.string),
    ),
  ])
}

pub fn thumbnail_decoder() -> decode.Decoder(Thumbnail) {
  use public_id <- decode.field("public_id", decode.string)
  use asset_id <- decode.field("asset_id", decode.string)
  use description <- decode.field("description", decode.optional(decode.string))
  use creator <- decode.field("creator", shared_user.user_decoder())
  use privacy <- decode.field("privacy", shared_privacy.privacy_decoder())
  use user_liked <- decode.field("user_liked", decode.bool)
  use show_on_profile <- decode.field("show_on_profile", decode.bool)
  use current_user_collections <- decode.field(
    "current_user_collections",
    decode.list(decode.string),
  )
  decode.success(Thumbnail(
    public_id:,
    asset_id:,
    description:,
    creator:,
    privacy:,
    user_liked:,
    show_on_profile:,
    current_user_collections:,
  ))
}
