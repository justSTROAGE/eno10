import bravo/uset
import gleam/bit_array
import gleam/bool
import gleam/list
import gleam/option
import gleam/result
import server/mimetype
import server/models/photo.{type Photo}
import server/models/user
import server/premium
import server/sql
import server/state.{type State}
import server/users
import shared/shared_privacy.{type Privacy}
import shared/shared_upload
import simplifile
import utils
import youid/uuid.{type Uuid}

pub fn get_data(
  state: State,
  asset_id: uuid.Uuid,
  _privacy: Privacy,
) -> Result(BitArray, Nil) {
  let fs_path = state.data_dir <> "/photos/" <> uuid.to_string(asset_id)
  case simplifile.read_bits(fs_path) {
    Ok(data) -> Ok(data)
    Error(_) -> Error(Nil)
  }
}

pub fn get_tags(
  state: State,
  photo_id id: photo.Id,
) -> Result(List(String), Nil) {
  case uset.lookup(state.tags_cache, id) {
    Ok(tags) -> Ok(tags)
    Error(_) -> {
      case sql.tags_list_by_photo(state.db, id) {
        Ok(res) -> {
          let tags = list.map(res.rows, fn(row) { row.tag })
          let _ = uset.insert(state.tags_cache, id, tags)
          Ok(tags)
        }

        Error(_) -> Error(Nil)
      }
    }
  }
}

pub fn get(state: State, id: photo.Id) -> Result(Photo, Nil) {
  utils.get_cache_l0(
    state.photo_cache,
    id,
    sql.photo_find_by_id(state.db, _),
    photo.from_find_by_id,
    Nil,
  )
}

pub type Error {
  PhotoNotFound
  UserNotFound
  InternalError
  CollectionNotFound
}

pub fn get_ids_by_user(
  state: State,
  user_id uid: user.Id,
) -> Result(List(photo.Id), Error) {
  case uset.lookup(state.user_photos_cache, uid) {
    Ok(pids) -> Ok(pids)
    Error(_) -> {
      use res <- result.try(
        sql.photos_list_by_user(state.db, uid)
        |> result.replace_error(InternalError),
      )
      let pids = res.rows |> list.map(fn(row) { row.id })
      let _ = uset.insert(state.user_photos_cache, uid, pids)
      Ok(pids)
    }
  }
}

pub fn get_by_username(
  state: State,
  username name: String,
  is_owner own: Bool,
) -> Result(List(Photo), Error) {
  use user <- result.try(utils.get_cache_l1(
    state.profile_cache,
    state.user_cache,
    name,
    sql.user_find_by_name(state.db, _),
    fn(u) { u.id },
    user.from_find_by_name,
    UserNotFound,
  ))
  use photos <- result.try(utils.get_cache_l2(
    state.user_photos_cache,
    state.photo_cache,
    user.id,
    sql.photos_list_by_owner(state.db, _),
    fn(p) { p.id },
    photo.from_photos_list_by_owner,
    InternalError,
  ))
  photos |> list.filter(fn(p) { p.show_on_profile || own }) |> Ok
}

pub fn get_by_collection(
  state: State,
  collection_id cid: Uuid,
) -> Result(List(Photo), Error) {
  utils.get_cache_l2(
    state.collection_photos_cache,
    state.photo_cache,
    cid,
    sql.collection_photos_list(state.db, _),
    fn(p) { p.id },
    photo.from_collection_list,
    PhotoNotFound,
  )
}

pub fn get_by_asset(id: photo.AssetId, state: State) -> Result(Photo, Nil) {
  utils.get_cache_l1(
    state.asset_cache,
    state.photo_cache,
    id,
    sql.photo_find_by_asset_id(state.db, _),
    fn(p) { p.id },
    photo.from_find_by_asset_id,
    Nil,
  )
}

pub fn get_by_public(state: State, id: photo.PublicId) -> Result(Photo, Nil) {
  utils.get_cache_l1(
    state.photo_public_cache,
    state.photo_cache,
    id,
    sql.photo_find_by_public_id(state.db, _),
    fn(p) { p.id },
    photo.from_find_by_public_id,
    Nil,
  )
}

pub fn like(
  state: State,
  photo_id pid: photo.Id,
  user_id uid: user.Id,
) -> Result(Nil, Nil) {
  use photo <- result.try(
    sql.user_likes_photo_add(state.db, uid, pid)
    |> utils.update_cache_l0(
      state.photo_cache,
      fn(p) { p.id },
      photo.from_user_likes_add,
      Nil,
    ),
  )

  utils.extend_cache_l2(state.user_likes_cache, uid, photo.id)

  Ok(Nil)
}

pub fn unlike(
  state: State,
  photo_id pid: photo.Id,
  user_id uid: user.Id,
) -> Result(Nil, Nil) {
  use _ <- result.try(
    sql.user_likes_photo_remove(state.db, uid, pid)
    |> utils.update_cache_l0(
      state.photo_cache,
      fn(p) { p.id },
      photo.from_user_likes_remove,
      Nil,
    ),
  )

  utils.remove_cache_l2(state.user_likes_cache, uid, pid)

  Ok(Nil)
}

pub fn has_user_liked(
  state: State,
  photo_id pid: photo.Id,
  user_id uid: user.Id,
) -> Bool {
  users.get_likes(state, uid)
  |> list.contains(pid)
}

