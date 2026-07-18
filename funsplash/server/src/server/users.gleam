import bravo/uset
import gleam/list
import gleam/option
import gleam/result
import server/models/photo
import server/models/user.{type User, User}
import server/sql
import server/state.{type State}
import shared/shared_account
import shared/shared_user.{type Error, NotFound}
import utils
import youid/uuid.{type Uuid}

pub fn get_likes(state: State, user_id id: user.Id) -> List(photo.Id) {
  case uset.lookup(state.user_likes_cache, id) {
    Ok(likes) -> likes
    Error(_) -> {
      use res <- utils.result_guard(sql.user_list_likes(state.db, id), [])
      let pids = res.rows |> list.map(fn(row) { row.photo_id })
      let _ = uset.insert(state.user_likes_cache, id, pids)
      pids
    }
  }
}

pub fn get_by_id(state: State, user_id id: user.Id) -> Result(User, Error) {
  utils.get_cache_l0(
    state.user_cache,
    id,
    sql.user_find_by_id(state.db, _),
    user.from_find_by_id,
    NotFound,
  )
}

pub fn get_by_name(
  state state: State,
  username name: String,
) -> Result(User, Error) {
  utils.get_cache_l1(
    state.profile_cache,
    state.user_cache,
    name,
    sql.user_find_by_name(state.db, _),
    fn(u) { u.id },
    user.from_find_by_name,
    NotFound,
  )
}

pub fn search(state: State, username: String) -> List(shared_user.User) {
  {
    use res <- result.try(
      sql.user_search(state.db, username) |> result.replace_error(Nil),
    )
    use first <- result.try(list.first(res.rows))
    // insert_new fails if already exists so this is safe
    let _ = uset.insert_new(state.profile_cache, first.username, first.id)
    Ok(
      list.map(res.rows, fn(row) { row |> user.from_search |> user.to_shared }),
    )
  }
  |> result.unwrap([])
}

pub fn update(
  user: shared_account.User,
  uid: Uuid,
  state: State,
) -> Result(User, shared_account.Error) {
  let existing = uset.lookup(state.profile_cache, user.username)
  let created_user = case existing {
    // username exists in cache and doesn't belong to current user
    Ok(id) if id != uid -> Error(shared_account.UsernameExists)
    _ -> {
      case utils.db_limit(sql.user_find_by_name(state.db, user.username)) {
        Ok(user) -> Ok(user |> user.from_find_by_name)
        Error(_) -> {
          use inserted_user <- utils.db_limit_try(
            sql.user_update(
              state.db,
              uid,
              user.username,
              user.first_name,
              user.last_name |> option.unwrap(""),
              user.bio |> option.unwrap(""),
              user.available_for_hire,
            ),
            shared_account.UsernameExists,
          )
          let _ = uset.delete_key(state.profile_cache, user.username)
          let _ = uset.delete_key(state.user_cache, uid)
          Ok(inserted_user |> user.from_update)
        }
      }
    }
  }

  use new_user <- result.try(created_user)
  let real_new_user = User(..new_user, username: user.username, id: uid)
  let _ = uset.insert_new(state.profile_cache, user.username, new_user.id)
  let _ = uset.insert(state.user_cache, uid, real_new_user)
  Ok(new_user)
}
