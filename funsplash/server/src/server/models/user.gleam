import gleam/option.{type Option}
import server/sql
import shared/shared_user
import youid/uuid.{type Uuid}

// to avoid circular dependency hell :(

pub type UserName =
  String

pub type Id =
  Uuid

// TODO: think about including list of photo ids and photo cache
pub type User {
  User(
    id: Uuid,
    username: String,
    first_name: String,
    last_name: Option(String),
    bio: Option(String),
    available_for_hire: Bool,
    premium: Bool,
    storage_quota: Int,
    storage_quota_used: Int,
  )
}

// mappers

pub fn from_search(user u: sql.UserSearchRow) -> User {
  User(
    id: u.id,
    username: u.username,
    first_name: u.first_name,
    last_name: u.last_name,
    bio: u.bio,
    available_for_hire: u.available_for_hire,
    premium: u.premium,
    storage_quota: u.storage_quota,
    storage_quota_used: u.storage_quota_used,
  )
}

pub fn from_create(user u: sql.UserCreateRow) -> User {
  User(
    id: u.id,
    username: u.username,
    first_name: u.first_name,
    last_name: u.last_name,
    bio: u.bio,
    available_for_hire: u.available_for_hire,
    premium: u.premium,
    storage_quota: u.storage_quota,
    storage_quota_used: u.storage_quota_used,
  )
}

pub fn from_find_by_id(user u: sql.UserFindByIdRow) -> User {
  User(
    id: u.id,
    username: u.username,
    first_name: u.first_name,
    last_name: u.last_name,
    bio: u.bio,
    available_for_hire: u.available_for_hire,
    premium: u.premium,
    storage_quota: u.storage_quota,
    storage_quota_used: u.storage_quota_used,
  )
}

pub fn to_shared(user: User) -> shared_user.User {
  shared_user.User(
    username: user.username,
    first_name: user.first_name,
    last_name: user.last_name,
    bio: user.bio,
    available_for_hire: user.available_for_hire,
    premium: user.premium,
  )
}

pub fn from_find_by_name(user u: sql.UserFindByNameRow) -> User {
  User(
    id: u.id,
    username: u.username,
    first_name: u.first_name,
    last_name: u.last_name,
    bio: u.bio,
    available_for_hire: u.available_for_hire,
    premium: u.premium,
    storage_quota: u.storage_quota,
    storage_quota_used: u.storage_quota_used,
  )
}

pub fn from_update(user u: sql.UserUpdateRow) -> User {
  User(
    id: u.id,
    username: u.username,
    first_name: u.first_name,
    last_name: u.last_name,
    bio: u.bio,
    available_for_hire: u.available_for_hire,
    premium: u.premium,
    storage_quota: u.storage_quota,
    storage_quota_used: u.storage_quota_used,
  )
}
