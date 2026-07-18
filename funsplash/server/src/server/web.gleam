import gleam/option.{type Option}
import server/models/user
import server/state
import wisp

pub type Context {
  Context(user: Option(user.User), state: state.State)
}

pub fn middleware(
  req: wisp.Request,
  context: Context,
  handle_request: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  use <- wisp.log_request(req)
  use <- wisp.serve_static(req, under: "/", from: context.state.static_dir)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  let req = wisp.method_override(req)
  use req <- wisp.csrf_known_header_protection(req)
  handle_request(req)
}
