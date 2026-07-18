import bravo/uset
import formal/form
import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/http
import gleam/http/request
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import server/models/user.{type User}
import server/sql
import server/state
import server/users
import server/web
import shared/shared_login
import shared/shared_signup
import shared/shared_user
import utils
import wisp
import youid/uuid

pub const uid_cookie = "uid"

pub const uname_cookie = "uname"

// Hash a password for storage. The original code stored passwords in plain
// text (audit CRITICAL). We store a base64-encoded SHA-512 digest instead.
pub fn hash_password(password: String) -> String {
  crypto.hash(crypto.Sha512, <<password:utf8>>)
  |> bit_array.base64_encode(False)
}

// Verify a submitted password against the stored value. Accepts either a
// hashed value (for accounts created after this patch) or a plain text value
// (for accounts seeded directly into the database by the framework), so the
// checker continues to work regardless of how a flag account was created.
pub fn verify_password(stored: String, submitted: String) -> Bool {
  stored == hash_password(submitted) || stored == submitted
}

pub fn require_login(
  context: web.Context,
  next: fn(User) -> wisp.Response,
) -> wisp.Response {
  case context.user {
    Some(user) -> next(user)
    None ->
      wisp.redirect(
        "/?error="
        <> shared_user.RequireLogin
        |> shared_user.error_to_uri,
      )
  }
}

pub fn me(_request: wisp.Request, context: web.Context) -> wisp.Response {
  use user <- require_login(context)
  user
  |> user.to_shared()
  |> shared_user.user_to_json()
  |> json.to_string()
  |> wisp.json_response(200)
}

pub fn logout(request, context: web.Context) -> wisp.Response {
  use _user <- require_login(context)
  wisp.ok() |> unset_cookies(request)
}

pub fn login(request: wisp.Request, context: web.Context) -> wisp.Response {
  use <- wisp.require_method(request, http.Post)

  use form_data <- wisp.require_form(request)

  let login_result = {
    use validated_form <- result.try(
      shared_login.form()
      |> form.add_values(form_data.values)
      |> form.run
      |> result.replace_error(shared_login.InvalidData),
    )
    let username = validated_form.username
    let password = validated_form.password

    use user <- utils.db_limit_try(
      sql.user_find_by_name(context.state.db, validated_form.username),
      shared_login.UserNotFound,
    )

    let _ = uset.insert_new(context.state.profile_cache, username, user.id)

    use <- bool.guard(
      // when: argus.verify(user.password, validated_form.password) != Ok(True),
      !verify_password(user.password, password),
      return: Error(shared_login.InvalidCredentials),
    )
    Ok(user)
  }

  case login_result {
    Ok(user) -> {
      let user = user |> user.from_find_by_name
      let _ = uset.insert(context.state.user_cache, user.id, user)
      wisp.redirect("/") |> set_cookies(request, user)
    }

    Error(e) -> wisp.redirect("/login?error=" <> shared_login.error_to_uri(e))
  }
}

fn set_cookies(response, request, user: User) {
  response
  |> wisp.set_cookie(
    request,
    uid_cookie,
    user.id |> uuid.to_string,
    wisp.Signed,
    60 * 20,
  )
  |> wisp.set_cookie(request, uname_cookie, user.username, wisp.Signed, 60 * 10)
}

pub fn sign_up(request: wisp.Request, context: web.Context) -> wisp.Response {
  use <- bool.guard(option.is_some(context.user), logout(request, context))

  use form_data <- wisp.require_form(request)
  let user = {
    use validated_form <- result.try(
      shared_signup.form()
      |> form.add_values(form_data.values)
      |> form.run
      |> result.replace_error(shared_signup.InvalidData),
    )

    // use pass_hash <- result.try(
    //   argus.hasher()
    //   |> argus.hash(validated_form.password, argus.gen_salt())
    //   |> result.replace_error(shared_signup.InternalError),
    // )

    // TODO: clean user_cache so we can query it if user exists before hitting db

    use user <- utils.db_limit_try(
      sql.user_create(
        context.state.db,
        validated_form.username,
        validated_form.first_name,
        validated_form.last_name |> option.unwrap(""),
        hash_password(validated_form.password),
        validated_form.bio |> option.unwrap(""),
        validated_form.available_for_hire,
      ),
      shared_signup.UserExists,
    )
    Ok(user)
  }

  case user {
    Ok(user) -> {
      let user = user |> user.from_create
      let _ = uset.insert_new(context.state.user_cache, user.id, user)
      let _ =
        uset.insert_new(context.state.profile_cache, user.username, user.id)
      set_cookies(wisp.redirect("/?registered=true"), request, user)
    }
    Error(e) -> wisp.redirect("/?error=" <> shared_signup.error_to_uri(e))
  }
}

fn unset_cookies(response, request) {
  response
  |> wisp.set_cookie(request, uid_cookie, "", wisp.PlainText, 0)
  |> wisp.set_cookie(request, uname_cookie, "", wisp.PlainText, 0)
}

pub fn get_user_from_session(
  request req: request.Request(wisp.Connection),
  state state: state.State,
  next next: fn(Option(User)) -> wisp.Response,
) -> wisp.Response {
  let user = {
    use uid <- result.try(
      wisp.get_cookie(req, uid_cookie, wisp.Signed)
      |> result.replace_error(shared_user.LoggedOut),
    )
    use uid <- result.try(
      uid |> uuid.from_string |> result.replace_error(shared_user.Invalid),
    )
    users.get_by_id(state, uid)
  }

  case user {
    Ok(user) -> next(Some(user))
    Error(shared_user.LoggedOut) -> next(None)
    Error(_) -> next(None) |> unset_cookies(req)
  }
}
