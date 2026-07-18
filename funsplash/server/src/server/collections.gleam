import bravo/uset
import gleam/bool
import gleam/list
import gleam/result
import server/models/collection.{type Collection}
import server/models/photo
import server/models/user
import server/photos
import server/sql
import server/state.{type State}
import utils
import youid/uuid.{type Uuid}

pub type CollectionModifyError {
  NotFound
  Forbidden
  InternalError
}

pub fn get_containing_photo_from_user(
  state state: State,
  photo_id pid: photo.Id,
  user_id uid: user.Id,
) -> Result(List(collection.PublicId), Nil) {
  use collections <- result.try(get_by_user(state, uid, True))

  collections
  |> list.filter_map(fn(c) {
    let contains_photo = case photos.get_by_collection(state, c.id) {
      Ok(photos) -> photos |> list.any(fn(p) { p.id == pid })
      Error(_) -> False
    }

    case contains_photo {
      True -> Ok(c.public_id)
      False -> Error(Nil)
    }
  })
  |> Ok
}

pub fn get_by_user(
  state: State,
  user_id uid: Uuid,
  is_owner own: Bool,
) -> Result(List(Collection), Nil) {
  use collections <- result.try(utils.get_cache_l2(
    state.user_collections_cache,
    state.collection_cache,
    uid,
    sql.user_collections_list(state.db, _),
    fn(c) { c.id },
    collection.from_user_collections_list,
    Nil,
  ))
  collections |> list.filter(fn(c) { !c.private || own }) |> Ok
}

pub fn get_by_public(
  state: State,
  public_id cid: collection.PublicId,
) -> Result(Collection, Nil) {
  utils.get_cache_l1(
    state.collection_public_cache,
    state.collection_cache,
    cid,
    sql.collection_find_by_public_id(state.db, _),
    fn(c) { c.id },
    collection.from_find_by_public_id,
    Nil,
  )
}

pub fn get(
  state: State,
  collection_id cid: collection.Id,
) -> Result(Collection, Nil) {
  utils.get_cache_l0(
    state.collection_cache,
    cid,
    sql.collection_find_by_id(state.db, _),
    collection.from_find_by_id,
    Nil,
  )
}

pub fn create(
  state: State,
  name: String,
  description: String,
  private: Bool,
  user_id uid: user.Id,
) -> Result(Collection, Nil) {
  use collection <- result.try(
    sql.collection_create(
      state.db,
      utils.generate_id(state),
      name,
      description,
      uid,
      private,
    )
    |> utils.update_cache_l0(
      state.collection_cache,
      fn(c) { c.id },
      collection.from_create,
      Nil,
    ),
  )

  utils.extend_cache_l2(state.user_collections_cache, uid, collection.id)

  Ok(collection)
}

pub fn add_photo(
  state: State,
  collection_id cid: collection.Id,
  photo_id pid: photo.Id,
) -> Result(Nil, CollectionModifyError) {
  use _ <- result.try(
    sql.collection_add_photo(state.db, pid, cid)
    |> result.replace_error(InternalError),
  )

  utils.extend_cache_l2(state.collection_photos_cache, cid, pid)

  Ok(Nil)
}

pub fn remove_photo(
  state: State,
  collection_id: collection.Id,
  photo_id pid: photo.Id,
  user_id uid: user.Id,
) -> Result(Nil, CollectionModifyError) {
  use res <- result.try(
    sql.collection_find_by_id(state.db, collection_id)
    |> result.replace_error(NotFound),
  )

  use collection <- result.try(
    res.rows |> list.first |> result.replace_error(NotFound),
  )

  use <- bool.guard(collection.creator != uid, Error(Forbidden))

  use _ <- result.try(
    sql.collection_remove_photo(state.db, pid, collection_id)
    |> result.replace_error(InternalError),
  )

  utils.remove_cache_l2(state.collection_photos_cache, collection_id, pid)

  Ok(Nil)
}

pub fn update(
  state: State,
  name: String,
  description: String,
  private: Bool,
  collection_id cid: collection.Id,
  user_id uid: user.Id,
) -> Result(Collection, Nil) {
  use collection <- result.try(
    sql.collection_update(state.db, cid, name, description, private, uid)
    |> utils.update_cache_l0(
      state.collection_cache,
      fn(c) { c.id },
      collection.from_update,
      Nil,
    ),
  )

  Ok(collection)
}

pub fn delete(
  state: State,
  collection_id cid: collection.Id,
  user_id uid: user.Id,
) -> Result(Nil, Nil) {
  use _ <- result.try(
    sql.collection_delete(state.db, cid, uid)
    |> utils.db_limit
    |> result.replace_error(Nil),
  )

  let _ = uset.delete_key(state.collection_cache, cid)
  let _ = utils.remove_cache_l2(state.user_collections_cache, uid, cid)
  let _ = uset.delete_key(state.collection_photos_cache, cid)

  Ok(Nil)
}
