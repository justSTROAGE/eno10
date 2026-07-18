import bravo/uset
import formal/form
import gleam/bool
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import server/collections
import server/models/collection
import server/models/photo
import server/models/user
import server/photos
import server/users
import server/web
import server/web/auth
import server/web/helper
import shared/shared_collection
import shared/shared_thumbnail
import utils.{result_guard}
import wisp

pub fn photos(
  _request: wisp.Request,
  context: web.Context,
  collection_id cid: collection.PublicId,
) -> wisp.Response {
  use col <- result_guard(
    collections.get_by_public(context.state, cid),
    wisp.not_found(),
  )
  use photos <- result_guard(
    photos.get_by_collection(context.state, col.id),
    wisp.not_found(),
  )

  let viewer_likes = case context.user {
    Some(u) ->
      uset.lookup(context.state.user_likes_cache, u.id) |> result.unwrap([])
    None -> []
  }

  let photos =
    photos
    |> list.try_map(fn(p) {
      use user <- result.try(users.get_by_id(context.state, p.creator))
      let user = user |> user.to_shared

      let liked = list.contains(viewer_likes, p.id)

      let cols = helper.current_user_collections(context, p)

      p
      |> photo.to_shared_thumbnail(user, liked, cols)
      |> shared_thumbnail.thumbnail_to_json
      |> Ok
    })

  case photos {
    Ok(photos) ->
      photos
      |> json.preprocessed_array
      |> json.to_string
      |> wisp.json_response(200)
    Error(_) -> wisp.internal_server_error()
  }
}

pub fn get(
  request: wisp.Request,
  context: web.Context,
  public_collection_id cid: collection.PublicId,
) -> wisp.Response {
  use <- wisp.require_method(request, http.Get)

  use col <- result_guard(
    collections.get_by_public(context.state, cid),
    wisp.not_found(),
  )
  use user <- result_guard(
    users.get_by_id(context.state, col.creator),
    wisp.internal_server_error(),
  )

  col
  |> collection.to_shared(user |> user.to_shared)
  |> shared_collection.collection_to_json
  |> json.to_string
  |> wisp.json_response(200)
}

pub fn create(request: wisp.Request, context: web.Context) -> wisp.Response {
  use <- wisp.require_method(request, http.Post)

  use user <- auth.require_login(context)
  use formdata <- wisp.require_form(request)

  let result = {
    use req <- result.try(
      shared_collection.collection_create_form()
      |> form.add_values(formdata.values)
      |> form.run
      |> result.replace_error(wisp.response(400)),
    )

    let photo_id = case req.photo_public_id {
      Some(id) ->
        case photos.get_by_public(context.state, id) {
          Ok(p) -> Some(p.id)
          _ -> None
        }
      _ -> None
    }

    use collection <- result.try(
      collections.create(
        context.state,
        req.name,
        req.description,
        req.private,
        user.id,
      )
      |> result.replace_error(wisp.internal_server_error()),
    )

    let _ = case photo_id {
      Some(pid) -> collections.add_photo(context.state, collection.id, pid)
      None -> Ok(Nil)
    }

    let redirect_to = case req.redirect_to {
      Some(url) if url != "" -> url
      _ -> "/collections/" <> collection.public_id
    }

    Ok(wisp.redirect(redirect_to))
  }

  case result {
    Ok(response) -> response
    Error(err) -> err
  }
}

pub fn add_photo(
  request: wisp.Request,
  context: web.Context,
  collection_public_id cid: collection.PublicId,
  photo_public_id pid: String,
) -> wisp.Response {
  use <- wisp.require_method(request, http.Post)
  use user <- auth.require_login(context)

  use collection <- result_guard(
    collections.get_by_public(context.state, cid),
    wisp.not_found(),
  )

  use <- bool.guard(collection.creator != user.id, wisp.response(403))

  use p <- result_guard(
    photos.get_by_public(context.state, pid),
    wisp.not_found(),
  )

  case collections.add_photo(context.state, collection.id, p.id) {
    Ok(_) -> wisp.ok()
    Error(collections.NotFound) -> wisp.not_found()
    Error(collections.Forbidden) -> wisp.response(403)
    Error(collections.InternalError) -> wisp.internal_server_error()
  }
}

pub fn remove_photo(
  request: wisp.Request,
  context: web.Context,
  collection_public_id cid: collection.PublicId,
  photo_public_id pid: String,
) -> wisp.Response {
  use <- wisp.require_method(request, http.Delete)
  use user <- auth.require_login(context)

  use col <- result_guard(
    collections.get_by_public(context.state, cid),
    wisp.not_found(),
  )

  use <- bool.guard(col.creator != user.id, wisp.response(403))

  use p <- result_guard(
    photos.get_by_public(context.state, pid),
    wisp.not_found(),
  )

  case collections.remove_photo(context.state, col.id, p.id, user.id) {
    Ok(_) -> wisp.ok()
    Error(collections.NotFound) -> wisp.not_found()
    Error(collections.Forbidden) -> wisp.response(403)
    Error(collections.InternalError) -> wisp.internal_server_error()
  }
}

pub fn update(
  request: wisp.Request,
  context: web.Context,
  collection_pubcli_id cid: collection.PublicId,
) -> wisp.Response {
  use user <- auth.require_login(context)

  use col <- result_guard(
    collections.get_by_public(context.state, cid),
    wisp.not_found(),
  )
  use <- bool.guard(col.creator != user.id, wisp.response(403))

  use formdata <- wisp.require_form(request)

  let result = {
    use req <- result.try(
      shared_collection.collection_update_form()
      |> form.add_values(formdata.values)
      |> form.run
      |> result.replace_error(wisp.response(400)),
    )

    use collection <- result.try(
      collections.update(
        context.state,
        req.name,
        req.description,
        req.private,
        col.id,
        user.id,
      )
      |> result.replace_error(wisp.internal_server_error()),
    )

    Ok(wisp.redirect("/collections/" <> collection.public_id))
  }

  case result {
    Ok(response) -> response
    Error(response) -> response
  }
}

pub fn delete(
  _request: wisp.Request,
  context: web.Context,
  collection_public_id cid: collection.PublicId,
) -> wisp.Response {
  use user <- auth.require_login(context)

  use col <- result_guard(
    collections.get_by_public(context.state, cid),
    wisp.not_found(),
  )
  use <- bool.guard(col.creator != user.id, wisp.response(403))

  use _ <- result_guard(
    collections.delete(context.state, col.id, user.id),
    wisp.internal_server_error(),
  )

  wisp.redirect("/users/" <> user.username)
}
