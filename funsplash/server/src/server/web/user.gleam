import gleam/json
import gleam/list
import gleam/option.{Some}
import server/collections
import server/models/collection
import server/models/photo
import server/models/user
import server/photos
import server/users
import server/web
import server/web/helper
import shared/shared_collection
import shared/shared_thumbnail
import shared/shared_user
import utils
import wisp

pub fn get(
  _request: wisp.Request,
  context: web.Context,
  username: String,
) -> wisp.Response {
  let user = users.get_by_name(context.state, username)

  case user {
    Ok(user) ->
      wisp.json_response(
        user
          |> user.to_shared
          |> shared_user.user_to_json
          |> json.to_string(),
        200,
      )
    _ -> wisp.bad_request("error")
  }
}

pub fn get_collections(
  _request: wisp.Request,
  context: web.Context,
  username: String,
) -> wisp.Response {
  use creator <- utils.result_guard(
    users.get_by_name(context.state, username),
    wisp.not_found(),
  )

  let is_owner = case context.user {
    Some(user) if user.id == creator.id -> True
    _ -> False
  }

  use collections <- utils.result_guard(
    collections.get_by_user(context.state, creator.id, is_owner),
    wisp.not_found(),
  )

  let creator = creator |> user.to_shared

  collections
  |> list.map(fn(c) {
    c |> collection.to_shared(creator) |> shared_collection.collection_to_json
  })
  |> json.preprocessed_array
  |> json.to_string
  |> wisp.json_response(200)
}

pub fn get_photos(
  _request: wisp.Request,
  context: web.Context,
  username: String,
) -> wisp.Response {
  // alternative do with by_user(id)
  use photos <- utils.result_guard(
    case context.user {
      Some(user) if user.username == username ->
        photos.get_by_username(context.state, username, True)
      _ -> photos.get_by_username(context.state, username, False)
    },
    wisp.not_found(),
  )

  use creator <- utils.result_guard(
    users.get_by_name(context.state, username),
    wisp.internal_server_error(),
  )
  let creator = creator |> user.to_shared

  photos
  |> list.map(fn(p) {
    let current_user_collections = helper.current_user_collections(context, p)
    p
    |> photo.to_shared_thumbnail(creator, False, current_user_collections)
    |> shared_thumbnail.thumbnail_to_json
  })
  |> json.preprocessed_array
  |> json.to_string
  |> wisp.json_response(200)
}

pub fn search(
  _request: wisp.Request,
  context: web.Context,
  username: String,
) -> wisp.Response {
  users.search(context.state, username)
  |> json.array(shared_user.user_to_json)
  |> json.to_string()
  |> wisp.json_response(200)
}
