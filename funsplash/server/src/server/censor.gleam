import gleam/bit_array
import gleam/bool
import gleam/bytes_tree.{type BytesTree}
import gleam/crypto
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import mist
import png/censor
import png/png.{type Compressed, type Uncompressed}
import pog
import server/models/photo
import server/models/user.{type User}
import server/photos
import server/users
import server/web
import shared/shared_privacy.{Premium, Private, Public}
import shared/shared_upload
import utils
import youid/uuid

const ressource_limit = 900

// TODO: ets cache parsed images
pub type State {
  State(
    photo: photo.Photo,
    in_photo: png.Photo(BitArray, Uncompressed),
    out_photo: Option(png.Photo(BytesTree, Compressed)),
    req_counter: Int,
    z_stream: png.ZStream,
    user: user.User,
    context: web.Context,
    bg_db: pog.Connection,
  )
}

// Verify the wisp Signed `uid` cookie on a raw mist request and resolve the
// authenticated user. Returns None if there is no valid signed session cookie.
// This closes the unauthenticated-access hole documented in the audit: the
// censor websocket used to skip cookie auth entirely.
fn authenticated_user(
  request: request.Request(mist.Connection),
  context: web.Context,
  secret: String,
) -> Option(user.User) {
  let parsed = {
    use uid_cookie <- result.try(
      request
      |> request.get_cookies
      |> list.key_find("uid")
      |> result.replace_error(Nil),
    )
    // wisp signs cookies with crypto.sign_message(msg, secret, Sha512);
    // verify the signature using the same secret before trusting the value.
    use uid_bits <- result.try(
      crypto.verify_signed_message(uid_cookie, <<secret:utf8>>),
    )
    use uid_str <- result.try(bit_array.to_string(uid_bits))
    use uid <- result.try(uid_str |> uuid.from_string |> result.replace_error(Nil))
    users.get_by_id(context.state, uid) |> result.replace_error(Nil)
  }
  case parsed {
    Ok(user) -> Some(user)
    Error(_) -> None
  }
}

fn forbidden() -> response.Response(mist.ResponseData) {
  response.new(403)
  |> response.set_body(mist.Bytes(bytes_tree.new()))
}

// use websocket for future collaborative real-time editing
pub fn upgrade(
  request: request.Request(mist.Connection),
  public_id: String,
  context: web.Context,
  bg_db: pog.Connection,
  secret: String,
) -> response.Response(mist.ResponseData) {
  io.println("Connected")

  // Require a valid signed session cookie. The original code skipped auth
  // ("mist doesnt have built in signed cookie checks so we just dont them
  // here"), which let an unauthenticated attacker open the socket on any photo.
  case authenticated_user(request, context, secret) {
    None -> forbidden()
    Some(requester) -> {
      case photos.get_by_public(context.state, public_id) {
        Error(_) -> forbidden()
        Ok(photo) -> censor_photo(request, context, bg_db, requester, photo)
      }
    }
  }
}

fn censor_photo(
  request: request.Request(mist.Connection),
  context: web.Context,
  bg_db: pog.Connection,
  requester: user.User,
  photo: photo.Photo,
) -> response.Response(mist.ResponseData) {
  use <- bool.guard(
    // Only the owner may censor premium/private photos; anyone may censor
    // a public photo (its raw bytes are already public). This prevents an
    // attacker from pulling raw premium/private pixels through this socket.
    case photo.privacy {
      Public -> False
      _ -> requester.id != photo.creator
    },
    forbidden(),
  )

  let on_init = fn(_connection: mist.WebsocketConnection) -> #(
    State,
    Option(process.Selector(b)),
  ) {
    let assert Ok(data) =
      photos.get_data(context.state, photo.asset_id, photo.privacy)
    let data = data |> png.parse
    let z_stream = png.init_compressor()
    #(
      State(
        photo:,
        in_photo: data,
        out_photo: None,
        req_counter: 0,
        z_stream:,
        user: requester,
        context:,
        bg_db:,
      ),
      None,
    )
  }

  mist.websocket(
    request:,
    on_init: on_init,
    handler: handler,
    on_close: close_socket,
  )
}

fn close_socket(state: State) -> Nil {
  use <- utils.defer(fn() {
    png.close_compressor(state.z_stream)
    io.println("Disconnected")
  })
  let p = state.photo
  // Only re-upload a censored copy belonging to the authenticated requesting
  // user, and force it to public. The original code re-attributed the new
  // photo to p.creator (the original owner) with the original privacy, which
  // let an attacker mint a fresh publicly-readable copy of a premium/private
  // photo's raw pixels. The requester only ever gets their own public copy.
  {
    use data <- option.map(state.out_photo)
    process.spawn_unlinked(fn() {
      shared_upload.Upload(
        creator: state.user.id,
        description: Some(option.unwrap(p.description, "") <> " (censored)"),
        privacy: Public,
        location: p.location,
        camera: p.camera,
        show_on_profile: True,
        data: shared_upload.InMemory(data |> png.pack, p.mimetype),
        tags: [],
      )
      |> photos.upload(state.context.state)
    })
  }
  Nil
}

fn handler(
  state: State,
  message: mist.WebsocketMessage(b),
  connection: mist.WebsocketConnection,
) {
  use <- bool.guard(state.req_counter >= ressource_limit, mist.stop())
  let state = State(..state, req_counter: state.req_counter + 1)
  case message {
    mist.Binary(mask) -> {
      case censor.censor_raw(state.in_photo, mask, state.z_stream) {
        Ok(censored_png) -> {
          let new_quota = state.user.storage_quota_used + png.size(censored_png)
          let #(ok, state) = case new_quota < state.user.storage_quota {
            True -> #("true", State(..state, out_photo: Some(censored_png)))
            False -> #("false", state)
          }
          let response =
            "{\"ok\": "
            <> ok
            <> ", \"pid\": \""
            <> state.photo.public_id
            <> "\", \"usage\": "
            <> int.to_string(new_quota)
            <> ", \"limit\": "
            <> int.to_string(state.user.storage_quota)
            <> "}"
          let _ = mist.send_text_frame(connection, response)
          mist.continue(state)
        }
        Error(e) -> {
          let _ = mist.send_text_frame(connection, e)
          mist.continue(state)
        }
      }
    }
    mist.Shutdown -> mist.stop()
    mist.Closed -> mist.stop()
    mist.Text(_) -> mist.continue(state)
    _ -> mist.continue(state)
  }
}