pub fn upload(
  photo p: shared_upload.Upload,
  state state: State,
) -> Result(Nil, shared_upload.Error) {
  let size = case p.data {
    shared_upload.InMemory(data:, mimetype: _) -> bit_array.byte_size(data)
    shared_upload.File(path: _, size:) -> size
  }

  use <- bool.guard(
    size > shared_upload.max_allowed_size,
    Error(shared_upload.ImageTooLarge(shared_upload.max_allowed_size)),
  )

  use user <- result.try(
    uset.lookup(state.user_cache, p.creator)
    |> result.replace_error(shared_upload.InternalError),
  )

  let new_used_quota = user.storage_quota_used + size
  use <- bool.guard(
    new_used_quota > user.storage_quota,
    Error(shared_upload.QuotaExceeded(user.storage_quota_used)),
  )

  let mimetype = case p.data {
    shared_upload.InMemory(data: _, mimetype:) -> mimetype
    shared_upload.File(path:, size: _) ->
      path |> mimetype.detect() |> result.unwrap(shared_upload.Other)
  }

  use new_photo <- result.try(
    sql.photo_create(
      state.db,
      p.description |> option.unwrap(""),
      p.creator,
      p.privacy |> photo.privacy_to_sql,
      p.location |> option.unwrap(""),
      p.camera |> option.unwrap(""),
      p.show_on_profile,
      size,
      mimetype |> mimetype.shared_to_sql,
      utils.generate_id(state),
    )
    |> utils.update_cache_l0(
      state.photo_cache,
      fn(p) { p.id },
      photo.from_create,
      shared_upload.InternalError,
    ),
  )

  utils.extend_cache_l2(state.user_photos_cache, user.id, new_photo.id)

  let _ =
    uset.insert(
      state.user_cache,
      user.id,
      user.User(..user, storage_quota_used: new_used_quota),
    )

  let fs_path =
    state.data_dir <> "/photos/" <> uuid.to_string(new_photo.asset_id)
  use _ <- result.try(
    case p.data {
      shared_upload.InMemory(data:, mimetype: _) ->
        simplifile.write_bits(fs_path, data)
      shared_upload.File(path:, size: _) -> simplifile.rename(path, fs_path)
    }
    |> result.replace_error(shared_upload.InternalError),
  )

  use _ <- result.try(case p.privacy {
    shared_privacy.Premium -> {
      let censored_path =
        state.data_dir
        <> "/photos_premium/"
        <> uuid.to_string(new_photo.asset_id)

      use data <- result.try(
        case p.data {
          shared_upload.InMemory(data:, ..) -> Ok(data)
          shared_upload.File(..) -> simplifile.read_bits(fs_path)
        }
        |> result.replace_error(shared_upload.InternalError),
      )

      case mimetype {
        shared_upload.Png -> data |> premium.censor
        _ -> <<>>
      }
      |> simplifile.write_bits(censored_path, _)
      |> result.replace_error(shared_upload.InternalError)
    }
    _ -> Ok(Nil)
  })

  use _ <- result.try(
    sql.photo_add_tags_batch(state.db, p.tags, new_photo.id)
    |> result.replace_error(shared_upload.InternalError),
  )

  let _ = uset.insert(state.tags_cache, new_photo.id, p.tags)

  Ok(Nil)
}

pub fn update(
  state: State,
  public_id: String,
  description: String,
  location: String,
  camera: String,
  privacy: shared_privacy.Privacy,
  show_on_profile: Bool,
  tags: List(String),
  user_id uid: user.Id,
) -> Result(photo.PublicId, shared_upload.Error) {
  use photo <- result.try(
    sql.photo_update(
      state.db,
      public_id,
      description,
      location,
      camera,
      photo.privacy_to_sql(privacy),
      show_on_profile,
      uid,
    )
    |> utils.update_cache_l0(
      state.photo_cache,
      fn(p) { p.id },
      photo.from_update,
      shared_upload.InternalError,
    ),
  )

  let existing_tags_res = uset.lookup(state.tags_cache, photo.id)

  use _ <- result.try(case existing_tags_res {
    Ok(existing) if existing == tags -> Ok(Nil)
    _ -> {
      use _ <- result.try(
        sql.photo_remove_all_tags(state.db, photo.id)
        |> result.replace_error(shared_upload.InternalError),
      )

      use _ <- result.try(
        sql.photo_add_tags_batch(state.db, tags, photo.id)
        |> result.replace_error(shared_upload.InternalError),
      )

      let _ = uset.insert(state.tags_cache, photo.id, tags)
      Ok(Nil)
    }
  })

  Ok(photo.public_id)
}

pub fn delete(
  state: State,
  public_id: String,
  user_id uid: user.Id,
) -> Result(Nil, Nil) {
  use photo_row <- result.try(
    sql.photo_delete(state.db, public_id, uid)
    |> utils.db_limit
    |> result.replace_error(Nil),
  )

  let p = photo.from_delete(photo_row)

  let _ = uset.delete_key(state.photo_cache, p.id)
  let _ = utils.remove_cache_l2(state.user_photos_cache, uid, p.id)
  let _ = uset.delete_key(state.photo_public_cache, p.public_id)
  let _ = uset.delete_key(state.asset_cache, p.asset_id)
  let _ = uset.delete_key(state.tags_cache, p.id)

  let fs_path = state.data_dir <> "/photos/" <> uuid.to_string(p.asset_id)
  let _ = simplifile.delete(fs_path)

  let censored_path =
    state.data_dir <> "/photos_premium/" <> uuid.to_string(p.asset_id)
  let _ = simplifile.delete(censored_path)

  Ok(Nil)
}
