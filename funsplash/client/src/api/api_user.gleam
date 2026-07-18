import api/api_photo
import gleam/dynamic/decode
import gleam/uri
import lustre/effect.{type Effect}
import rsvp
import shared/shared_collection
import shared/shared_thumbnail
import shared/shared_user

pub fn fetch(
  username: String,
  on_response: fn(Result(shared_user.User, rsvp.Error(String))) -> message,
) -> Effect(message) {
  let url = api_photo.api_base_url() <> "/users/" <> username
  let handler = rsvp.expect_json(shared_user.user_decoder(), on_response)
  rsvp.get(url, handler)
}

pub fn fetch_photos(
  username: String,
  on_response: fn(Result(List(shared_thumbnail.Thumbnail), rsvp.Error(String))) ->
    message,
) -> Effect(message) {
  let url = api_photo.api_base_url() <> "/users/" <> username <> "/photos"
  let handler =
    rsvp.expect_json(
      decode.list(shared_thumbnail.thumbnail_decoder()),
      on_response,
    )
  rsvp.get(url, handler)
}

pub fn fetch_collections(
  username: String,
  on_response: fn(
    Result(List(shared_collection.Collection), rsvp.Error(String)),
  ) -> message,
) -> Effect(message) {
  let url = api_photo.api_base_url() <> "/users/" <> username <> "/collections"
  let handler =
    rsvp.expect_json(
      decode.list(shared_collection.collection_decoder()),
      on_response,
    )
  rsvp.get(url, handler)
}

pub fn search(
  query: String,
  on_response: fn(Result(List(shared_user.User), rsvp.Error(String))) -> message,
) -> Effect(message) {
  let url =
    api_photo.api_base_url()
    <> shared_user.search_uri
    <> uri.percent_encode(query)
  let handler =
    rsvp.expect_json(decode.list(shared_user.user_decoder()), on_response)
  rsvp.get(url, handler)
}
