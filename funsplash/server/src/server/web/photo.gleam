import formal/form
import gleam/bool
import gleam/bytes_tree
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import server/models/photo.{type Photo}
import server/models/user
import server/photos
import server/premium
import server/state.{type State}
import server/users
import server/web
import server/web/auth
import server/web/helper
import shared/shared_photo
import shared/shared_privacy.{Premium, Private, Public}
import shared/shared_upload
import simplifile
import utils.{result_guard}
import wisp
import youid/uuid

fn try_get_asset(
  asset_id: String,
  state: State,
  next: fn(Photo) -> wisp.Response,
) -> wisp.Response {
  use asset_id <- utils.result_guard(
    asset_id |> uuid.from_string,
    wisp.not_found(),
  )
  use photo <- utils.result_guard(
    photos.get_by_asset(asset_id, state),
    wisp.not_found(),
  )
  next(photo)
}

pub fn get_data_private(
  _request: wisp.Request,
  context: web.Context,
  asset_id: String,
) -> wisp.Response {
  use user <- auth.require_login(context)
  use photo <- try_get_asset(asset_id, context.state)

  use <- bool.guard(photo.privacy != Private, wisp.not_found())
  use <- bool.guard(photo.creator != user.id, wisp.response(403))

  let fs_path =
    context.state.data_dir <> "/photos/" <> uuid.to_string(photo.asset_id)

  wisp.ok()
  |> wisp.set_header("content-type", "image/png")
  |> wisp.set_body(wisp.File(fs_path, offset: 0, limit: None))
}

pub fn get_data_premium(
  _request: wisp.Request,
  context: web.Context,
  asset_id: String,
) -> wisp.Response {
  use photo <- try_get_asset(asset_id, context.state)

  use <- bool.guard(photo.privacy != Premium, wisp.not_found())

  let fs_path =
    context.state.data_dir
    <> case context.user {
      Some(user) if user.id == photo.creator || user.premium == True ->
        "/photos/"
      _ -> "/photos_premium/"
    }
    <> uuid.to_string(photo.asset_id)

  wisp.ok()
  |> wisp.set_header("content-type", "image/png")
  |> wisp.set_body(wisp.File(fs_path, offset: 0, limit: None))
}

pub fn get_data_public(
  _request: wisp.Request,
  context: web.Context,
  asset_id: String,
) -> wisp.Response {
  // TODO: move photo files into privacy dirs /public /private etc. so we dont have to call db here
  use photo <- try_get_asset(asset_id, context.state)

  use <- bool.guard(photo.privacy != Public, wisp.not_found())

  let fs_path =
    context.state.data_dir <> "/photos/" <> uuid.to_string(photo.asset_id)

  wisp.ok()
  |> wisp.set_header("content-type", "image/png")
  |> wisp.set_body(wisp.File(fs_path, offset: 0, limit: None))
}

pub fn get(
  _request: wisp.Request,
  context: web.Context,
  public_id: String,
) -> wisp.Response {
  use photo <- utils.result_guard(
    photos.get_by_public(context.state, public_id),
    wisp.not_found(),
  )
  use user <- utils.result_guard(
    users.get_by_id(context.state, photo.creator),
    wisp.internal_server_error(),
  )

  let cols = helper.current_user_collections(context, photo)

  use tags <- utils.result_guard(
    photos.get_tags(context.state, photo.id),
    wisp.internal_server_error(),
  )

  let user_liked = case context.user {
    Some(viewer) -> photos.has_user_liked(context.state, photo.id, viewer.id)
    None -> False
  }

  photo
  |> photo.to_shared(user |> user.to_shared, tags, user_liked, cols)
  |> shared_photo.photo_to_json
  |> json.to_string
  |> wisp.json_response(200)
}

pub fn upload(request: wisp.Request, context: web.Context) -> wisp.Response {
  use user <- auth.require_login(context)

  use multipart <- wisp.require_form(request)

  let upload_result = {
    use file <- result.try(
      list.key_find(multipart.files, "photo")
      |> result.replace_error(shared_upload.FileMissing),
    )
    use info <- result.try(
      simplifile.file_info(file.path)
      |> result.replace_error(shared_upload.FileReadError),
    )

    let data = shared_upload.File(file.path, info.size)

    use form <- result.try(
      shared_upload.upload_form(user.id, data)
      |> form.add_values(multipart.values)
      |> form.run
      |> result.map_error(fn(f) {
        case form.field_errors(f, "photo") {
          [_, ..] -> shared_upload.ImageTooLarge(shared_upload.max_allowed_size)
          _ -> shared_upload.InvalidForm
        }
      }),
    )

    form
    |> photos.upload(context.state)
  }

  case upload_result {
    Ok(_) -> wisp.redirect("/?upload_successful")
    Error(err) -> {
      wisp.redirect("/?error=" <> shared_upload.error_to_uri(err))
    }
  }
}

pub fn like(
  request: wisp.Request,
  context: web.Context,
  public_id pid: String,
) -> wisp.Response {
  use user <- auth.require_login(context)
  use p <- result_guard(
    photos.get_by_public(context.state, pid),
    wisp.not_found(),
  )

  let res = case request.method {
    http.Post -> Ok(photos.like(context.state, p.id, user.id))
    http.Delete -> Ok(photos.unlike(context.state, p.id, user.id))
    _ -> Error(Nil)
  }

  case res {
    Ok(res) ->
      case res {
        Ok(_) -> wisp.ok()
        Error(_) -> wisp.internal_server_error()
      }
    Error(_) -> wisp.method_not_allowed([http.Delete, http.Post])
  }
}

pub fn update(
  request: wisp.Request,
  context: web.Context,
  public_id pid: String,
) -> wisp.Response {
  use user <- auth.require_login(context)

  use p <- result_guard(
    photos.get_by_public(context.state, pid),
    wisp.not_found(),
  )
  use <- bool.guard(p.creator != user.id, wisp.response(403))

  use formdata <- wisp.require_form(request)

  let result = {
    use req <- result.try(
      shared_photo.photo_update_form()
      |> form.add_values(formdata.values)
      |> form.run
      |> result.replace_error(wisp.response(400)),
    )

    use _photo_id <- result.try(
      photos.update(
        context.state,
        pid,
        req.description,
        req.location,
        req.camera,
        req.privacy,
        req.show_on_profile,
        req.tags,
        user.id,
      )
      |> result.replace_error(wisp.internal_server_error()),
    )

    Ok(wisp.redirect("/photos/" <> pid))
  }

  case result {
    Ok(response) -> response
    Error(response) -> response
  }
}

pub fn delete(
  _request: wisp.Request,
  context: web.Context,
  public_id pid: String,
) -> wisp.Response {
  use user <- auth.require_login(context)

  use p <- result_guard(
    photos.get_by_public(context.state, pid),
    wisp.not_found(),
  )
  use <- bool.guard(p.creator != user.id, wisp.response(403))

  use _ <- result_guard(
    photos.delete(context.state, pid, user.id),
    wisp.internal_server_error(),
  )

  wisp.redirect("/users/" <> uuid.to_string(user.id))
}
