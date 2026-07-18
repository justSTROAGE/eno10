import gleam/option.{type Option}
import gleam/time/timestamp.{type Timestamp}
import server/mimetype
import server/sql
import shared/shared_collection
import shared/shared_photo
import shared/shared_privacy.{type Privacy, Premium, Private, Public}
import shared/shared_stats
import shared/shared_thumbnail
import shared/shared_upload
import shared/shared_user
import youid/uuid.{type Uuid}

pub type Id =
  Uuid

pub type PublicId =
  String

pub type AssetId =
  Uuid

pub type Photo {
  Photo(
    id: Id,
    public_id: PublicId,
    asset_id: AssetId,
    description: Option(String),
    creator: Uuid,
    privacy: Privacy,
    mimetype: shared_upload.MimeType,
    show_on_profile: Bool,
    location: Option(String),
    camera: Option(String),
    likes_count: Int,
    views: Int,
    downloads: Int,
    file_size: Int,
    created_at: Timestamp,
  )
}

// mappers

pub fn privacy_to_sql(priv: Privacy) -> sql.PhotoPrivacy {
  case priv {
    Public -> sql.Public
    Premium -> sql.Premium
    Private -> sql.Private
  }
}

pub fn sql_to_privacy(priv: sql.PhotoPrivacy) -> Privacy {
  case priv {
    sql.Public -> Public
    sql.Premium -> Premium
    sql.Private -> Private
  }
}

pub fn to_shared(
  photo: Photo,
  creator: shared_user.User,
  tags: List(String),
  user_liked: Bool,
  current_user_collections: List(shared_collection.PublicId),
) -> shared_photo.Photo {
  shared_photo.Photo(
    thumbnail: to_shared_thumbnail(
      photo,
      creator,
      user_liked,
      current_user_collections,
    ),
    description: photo.description,
    stats: to_shared_stats(photo),
    location: photo.location,
    camera: photo.camera,
    created_at: photo.created_at |> timestamp.to_unix_seconds,
    tags:,
  )
}

pub fn to_shared_stats(p: Photo) -> shared_stats.Stats {
  shared_stats.Stats(
    views: p.views,
    likes: p.likes_count,
    downloads: p.downloads,
  )
}

pub fn to_shared_thumbnail(
  p: Photo,
  creator: shared_user.User,
  user_liked: Bool,
  current_user_collections: List(shared_collection.PublicId),
) -> shared_thumbnail.Thumbnail {
  shared_thumbnail.Thumbnail(
    public_id: p.public_id,
    asset_id: p.asset_id |> uuid.to_string,
    description: p.description,
    creator: creator,
    privacy: p.privacy,
    user_liked:,
    show_on_profile: p.show_on_profile,
    current_user_collections:,
  )
}

pub fn from_find_by_public_id(p: sql.PhotoFindByPublicIdRow) -> Photo {
  Photo(
    id: p.id,
    public_id: p.public_id,
    asset_id: p.asset_id,
    description: p.description,
    creator: p.creator,
    privacy: p.privacy |> sql_to_privacy,
    show_on_profile: p.show_on_profile,
    mimetype: p.mimetype |> mimetype.sql_to_shared,
    location: p.location,
    camera: p.camera,
    likes_count: p.likes_count,
    views: p.views,
    downloads: p.downloads,
    created_at: p.created_at,
    file_size: p.file_size,
  )
}

pub fn from_create(p: sql.PhotoCreateRow) -> Photo {
  Photo(
    id: p.id,
    public_id: p.public_id,
    asset_id: p.asset_id,
    description: p.description,
    creator: p.creator,
    privacy: p.privacy |> sql_to_privacy,
    show_on_profile: p.show_on_profile,
    mimetype: p.mimetype |> mimetype.sql_to_shared,
    location: p.location,
    camera: p.camera,
    likes_count: p.likes_count,
    views: p.views,
    downloads: p.downloads,
    created_at: p.created_at,
    file_size: p.file_size,
  )
}

pub fn from_user_likes_add(p: sql.UserLikesPhotoAddRow) -> Photo {
  Photo(
    id: p.id,
    public_id: p.public_id,
    asset_id: p.asset_id,
    description: p.description,
    creator: p.creator,
    privacy: p.privacy |> sql_to_privacy,
    show_on_profile: p.show_on_profile,
    mimetype: p.mimetype |> mimetype.sql_to_shared,
    location: p.location,
    camera: p.camera,
    likes_count: p.likes_count,
    views: p.views,
    downloads: p.downloads,
    created_at: p.created_at,
    file_size: p.file_size,
  )
}

pub fn from_user_likes_remove(p: sql.UserLikesPhotoRemoveRow) -> Photo {
  Photo(
    id: p.id,
    public_id: p.public_id,
    asset_id: p.asset_id,
    description: p.description,
    creator: p.creator,
    privacy: p.privacy |> sql_to_privacy,
    show_on_profile: p.show_on_profile,
    mimetype: p.mimetype |> mimetype.sql_to_shared,
    location: p.location,
    camera: p.camera,
    likes_count: p.likes_count,
    views: p.views,
    downloads: p.downloads,
    created_at: p.created_at,
    file_size: p.file_size,
  )
}

