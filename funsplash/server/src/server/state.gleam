import bravo
import bravo/uset.{type USet}
import gleam/erlang/process
import gleam/io
import pog
import server/id_server
import server/models/collection
import server/models/photo.{type Photo}
import server/models/user.{type User}
import youid/uuid

pub fn init(data_dir, static_dir, db, id_server_name) -> State {
  let assert Ok(collection_cache) = uset.new("collections_cache", bravo.Public)
  let assert Ok(user_cache) = uset.new("user_cache", bravo.Public)
  let assert Ok(photo_cache) = uset.new("photo_cache", bravo.Public)
  let assert Ok(asset_cache) = uset.new("asset_cache", bravo.Public)
  let assert Ok(profile_cache) = uset.new("profile_cache", bravo.Public)
  let assert Ok(collection_public_cache) =
    uset.new("collection_public_cache", bravo.Public)
  let assert Ok(photo_public_cache) =
    uset.new("photo_public_cache", bravo.Public)
  let assert Ok(user_collections_cache) =
    uset.new("user_collections_cache", bravo.Public)
  let assert Ok(user_photos_cache) = uset.new("user_photos_cache", bravo.Public)
  let assert Ok(collection_photos_cache) =
    uset.new("collection_photos_cache", bravo.Public)
  let assert Ok(user_likes_cache) = uset.new("user_likes_cache", bravo.Public)
  let assert Ok(tags_cache) = uset.new("tags_cache", bravo.Public)

  State(
    data_dir:,
    static_dir:,
    db:,
    id_server: id_server_name,
    collection_cache:,
    user_cache:,
    photo_cache:,
    asset_cache:,
    photo_public_cache:,
    profile_cache:,
    collection_public_cache:,
    user_collections_cache:,
    user_photos_cache:,
    collection_photos_cache:,
    user_likes_cache:,
    tags_cache:,
  )
}

pub type State {
  State(
    data_dir: String,
    static_dir: String,
    db: pog.Connection,
    id_server: process.Name(id_server.IdServerMessage),
    // l0
    collection_cache: CollectionCache,
    user_cache: UserCache,
    photo_cache: PhotoCache,
    // l1
    asset_cache: AssetCache,
    photo_public_cache: PhotoPublicCache,
    profile_cache: ProfileCache,
    collection_public_cache: CollectionPublicCache,
    // l2
    user_collections_cache: UserCollectionsCache,
    user_photos_cache: UserPhotosCache,
    collection_photos_cache: CollectionPhotosCache,
    user_likes_cache: UserLikesCache,
    tags_cache: TagsCache,
  )
}

// l0

pub type CollectionCache =
  USet(collection.Id, collection.Collection)

pub type PhotoCache =
  USet(photo.Id, Photo)

pub type UserCache =
  USet(user.Id, User)

// l1

pub type AssetCache =
  USet(photo.AssetId, photo.Id)

pub type PhotoPublicCache =
  USet(photo.PublicId, photo.Id)

pub type ProfileCache =
  USet(user.UserName, user.Id)

pub type CollectionPublicCache =
  USet(collection.PublicId, collection.Id)

// l2

pub type UserCollectionsCache =
  USet(user.Id, List(collection.Id))

pub type UserPhotosCache =
  USet(user.Id, List(photo.Id))

pub type CollectionPhotosCache =
  USet(collection.Id, List(photo.Id))

pub type UserLikesCache =
  USet(user.Id, List(photo.Id))

pub type TagsCache =
  USet(photo.Id, List(String))

pub fn start_ttl_sweeper(state: State, interval_ms: Int, ttl_ms: Int) {
  let _ = process.spawn(fn() { sweeper_loop(state, interval_ms, ttl_ms) })
  Nil
}

fn sweeper_loop(state: State, interval_ms: Int, ttl_ms: Int) {
  process.sleep(interval_ms)
  io.println("starting cache cleanup")
  let now = uuid.time_posix_millisec(uuid.v7())
  let cutoff = now - ttl_ms

  sweep_cache(state.user_cache, cutoff, fn(key, user) {
    let _ = uset.delete_key(state.profile_cache, user.username)
    let _ = uset.delete_key(state.user_collections_cache, key)
    let _ = uset.delete_key(state.user_photos_cache, key)
    let _ = uset.delete_key(state.user_likes_cache, key)
    Nil
  })

  sweep_cache(state.photo_cache, cutoff, fn(key, photo) {
    let _ = uset.delete_key(state.photo_public_cache, photo.public_id)
    let _ = uset.delete_key(state.asset_cache, photo.asset_id)
    let _ = uset.delete_key(state.tags_cache, key)
    Nil
  })

  sweep_cache(state.collection_cache, cutoff, fn(key, collection) {
    let _ = uset.delete_key(state.collection_photos_cache, key)
    let _ = uset.delete_key(state.collection_public_cache, collection.public_id)
    Nil
  })

  sweeper_loop(state, interval_ms, ttl_ms)
}

fn sweep_cache(
  cache: USet(uuid.Uuid, a),
  cutoff: Int,
  on_delete: fn(uuid.Uuid, a) -> Nil,
) {
  case uset.first(cache) {
    Ok(first_key) -> sweep_cache_loop(cache, cutoff, on_delete, first_key)
    Error(_) -> Nil
  }
}

fn sweep_cache_loop(
  cache: USet(uuid.Uuid, a),
  cutoff: Int,
  on_delete: fn(uuid.Uuid, a) -> Nil,
  key: uuid.Uuid,
) {
  let next_key = uset.next(cache, key)
  let timestamp = uuid.time_posix_millisec(key)
  case timestamp < cutoff {
    True -> {
      case uset.lookup(cache, key) {
        Ok(val) -> {
          on_delete(key, val)
          let _ = uset.delete_key(cache, key)
          Nil
        }
        Error(_) -> Nil
      }
    }
    False -> Nil
  }
  case next_key {
    Ok(k) -> sweep_cache_loop(cache, cutoff, on_delete, k)
    Error(_) -> Nil
  }
}
