import api/api_photo
import lustre/effect.{type Effect}
import rsvp
import shared/shared_user

pub fn fetch_me(
  on_response: fn(Result(shared_user.User, rsvp.Error(String))) -> message,
) -> Effect(message) {
  let url = api_photo.api_base_url() <> "/me"
  let handler = rsvp.expect_json(shared_user.user_decoder(), on_response)
  rsvp.get(url, handler)
}