pub fn from_find_by_id(p: sql.PhotoFindByIdRow) -> Photo {
  Photo(
    id: p.id,
    public_id: p.public_id,
    asset_id: p.asset_id,
    description: p.description,
    creator: p.creator,
    privacy: p.privacy |> sql_to_privacy,
    show_on_profile: p.show_on_profile,
    mimetype: p.mimetype |> mimetype.sql_to_shared,
    location: p.location,
    camera: p.camera,
    likes_count: p.likes_count,
    views: p.views,
    downloads: p.downloads,
    created_at: p.created_at,
    file_size: p.file_size,
  )
}

pub fn from_collection_list(p: sql.CollectionPhotosListRow) -> Photo {
  Photo(
    id: p.id,
    public_id: p.public_id,
    asset_id: p.asset_id,
    description: p.description,
    creator: p.creator,
    privacy: p.privacy |> sql_to_privacy,
    show_on_profile: p.show_on_profile,
    mimetype: p.mimetype |> mimetype.sql_to_shared,
    location: p.location,
    camera: p.camera,
    likes_count: p.likes_count,
    views: p.views,
    downloads: p.downloads,
    created_at: p.created_at,
    file_size: p.file_size,
  )
}

pub fn from_update(p: sql.PhotoUpdateRow) -> Photo {
  Photo(
    id: p.id,
    public_id: p.public_id,
    asset_id: p.asset_id,
    description: p.description,
    creator: p.creator,
    privacy: p.privacy |> sql_to_privacy,
    show_on_profile: p.show_on_profile,
    mimetype: p.mimetype |> mimetype.sql_to_shared,
    location: p.location,
    camera: p.camera,
    likes_count: p.likes_count,
    views: p.views,
    downloads: p.downloads,
    file_size: p.file_size,
    created_at: p.created_at,
  )
}

pub fn from_delete(p: sql.PhotoDeleteRow) -> Photo {
  Photo(
    id: p.id,
    public_id: p.public_id,
    asset_id: p.asset_id,
    description: p.description,
    creator: p.creator,
    privacy: p.privacy |> sql_to_privacy,
    show_on_profile: p.show_on_profile,
    mimetype: p.mimetype |> mimetype.sql_to_shared,
    location: p.location,
    camera: p.camera,
    likes_count: p.likes_count,
    views: p.views,
    downloads: p.downloads,
    file_size: p.file_size,
    created_at: p.created_at,
  )
}

pub fn from_find_by_asset_id(p: sql.PhotoFindByAssetIdRow) -> Photo {
  Photo(
    id: p.id,
    public_id: p.public_id,
    asset_id: p.asset_id,
    description: p.description,
    creator: p.creator,
    privacy: p.privacy |> sql_to_privacy,
    show_on_profile: p.show_on_profile,
    mimetype: p.mimetype |> mimetype.sql_to_shared,
    location: p.location,
    camera: p.camera,
    likes_count: p.likes_count,
    views: p.views,
    downloads: p.downloads,
    created_at: p.created_at,
    file_size: p.file_size,
  )
}

pub fn from_photos_list_by_user(photo p: sql.PhotosListByUserRow) -> Photo {
  Photo(
    id: p.id,
    public_id: p.public_id,
    asset_id: p.asset_id,
    description: p.description,
    creator: p.creator,
    privacy: p.privacy |> sql_to_privacy,
    show_on_profile: p.show_on_profile,
    mimetype: p.mimetype |> mimetype.sql_to_shared,
    location: p.location,
    camera: p.camera,
    likes_count: p.likes_count,
    views: p.views,
    downloads: p.downloads,
    created_at: p.created_at,
    file_size: p.file_size,
  )
}

pub fn from_photos_list_by_owner(photo p: sql.PhotosListByOwnerRow) -> Photo {
  Photo(
    id: p.id,
    public_id: p.public_id,
    asset_id: p.asset_id,
    description: p.description,
    creator: p.creator,
    privacy: p.privacy |> sql_to_privacy,
    show_on_profile: p.show_on_profile,
    mimetype: p.mimetype |> mimetype.sql_to_shared,
    location: p.location,
    camera: p.camera,
    likes_count: p.likes_count,
    views: p.views,
    downloads: p.downloads,
    file_size: p.file_size,
    created_at: p.created_at,
  )
}

pub fn from_add_tag(row: sql.PhotoAddTagRow) -> #(Id, String) {
  #(row.photo_id, row.tag)
}

pub fn from_remove_tag(row: sql.PhotoRemoveTagRow) -> #(Id, String) {
  #(row.photo_id, row.tag)
}
