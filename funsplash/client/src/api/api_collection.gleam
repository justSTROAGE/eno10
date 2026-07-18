import browser
import gleam/dynamic/decode
import gleam/json
import lustre/effect.{type Effect}
import rsvp
import shared/shared_collection
import shared/shared_thumbnail

pub fn api_base_url() -> String {
  browser.window_location_origin() <> "/napi"
}

pub fn fetch(
  id: String,
  on_response: fn(Result(shared_collection.Collection, rsvp.Error(String))) ->
    message,
) -> Effect(message) {
  let url = api_base_url() <> "/collections/" <> id
  let decoder = shared_collection.collection_decoder()
  let handler = rsvp.expect_json(decoder, on_response)
  rsvp.get(url, handler)
}

pub fn fetch_photos(
  id: String,
  on_response: fn(Result(List(shared_thumbnail.Thumbnail), rsvp.Error(String))) ->
    message,
) -> Effect(message) {
  let url = api_base_url() <> "/collections/" <> id <> "/photos"
  let decoder = decode.list(shared_thumbnail.thumbnail_decoder())
  let handler = rsvp.expect_json(decoder, on_response)
  rsvp.get(url, handler)
}

pub fn add_photo(
  collection_id: String,
  photo_public_id: String,
  on_response: fn(Result(Nil, rsvp.Error(String))) -> message,
) -> Effect(message) {
  let url =
    api_base_url()
    <> "/collections/"
    <> collection_id
    <> "/photos/"
    <> photo_public_id
  let handler =
    rsvp.expect_text(fn(res) {
      case res {
        Ok(_) -> on_response(Ok(Nil))
        Error(e) -> on_response(Error(e))
      }
    })
  rsvp.post(url, json.object([]), handler)
}

pub fn remove_photo(
  collection_id: String,
  photo_public_id: String,
  on_response: fn(Result(Nil, rsvp.Error(String))) -> message,
) -> Effect(message) {
  let url =
    api_base_url()
    <> "/collections/"
    <> collection_id
    <> "/photos/"
    <> photo_public_id
  let handler =
    rsvp.expect_text(fn(res) {
      case res {
        Ok(_) -> on_response(Ok(Nil))
        Error(e) -> on_response(Error(e))
      }
    })
  // Let's hope rsvp.delete exists. We grepped it earlier and it does!
  rsvp.delete(url, json.object([]), handler)
}

pub fn delete_collection(
  id: String,
  on_response: fn(Result(Nil, rsvp.Error(String))) -> message,
) -> Effect(message) {
  let url = api_base_url() <> "/collections/" <> id
  let handler =
    rsvp.expect_text(fn(res) {
      case res {
        Ok(_) -> on_response(Ok(Nil))
        Error(e) -> on_response(Error(e))
      }
    })
  rsvp.delete(url, json.object([]), handler)
}
