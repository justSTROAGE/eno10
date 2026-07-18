import auth
import browser
import gleam/int
import gleam/json
import lustre/effect.{type Effect}
import rsvp
import shared/shared_error
import shared/shared_photo
import shared/shared_privacy.{Premium, Private, Public}
import shared/shared_thumbnail

pub fn api_base_url() -> String {
  browser.window_location_origin() <> "/napi"
}

pub fn images_base_url() -> String {
  browser.window_location_origin() <> "/images"
}

pub fn fetch_thumbnail(
  on_response: fn(Result(shared_photo.Photo, rsvp.Error(shared_error.ApiError))) ->
    message,
) -> Effect(message) {
  todo
}

pub fn fetch_stats(
  on_response: fn(Result(shared_photo.Photo, rsvp.Error(shared_error.ApiError))) ->
    message,
) -> Effect(message) {
  todo
}

pub fn fetch(
  id: String,
  on_response: fn(Result(shared_photo.Photo, rsvp.Error(String))) -> message,
) -> Effect(message) {
  let url = api_base_url() <> "/photos/" <> id
  let decoder = shared_photo.photo_decoder()
  let handler = rsvp.expect_json(decoder, on_response)
  rsvp.get(url, handler)
}

pub fn like(
  public_id: String,
  is_like: Bool,
  on_response: fn(Result(Nil, rsvp.Error(String))) -> message,
) -> Effect(message) {
  let url = api_base_url() <> "/like/" <> public_id
  let handler =
    rsvp.expect_text(fn(res) {
      case res {
        Ok(_) -> on_response(Ok(Nil))
        Error(e) -> on_response(Error(e))
      }
    })

  // Note: RSVP uses empty body for POST
  case is_like {
    True -> rsvp.post(url, json.object([]), handler)
    False -> rsvp.delete(url, json.object([]), handler)
  }
}

pub fn data_url(thumb: shared_thumbnail.Thumbnail) {
  case thumb.privacy {
    Private -> "/images/private_photo-" <> thumb.asset_id
    Premium -> "/images/premium_photo-" <> thumb.asset_id
    Public -> "/images/photo-" <> thumb.asset_id
  }
}

pub fn src_url(
  thumb: shared_thumbnail.Thumbnail,
  current_auth: auth.Auth,
) -> String {
  let is_owner = case current_auth {
    auth.LoggedIn(user) -> user.username == thumb.creator.username
    _ -> False
  }

  case thumb.privacy {
    Private if !is_owner ->
      "data:image/svg+xml;utf8,<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"800\" height=\"600\"><rect width=\"800\" height=\"600\" fill=\"%23e5e7eb\"/><text x=\"50%\" y=\"50%\" dominant-baseline=\"middle\" text-anchor=\"middle\" font-size=\"60\" fill=\"%236b7280\">🔒</text></svg>"
    _ -> data_url(thumb)
  }
}

pub fn delete_photo(
  id: String,
  on_response: fn(Result(Nil, rsvp.Error(String))) -> message,
) -> Effect(message) {
  let url = api_base_url() <> "/photos/" <> id
  let handler =
    rsvp.expect_text(fn(res) {
      case res {
        Ok(_) -> on_response(Ok(Nil))
        Error(e) -> on_response(Error(e))
      }
    })
  rsvp.delete(url, json.object([]), handler)
}
