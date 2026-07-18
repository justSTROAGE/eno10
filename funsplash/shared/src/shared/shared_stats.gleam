import gleam/dynamic/decode
import gleam/json
import shared/shared_thumbnail

pub type Stats {
  Stats(views: Int, likes: Int, downloads: Int)
}

pub fn stats_to_json(stats: Stats) -> json.Json {
  let Stats(views:, likes:, downloads:) = stats
  json.object([
    #("views", json.int(views)),
    #("likes", json.int(likes)),
    #("downloads", json.int(downloads)),
  ])
}

pub fn stats_decoder() -> decode.Decoder(Stats) {
  use views <- decode.field("views", decode.int)
  use likes <- decode.field("likes", decode.int)
  use downloads <- decode.field("downloads", decode.int)
  decode.success(Stats(views:, likes:, downloads:))
}

pub type StatsThumbnail {
  StatsThumbnail(thumbnail: shared_thumbnail.Thumbnail, stats: Stats)
}

pub fn stats_thumbnail_to_json(stats_thumbnail: StatsThumbnail) -> json.Json {
  let StatsThumbnail(thumbnail:, stats:) = stats_thumbnail
  json.object([
    #("thumbnail", shared_thumbnail.thumbnail_to_json(thumbnail)),
    #("stats", stats_to_json(stats)),
  ])
}

pub fn stats_thumbnail_decoder() -> decode.Decoder(StatsThumbnail) {
  use thumbnail <- decode.field(
    "thumbnail",
    shared_thumbnail.thumbnail_decoder(),
  )
  use stats <- decode.field("stats", stats_decoder())
  decode.success(StatsThumbnail(thumbnail:, stats:))
}
