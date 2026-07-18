//// This module contains the code to run the sql queries defined in
//// `./src/server/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/option.{type Option}
import gleam/time/timestamp.{type Timestamp}
import pog
import youid/uuid.{type Uuid}

/// A row you get from running the `collection_add_photo` query
/// defined in `./src/server/sql/collection_add_photo.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CollectionAddPhotoRow {
  CollectionAddPhotoRow(photo_id: Uuid, collection_id: Uuid)
}

/// Runs the `collection_add_photo` query
/// defined in `./src/server/sql/collection_add_photo.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn collection_add_photo(
  db: pog.Connection,
  arg_1: Uuid,
  arg_2: Uuid,
) -> Result(pog.Returned(CollectionAddPhotoRow), pog.QueryError) {
  let decoder = {
    use photo_id <- decode.field(0, uuid_decoder())
    use collection_id <- decode.field(1, uuid_decoder())
    decode.success(CollectionAddPhotoRow(photo_id:, collection_id:))
  }

  "INSERT INTO collections_photos (photo_id, collection_id)
VALUES ($1, $2)
ON CONFLICT DO NOTHING
RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `collection_create` query
/// defined in `./src/server/sql/collection_create.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CollectionCreateRow {
  CollectionCreateRow(
    id: Uuid,
    public_id: String,
    name: String,
    description: Option(String),
    creator: Uuid,
    private: Bool,
  )
}

/// Runs the `collection_create` query
/// defined in `./src/server/sql/collection_create.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn collection_create(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: String,
  arg_4: Uuid,
  arg_5: Bool,
) -> Result(pog.Returned(CollectionCreateRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use name <- decode.field(2, decode.string)
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use private <- decode.field(5, decode.bool)
    decode.success(CollectionCreateRow(
      id:,
      public_id:,
      name:,
      description:,
      creator:,
      private:,
    ))
  }

  "INSERT INTO collections (public_id, name, description, creator, private)
VALUES ($1, $2, nullif($3, ''), $4, $5)
RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(uuid.to_string(arg_4)))
  |> pog.parameter(pog.bool(arg_5))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `collection_delete` query
/// defined in `./src/server/sql/collection_delete.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CollectionDeleteRow {
  CollectionDeleteRow(id: Uuid)
}

/// Runs the `collection_delete` query
/// defined in `./src/server/sql/collection_delete.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn collection_delete(
  db: pog.Connection,
  id: Uuid,
  creator: Uuid,
) -> Result(pog.Returned(CollectionDeleteRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    decode.success(CollectionDeleteRow(id:))
  }

  "DELETE FROM collections
WHERE id = $1 AND creator = $2
RETURNING id;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(id)))
  |> pog.parameter(pog.text(uuid.to_string(creator)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `collection_find_by_id` query
/// defined in `./src/server/sql/collection_find_by_id.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CollectionFindByIdRow {
  CollectionFindByIdRow(
    id: Uuid,
    public_id: String,
    name: String,
    description: Option(String),
    creator: Uuid,
    private: Bool,
  )
}

/// Runs the `collection_find_by_id` query
/// defined in `./src/server/sql/collection_find_by_id.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn collection_find_by_id(
  db: pog.Connection,
  id: Uuid,
) -> Result(pog.Returned(CollectionFindByIdRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use name <- decode.field(2, decode.string)
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use private <- decode.field(5, decode.bool)
    decode.success(CollectionFindByIdRow(
      id:,
      public_id:,
      name:,
      description:,
      creator:,
      private:,
    ))
  }

  "SELECT *
FROM collections
WHERE id = $1
LIMIT 1;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(id)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `collection_find_by_public_id` query
/// defined in `./src/server/sql/collection_find_by_public_id.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CollectionFindByPublicIdRow {
  CollectionFindByPublicIdRow(
    id: Uuid,
    public_id: String,
    name: String,
    description: Option(String),
    creator: Uuid,
    private: Bool,
  )
}

/// Runs the `collection_find_by_public_id` query
/// defined in `./src/server/sql/collection_find_by_public_id.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn collection_find_by_public_id(
  db: pog.Connection,
  public_id: String,
) -> Result(pog.Returned(CollectionFindByPublicIdRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use name <- decode.field(2, decode.string)
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use private <- decode.field(5, decode.bool)
    decode.success(CollectionFindByPublicIdRow(
      id:,
      public_id:,
      name:,
      description:,
      creator:,
      private:,
    ))
  }

  "SELECT *
FROM collections
WHERE public_id = $1
LIMIT 1;
"
  |> pog.query
  |> pog.parameter(pog.text(public_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `collection_photos_list` query
/// defined in `./src/server/sql/collection_photos_list.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CollectionPhotosListRow {
  CollectionPhotosListRow(
    id: Uuid,
    public_id: String,
    asset_id: Uuid,
    description: Option(String),
    creator: Uuid,
    file_size: Int,
    privacy: PhotoPrivacy,
    show_on_profile: Bool,
    mimetype: Mimetype,
    location: Option(String),
    camera: Option(String),
    likes_count: Int,
    views: Int,
    downloads: Int,
    created_at: Timestamp,
  )
}

/// Runs the `collection_photos_list` query
/// defined in `./src/server/sql/collection_photos_list.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn collection_photos_list(
  db: pog.Connection,
  arg_1: Uuid,
) -> Result(pog.Returned(CollectionPhotosListRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use asset_id <- decode.field(2, uuid_decoder())
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use file_size <- decode.field(5, decode.int)
    use privacy <- decode.field(6, photo_privacy_decoder())
    use show_on_profile <- decode.field(7, decode.bool)
    use mimetype <- decode.field(8, mimetype_decoder())
    use location <- decode.field(9, decode.optional(decode.string))
    use camera <- decode.field(10, decode.optional(decode.string))
    use likes_count <- decode.field(11, decode.int)
    use views <- decode.field(12, decode.int)
    use downloads <- decode.field(13, decode.int)
    use created_at <- decode.field(14, pog.timestamp_decoder())
    decode.success(CollectionPhotosListRow(
      id:,
      public_id:,
      asset_id:,
      description:,
      creator:,
      file_size:,
      privacy:,
      show_on_profile:,
      mimetype:,
      location:,
      camera:,
      likes_count:,
      views:,
      downloads:,
      created_at:,
    ))
  }

  "SELECT p.* 
FROM collections_photos cp
JOIN photos p ON p.id = cp.photo_id
WHERE cp.collection_id = $1;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `collection_remove_photo` query
/// defined in `./src/server/sql/collection_remove_photo.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CollectionRemovePhotoRow {
  CollectionRemovePhotoRow(photo_id: Uuid, collection_id: Uuid)
}

/// Runs the `collection_remove_photo` query
/// defined in `./src/server/sql/collection_remove_photo.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn collection_remove_photo(
  db: pog.Connection,
  photo_id: Uuid,
  collection_id: Uuid,
) -> Result(pog.Returned(CollectionRemovePhotoRow), pog.QueryError) {
  let decoder = {
    use photo_id <- decode.field(0, uuid_decoder())
    use collection_id <- decode.field(1, uuid_decoder())
    decode.success(CollectionRemovePhotoRow(photo_id:, collection_id:))
  }

  "DELETE FROM collections_photos
WHERE photo_id = $1 AND collection_id = $2
RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(photo_id)))
  |> pog.parameter(pog.text(uuid.to_string(collection_id)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `collection_update` query
/// defined in `./src/server/sql/collection_update.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CollectionUpdateRow {
  CollectionUpdateRow(
    id: Uuid,
    public_id: String,
    name: String,
    description: Option(String),
    creator: Uuid,
    private: Bool,
  )
}

/// Runs the `collection_update` query
/// defined in `./src/server/sql/collection_update.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn collection_update(
  db: pog.Connection,
  id: Uuid,
  arg_2: String,
  arg_3: String,
  private: Bool,
  creator: Uuid,
) -> Result(pog.Returned(CollectionUpdateRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use name <- decode.field(2, decode.string)
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use private <- decode.field(5, decode.bool)
    decode.success(CollectionUpdateRow(
      id:,
      public_id:,
      name:,
      description:,
      creator:,
      private:,
    ))
  }

  "UPDATE collections
SET name = $2, description = $3, private = $4
WHERE id = $1 AND creator = $5
RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(id)))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.bool(private))
  |> pog.parameter(pog.text(uuid.to_string(creator)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `photo_add_tag` query
/// defined in `./src/server/sql/photo_add_tag.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PhotoAddTagRow {
  PhotoAddTagRow(tag: String, photo_id: Uuid)
}

/// Runs the `photo_add_tag` query
/// defined in `./src/server/sql/photo_add_tag.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn photo_add_tag(
  db: pog.Connection,
  arg_1: String,
  arg_2: Uuid,
) -> Result(pog.Returned(PhotoAddTagRow), pog.QueryError) {
  let decoder = {
    use tag <- decode.field(0, decode.string)
    use photo_id <- decode.field(1, uuid_decoder())
    decode.success(PhotoAddTagRow(tag:, photo_id:))
  }

  "WITH inserted_tag AS (
    INSERT INTO tags (tag) VALUES ($1) ON CONFLICT DO NOTHING
)
INSERT INTO photos_tags (tag, photo_id) VALUES ($1, $2) ON CONFLICT DO NOTHING
RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `photo_add_tags_batch` query
/// defined in `./src/server/sql/photo_add_tags_batch.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PhotoAddTagsBatchRow {
  PhotoAddTagsBatchRow(tag: String, photo_id: Uuid)
}

/// Runs the `photo_add_tags_batch` query
/// defined in `./src/server/sql/photo_add_tags_batch.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn photo_add_tags_batch(
  db: pog.Connection,
  arg_1: List(String),
  arg_2: Uuid,
) -> Result(pog.Returned(PhotoAddTagsBatchRow), pog.QueryError) {
  let decoder = {
    use tag <- decode.field(0, decode.string)
    use photo_id <- decode.field(1, uuid_decoder())
    decode.success(PhotoAddTagsBatchRow(tag:, photo_id:))
  }

  "WITH unnested_tags AS (
    SELECT unnest($1::text[]) AS tag
),
inserted_tags AS (
    INSERT INTO tags (tag)
    SELECT tag FROM unnested_tags
    ON CONFLICT DO NOTHING
)
INSERT INTO photos_tags (tag, photo_id)
SELECT tag, $2 FROM unnested_tags
ON CONFLICT DO NOTHING
RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_1))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `photo_create` query
/// defined in `./src/server/sql/photo_create.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PhotoCreateRow {
  PhotoCreateRow(
    id: Uuid,
    public_id: String,
    asset_id: Uuid,
    description: Option(String),
    creator: Uuid,
    file_size: Int,
    privacy: PhotoPrivacy,
    show_on_profile: Bool,
    mimetype: Mimetype,
    location: Option(String),
    camera: Option(String),
    likes_count: Int,
    views: Int,
    downloads: Int,
    created_at: Timestamp,
  )
}

/// Runs the `photo_create` query
/// defined in `./src/server/sql/photo_create.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn photo_create(
  db: pog.Connection,
  arg_1: String,
  id: Uuid,
  arg_3: PhotoPrivacy,
  arg_4: String,
  arg_5: String,
  arg_6: Bool,
  arg_7: Int,
  arg_8: Mimetype,
  arg_9: String,
) -> Result(pog.Returned(PhotoCreateRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use asset_id <- decode.field(2, uuid_decoder())
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use file_size <- decode.field(5, decode.int)
    use privacy <- decode.field(6, photo_privacy_decoder())
    use show_on_profile <- decode.field(7, decode.bool)
    use mimetype <- decode.field(8, mimetype_decoder())
    use location <- decode.field(9, decode.optional(decode.string))
    use camera <- decode.field(10, decode.optional(decode.string))
    use likes_count <- decode.field(11, decode.int)
    use views <- decode.field(12, decode.int)
    use downloads <- decode.field(13, decode.int)
    use created_at <- decode.field(14, pog.timestamp_decoder())
    decode.success(PhotoCreateRow(
      id:,
      public_id:,
      asset_id:,
      description:,
      creator:,
      file_size:,
      privacy:,
      show_on_profile:,
      mimetype:,
      location:,
      camera:,
      likes_count:,
      views:,
      downloads:,
      created_at:,
    ))
  }

  "WITH updated_user AS (
     UPDATE users
     SET storage_quota_used = storage_quota_used + $7
     WHERE id = $2
)
INSERT INTO photos (description, creator, privacy, location, camera, show_on_profile, file_size, mimetype, public_id)
VALUES (nullif($1,''),
	$2,
	$3,
	nullif($4,''),
	nullif($5,''),
	$6,
	$7,
	$8,
	$9)
RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(uuid.to_string(id)))
  |> pog.parameter(photo_privacy_encoder(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.parameter(pog.bool(arg_6))
  |> pog.parameter(pog.int(arg_7))
  |> pog.parameter(mimetype_encoder(arg_8))
  |> pog.parameter(pog.text(arg_9))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `photo_delete` query
/// defined in `./src/server/sql/photo_delete.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PhotoDeleteRow {
  PhotoDeleteRow(
    id: Uuid,
    public_id: String,
    asset_id: Uuid,
    description: Option(String),
    creator: Uuid,
    file_size: Int,
    privacy: PhotoPrivacy,
    show_on_profile: Bool,
    mimetype: Mimetype,
    location: Option(String),
    camera: Option(String),
    likes_count: Int,
    views: Int,
    downloads: Int,
    created_at: Timestamp,
  )
}

/// Runs the `photo_delete` query
/// defined in `./src/server/sql/photo_delete.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn photo_delete(
  db: pog.Connection,
  public_id: String,
  creator: Uuid,
) -> Result(pog.Returned(PhotoDeleteRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use asset_id <- decode.field(2, uuid_decoder())
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use file_size <- decode.field(5, decode.int)
    use privacy <- decode.field(6, photo_privacy_decoder())
    use show_on_profile <- decode.field(7, decode.bool)
    use mimetype <- decode.field(8, mimetype_decoder())
    use location <- decode.field(9, decode.optional(decode.string))
    use camera <- decode.field(10, decode.optional(decode.string))
    use likes_count <- decode.field(11, decode.int)
    use views <- decode.field(12, decode.int)
    use downloads <- decode.field(13, decode.int)
    use created_at <- decode.field(14, pog.timestamp_decoder())
    decode.success(PhotoDeleteRow(
      id:,
      public_id:,
      asset_id:,
      description:,
      creator:,
      file_size:,
      privacy:,
      show_on_profile:,
      mimetype:,
      location:,
      camera:,
      likes_count:,
      views:,
      downloads:,
      created_at:,
    ))
  }

  "DELETE FROM photos
WHERE public_id = $1 AND creator = $2
RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(public_id))
  |> pog.parameter(pog.text(uuid.to_string(creator)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `photo_find_by_asset_id` query
/// defined in `./src/server/sql/photo_find_by_asset_id.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PhotoFindByAssetIdRow {
  PhotoFindByAssetIdRow(
    id: Uuid,
    public_id: String,
    asset_id: Uuid,
    description: Option(String),
    creator: Uuid,
    file_size: Int,
    privacy: PhotoPrivacy,
    show_on_profile: Bool,
    mimetype: Mimetype,
    location: Option(String),
    camera: Option(String),
    likes_count: Int,
    views: Int,
    downloads: Int,
    created_at: Timestamp,
  )
}

/// Runs the `photo_find_by_asset_id` query
/// defined in `./src/server/sql/photo_find_by_asset_id.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn photo_find_by_asset_id(
  db: pog.Connection,
  asset_id: Uuid,
) -> Result(pog.Returned(PhotoFindByAssetIdRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use asset_id <- decode.field(2, uuid_decoder())
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use file_size <- decode.field(5, decode.int)
    use privacy <- decode.field(6, photo_privacy_decoder())
    use show_on_profile <- decode.field(7, decode.bool)
    use mimetype <- decode.field(8, mimetype_decoder())
    use location <- decode.field(9, decode.optional(decode.string))
    use camera <- decode.field(10, decode.optional(decode.string))
    use likes_count <- decode.field(11, decode.int)
    use views <- decode.field(12, decode.int)
    use downloads <- decode.field(13, decode.int)
    use created_at <- decode.field(14, pog.timestamp_decoder())
    decode.success(PhotoFindByAssetIdRow(
      id:,
      public_id:,
      asset_id:,
      description:,
      creator:,
      file_size:,
      privacy:,
      show_on_profile:,
      mimetype:,
      location:,
      camera:,
      likes_count:,
      views:,
      downloads:,
      created_at:,
    ))
  }

  "SELECT *
FROM photos
WHERE asset_id = $1
LIMIT 1;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(asset_id)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `photo_find_by_id` query
/// defined in `./src/server/sql/photo_find_by_id.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PhotoFindByIdRow {
  PhotoFindByIdRow(
    id: Uuid,
    public_id: String,
    asset_id: Uuid,
    description: Option(String),
    creator: Uuid,
    file_size: Int,
    privacy: PhotoPrivacy,
    show_on_profile: Bool,
    mimetype: Mimetype,
    location: Option(String),
    camera: Option(String),
    likes_count: Int,
    views: Int,
    downloads: Int,
    created_at: Timestamp,
  )
}

/// Runs the `photo_find_by_id` query
/// defined in `./src/server/sql/photo_find_by_id.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn photo_find_by_id(
  db: pog.Connection,
  id: Uuid,
) -> Result(pog.Returned(PhotoFindByIdRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use asset_id <- decode.field(2, uuid_decoder())
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use file_size <- decode.field(5, decode.int)
    use privacy <- decode.field(6, photo_privacy_decoder())
    use show_on_profile <- decode.field(7, decode.bool)
    use mimetype <- decode.field(8, mimetype_decoder())
    use location <- decode.field(9, decode.optional(decode.string))
    use camera <- decode.field(10, decode.optional(decode.string))
    use likes_count <- decode.field(11, decode.int)
    use views <- decode.field(12, decode.int)
    use downloads <- decode.field(13, decode.int)
    use created_at <- decode.field(14, pog.timestamp_decoder())
    decode.success(PhotoFindByIdRow(
      id:,
      public_id:,
      asset_id:,
      description:,
      creator:,
      file_size:,
      privacy:,
      show_on_profile:,
      mimetype:,
      location:,
      camera:,
      likes_count:,
      views:,
      downloads:,
      created_at:,
    ))
  }

  "SELECT *
FROM photos
WHERE id = $1
LIMIT 1;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(id)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `photo_find_by_public_id` query
/// defined in `./src/server/sql/photo_find_by_public_id.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PhotoFindByPublicIdRow {
  PhotoFindByPublicIdRow(
    id: Uuid,
    public_id: String,
    asset_id: Uuid,
    description: Option(String),
    creator: Uuid,
    file_size: Int,
    privacy: PhotoPrivacy,
    show_on_profile: Bool,
    mimetype: Mimetype,
    location: Option(String),
    camera: Option(String),
    likes_count: Int,
    views: Int,
    downloads: Int,
    created_at: Timestamp,
  )
}

/// Runs the `photo_find_by_public_id` query
/// defined in `./src/server/sql/photo_find_by_public_id.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn photo_find_by_public_id(
  db: pog.Connection,
  public_id: String,
) -> Result(pog.Returned(PhotoFindByPublicIdRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use asset_id <- decode.field(2, uuid_decoder())
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use file_size <- decode.field(5, decode.int)
    use privacy <- decode.field(6, photo_privacy_decoder())
    use show_on_profile <- decode.field(7, decode.bool)
    use mimetype <- decode.field(8, mimetype_decoder())
    use location <- decode.field(9, decode.optional(decode.string))
    use camera <- decode.field(10, decode.optional(decode.string))
    use likes_count <- decode.field(11, decode.int)
    use views <- decode.field(12, decode.int)
    use downloads <- decode.field(13, decode.int)
    use created_at <- decode.field(14, pog.timestamp_decoder())
    decode.success(PhotoFindByPublicIdRow(
      id:,
      public_id:,
      asset_id:,
      description:,
      creator:,
      file_size:,
      privacy:,
      show_on_profile:,
      mimetype:,
      location:,
      camera:,
      likes_count:,
      views:,
      downloads:,
      created_at:,
    ))
  }

  "SELECT *
FROM photos
WHERE public_id = $1
LIMIT 1;
"
  |> pog.query
  |> pog.parameter(pog.text(public_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `photo_remove_all_tags` query
/// defined in `./src/server/sql/photo_remove_all_tags.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn photo_remove_all_tags(
  db: pog.Connection,
  arg_1: Uuid,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "DELETE FROM photos_tags
WHERE photo_id = $1;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `photo_remove_tag` query
/// defined in `./src/server/sql/photo_remove_tag.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PhotoRemoveTagRow {
  PhotoRemoveTagRow(tag: String, photo_id: Uuid)
}

/// Runs the `photo_remove_tag` query
/// defined in `./src/server/sql/photo_remove_tag.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn photo_remove_tag(
  db: pog.Connection,
  tag: String,
  photo_id: Uuid,
) -> Result(pog.Returned(PhotoRemoveTagRow), pog.QueryError) {
  let decoder = {
    use tag <- decode.field(0, decode.string)
    use photo_id <- decode.field(1, uuid_decoder())
    decode.success(PhotoRemoveTagRow(tag:, photo_id:))
  }

  "DELETE FROM photos_tags
WHERE tag = $1 AND photo_id = $2
RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(tag))
  |> pog.parameter(pog.text(uuid.to_string(photo_id)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `photo_update` query
/// defined in `./src/server/sql/photo_update.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PhotoUpdateRow {
  PhotoUpdateRow(
    id: Uuid,
    public_id: String,
    asset_id: Uuid,
    description: Option(String),
    creator: Uuid,
    file_size: Int,
    privacy: PhotoPrivacy,
    show_on_profile: Bool,
    mimetype: Mimetype,
    location: Option(String),
    camera: Option(String),
    likes_count: Int,
    views: Int,
    downloads: Int,
    created_at: Timestamp,
  )
}

/// Runs the `photo_update` query
/// defined in `./src/server/sql/photo_update.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn photo_update(
  db: pog.Connection,
  public_id: String,
  arg_2: String,
  arg_3: String,
  arg_4: String,
  arg_5: PhotoPrivacy,
  show_on_profile: Bool,
  creator: Uuid,
) -> Result(pog.Returned(PhotoUpdateRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use asset_id <- decode.field(2, uuid_decoder())
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use file_size <- decode.field(5, decode.int)
    use privacy <- decode.field(6, photo_privacy_decoder())
    use show_on_profile <- decode.field(7, decode.bool)
    use mimetype <- decode.field(8, mimetype_decoder())
    use location <- decode.field(9, decode.optional(decode.string))
    use camera <- decode.field(10, decode.optional(decode.string))
    use likes_count <- decode.field(11, decode.int)
    use views <- decode.field(12, decode.int)
    use downloads <- decode.field(13, decode.int)
    use created_at <- decode.field(14, pog.timestamp_decoder())
    decode.success(PhotoUpdateRow(
      id:,
      public_id:,
      asset_id:,
      description:,
      creator:,
      file_size:,
      privacy:,
      show_on_profile:,
      mimetype:,
      location:,
      camera:,
      likes_count:,
      views:,
      downloads:,
      created_at:,
    ))
  }

  "UPDATE photos
SET description = $2, location = $3, camera = $4, privacy = $5, show_on_profile = $6
WHERE public_id = $1 AND creator = $7
RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(public_id))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(photo_privacy_encoder(arg_5))
  |> pog.parameter(pog.bool(show_on_profile))
  |> pog.parameter(pog.text(uuid.to_string(creator)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `photos_list_by_owner` query
/// defined in `./src/server/sql/photos_list_by_owner.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PhotosListByOwnerRow {
  PhotosListByOwnerRow(
    id: Uuid,
    public_id: String,
    asset_id: Uuid,
    description: Option(String),
    creator: Uuid,
    file_size: Int,
    privacy: PhotoPrivacy,
    show_on_profile: Bool,
    mimetype: Mimetype,
    location: Option(String),
    camera: Option(String),
    likes_count: Int,
    views: Int,
    downloads: Int,
    created_at: Timestamp,
  )
}

/// Runs the `photos_list_by_owner` query
/// defined in `./src/server/sql/photos_list_by_owner.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn photos_list_by_owner(
  db: pog.Connection,
  arg_1: Uuid,
) -> Result(pog.Returned(PhotosListByOwnerRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use asset_id <- decode.field(2, uuid_decoder())
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use file_size <- decode.field(5, decode.int)
    use privacy <- decode.field(6, photo_privacy_decoder())
    use show_on_profile <- decode.field(7, decode.bool)
    use mimetype <- decode.field(8, mimetype_decoder())
    use location <- decode.field(9, decode.optional(decode.string))
    use camera <- decode.field(10, decode.optional(decode.string))
    use likes_count <- decode.field(11, decode.int)
    use views <- decode.field(12, decode.int)
    use downloads <- decode.field(13, decode.int)
    use created_at <- decode.field(14, pog.timestamp_decoder())
    decode.success(PhotosListByOwnerRow(
      id:,
      public_id:,
      asset_id:,
      description:,
      creator:,
      file_size:,
      privacy:,
      show_on_profile:,
      mimetype:,
      location:,
      camera:,
      likes_count:,
      views:,
      downloads:,
      created_at:,
    ))
  }

  "SELECT *
FROM photos
WHERE creator = $1;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `photos_list_by_tag` query
/// defined in `./src/server/sql/photos_list_by_tag.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PhotosListByTagRow {
  PhotosListByTagRow(public_id: String)
}

/// Runs the `photos_list_by_tag` query
/// defined in `./src/server/sql/photos_list_by_tag.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn photos_list_by_tag(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(PhotosListByTagRow), pog.QueryError) {
  let decoder = {
    use public_id <- decode.field(0, decode.string)
    decode.success(PhotosListByTagRow(public_id:))
  }

  "SELECT photos.public_id
FROM photos
JOIN photos_tags ON photos.id = photos_tags.photo_id
WHERE photos_tags.tag = $1;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `photos_list_by_user` query
/// defined in `./src/server/sql/photos_list_by_user.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PhotosListByUserRow {
  PhotosListByUserRow(
    id: Uuid,
    public_id: String,
    asset_id: Uuid,
    description: Option(String),
    creator: Uuid,
    file_size: Int,
    privacy: PhotoPrivacy,
    show_on_profile: Bool,
    mimetype: Mimetype,
    location: Option(String),
    camera: Option(String),
    likes_count: Int,
    views: Int,
    downloads: Int,
    created_at: Timestamp,
  )
}

/// Runs the `photos_list_by_user` query
/// defined in `./src/server/sql/photos_list_by_user.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn photos_list_by_user(
  db: pog.Connection,
  creator: Uuid,
) -> Result(pog.Returned(PhotosListByUserRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use asset_id <- decode.field(2, uuid_decoder())
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use file_size <- decode.field(5, decode.int)
    use privacy <- decode.field(6, photo_privacy_decoder())
    use show_on_profile <- decode.field(7, decode.bool)
    use mimetype <- decode.field(8, mimetype_decoder())
    use location <- decode.field(9, decode.optional(decode.string))
    use camera <- decode.field(10, decode.optional(decode.string))
    use likes_count <- decode.field(11, decode.int)
    use views <- decode.field(12, decode.int)
    use downloads <- decode.field(13, decode.int)
    use created_at <- decode.field(14, pog.timestamp_decoder())
    decode.success(PhotosListByUserRow(
      id:,
      public_id:,
      asset_id:,
      description:,
      creator:,
      file_size:,
      privacy:,
      show_on_profile:,
      mimetype:,
      location:,
      camera:,
      likes_count:,
      views:,
      downloads:,
      created_at:,
    ))
  }

  "SELECT *
FROM photos
WHERE creator = $1
AND show_on_profile = true;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(creator)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `photos_list_by_user_cursor_date` query
/// defined in `./src/server/sql/photos_list_by_user_cursor_date.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PhotosListByUserCursorDateRow {
  PhotosListByUserCursorDateRow(
    public_id: String,
    asset_id: Uuid,
    description: Option(String),
    creator: Uuid,
    privacy: PhotoPrivacy,
    show_on_profile: Bool,
    location: Option(String),
    camera: Option(String),
    likes_count: Int,
    views: Int,
    downloads: Int,
    created_at: Timestamp,
    file_size: Int,
  )
}

/// Runs the `photos_list_by_user_cursor_date` query
/// defined in `./src/server/sql/photos_list_by_user_cursor_date.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn photos_list_by_user_cursor_date(
  db: pog.Connection,
  creator: Uuid,
  show_on_profile: Bool,
  arg_3: Timestamp,
) -> Result(pog.Returned(PhotosListByUserCursorDateRow), pog.QueryError) {
  let decoder = {
    use public_id <- decode.field(0, decode.string)
    use asset_id <- decode.field(1, uuid_decoder())
    use description <- decode.field(2, decode.optional(decode.string))
    use creator <- decode.field(3, uuid_decoder())
    use privacy <- decode.field(4, photo_privacy_decoder())
    use show_on_profile <- decode.field(5, decode.bool)
    use location <- decode.field(6, decode.optional(decode.string))
    use camera <- decode.field(7, decode.optional(decode.string))
    use likes_count <- decode.field(8, decode.int)
    use views <- decode.field(9, decode.int)
    use downloads <- decode.field(10, decode.int)
    use created_at <- decode.field(11, pog.timestamp_decoder())
    use file_size <- decode.field(12, decode.int)
    decode.success(PhotosListByUserCursorDateRow(
      public_id:,
      asset_id:,
      description:,
      creator:,
      privacy:,
      show_on_profile:,
      location:,
      camera:,
      likes_count:,
      views:,
      downloads:,
      created_at:,
      file_size:,
    ))
  }

  "SELECT 
    public_id,
    asset_id,
    description,
    creator,
    privacy,
    show_on_profile,
    location,
    camera,
    likes_count,
    views,
    downloads,
    created_at,
    file_size
FROM photos
WHERE creator = $1 
  AND show_on_profile = $2
  AND created_at < $3 -- $3 is the timestamp of the last photo they saw
ORDER BY created_at DESC
LIMIT 50;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(creator)))
  |> pog.parameter(pog.bool(show_on_profile))
  |> pog.parameter(pog.timestamp(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `tags_list_by_photo` query
/// defined in `./src/server/sql/tags_list_by_photo.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type TagsListByPhotoRow {
  TagsListByPhotoRow(tag: String)
}

/// Runs the `tags_list_by_photo` query
/// defined in `./src/server/sql/tags_list_by_photo.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn tags_list_by_photo(
  db: pog.Connection,
  arg_1: Uuid,
) -> Result(pog.Returned(TagsListByPhotoRow), pog.QueryError) {
  let decoder = {
    use tag <- decode.field(0, decode.string)
    decode.success(TagsListByPhotoRow(tag:))
  }

  "SELECT tag
FROM photos_tags
WHERE photo_id = $1;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `user_collections_for_photo` query
/// defined in `./src/server/sql/user_collections_for_photo.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UserCollectionsForPhotoRow {
  UserCollectionsForPhotoRow(collection_id: Uuid)
}

/// Runs the `user_collections_for_photo` query
/// defined in `./src/server/sql/user_collections_for_photo.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn user_collections_for_photo(
  db: pog.Connection,
  collections_creator: Uuid,
  arg_2: Uuid,
) -> Result(pog.Returned(UserCollectionsForPhotoRow), pog.QueryError) {
  let decoder = {
    use collection_id <- decode.field(0, uuid_decoder())
    decode.success(UserCollectionsForPhotoRow(collection_id:))
  }

  "SELECT collection_id
FROM collections_photos
JOIN collections ON collections.id = collections_photos.collection_id
WHERE collections.creator = $1 AND collections_photos.photo_id = $2;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(collections_creator)))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `user_collections_list` query
/// defined in `./src/server/sql/user_collections_list.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UserCollectionsListRow {
  UserCollectionsListRow(
    id: Uuid,
    public_id: String,
    name: String,
    description: Option(String),
    creator: Uuid,
    private: Bool,
  )
}

/// Runs the `user_collections_list` query
/// defined in `./src/server/sql/user_collections_list.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn user_collections_list(
  db: pog.Connection,
  creator: Uuid,
) -> Result(pog.Returned(UserCollectionsListRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use name <- decode.field(2, decode.string)
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use private <- decode.field(5, decode.bool)
    decode.success(UserCollectionsListRow(
      id:,
      public_id:,
      name:,
      description:,
      creator:,
      private:,
    ))
  }

  "SELECT *
FROM collections
WHERE creator = $1
ORDER BY id DESC;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(creator)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `user_create` query
/// defined in `./src/server/sql/user_create.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UserCreateRow {
  UserCreateRow(
    id: Uuid,
    username: String,
    first_name: String,
    last_name: Option(String),
    bio: Option(String),
    available_for_hire: Bool,
    premium: Bool,
    password: String,
    created_at: Timestamp,
    updated_at: Timestamp,
    storage_quota: Int,
    storage_quota_used: Int,
  )
}

/// Runs the `user_create` query
/// defined in `./src/server/sql/user_create.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn user_create(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: String,
  arg_4: String,
  arg_5: String,
  arg_6: Bool,
) -> Result(pog.Returned(UserCreateRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use username <- decode.field(1, decode.string)
    use first_name <- decode.field(2, decode.string)
    use last_name <- decode.field(3, decode.optional(decode.string))
    use bio <- decode.field(4, decode.optional(decode.string))
    use available_for_hire <- decode.field(5, decode.bool)
    use premium <- decode.field(6, decode.bool)
    use password <- decode.field(7, decode.string)
    use created_at <- decode.field(8, pog.timestamp_decoder())
    use updated_at <- decode.field(9, pog.timestamp_decoder())
    use storage_quota <- decode.field(10, decode.int)
    use storage_quota_used <- decode.field(11, decode.int)
    decode.success(UserCreateRow(
      id:,
      username:,
      first_name:,
      last_name:,
      bio:,
      available_for_hire:,
      premium:,
      password:,
      created_at:,
      updated_at:,
      storage_quota:,
      storage_quota_used:,
    ))
  }

  "INSERT INTO users (username, first_name, last_name, password, bio, available_for_hire)
VALUES ($1,
	$2,
       	nullif($3,''),
	$4,
	nullif($5,''),
	$6
)
RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.parameter(pog.bool(arg_6))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `user_find_by_id` query
/// defined in `./src/server/sql/user_find_by_id.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UserFindByIdRow {
  UserFindByIdRow(
    id: Uuid,
    username: String,
    first_name: String,
    last_name: Option(String),
    bio: Option(String),
    available_for_hire: Bool,
    premium: Bool,
    password: String,
    created_at: Timestamp,
    updated_at: Timestamp,
    storage_quota: Int,
    storage_quota_used: Int,
  )
}

/// Runs the `user_find_by_id` query
/// defined in `./src/server/sql/user_find_by_id.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn user_find_by_id(
  db: pog.Connection,
  id: Uuid,
) -> Result(pog.Returned(UserFindByIdRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use username <- decode.field(1, decode.string)
    use first_name <- decode.field(2, decode.string)
    use last_name <- decode.field(3, decode.optional(decode.string))
    use bio <- decode.field(4, decode.optional(decode.string))
    use available_for_hire <- decode.field(5, decode.bool)
    use premium <- decode.field(6, decode.bool)
    use password <- decode.field(7, decode.string)
    use created_at <- decode.field(8, pog.timestamp_decoder())
    use updated_at <- decode.field(9, pog.timestamp_decoder())
    use storage_quota <- decode.field(10, decode.int)
    use storage_quota_used <- decode.field(11, decode.int)
    decode.success(UserFindByIdRow(
      id:,
      username:,
      first_name:,
      last_name:,
      bio:,
      available_for_hire:,
      premium:,
      password:,
      created_at:,
      updated_at:,
      storage_quota:,
      storage_quota_used:,
    ))
  }

  "SELECT *
FROM users
WHERE id=$1
LIMIT 1;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(id)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `user_find_by_name` query
/// defined in `./src/server/sql/user_find_by_name.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UserFindByNameRow {
  UserFindByNameRow(
    id: Uuid,
    username: String,
    first_name: String,
    last_name: Option(String),
    bio: Option(String),
    available_for_hire: Bool,
    premium: Bool,
    password: String,
    created_at: Timestamp,
    updated_at: Timestamp,
    storage_quota: Int,
    storage_quota_used: Int,
  )
}

/// Runs the `user_find_by_name` query
/// defined in `./src/server/sql/user_find_by_name.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn user_find_by_name(
  db: pog.Connection,
  username: String,
) -> Result(pog.Returned(UserFindByNameRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use username <- decode.field(1, decode.string)
    use first_name <- decode.field(2, decode.string)
    use last_name <- decode.field(3, decode.optional(decode.string))
    use bio <- decode.field(4, decode.optional(decode.string))
    use available_for_hire <- decode.field(5, decode.bool)
    use premium <- decode.field(6, decode.bool)
    use password <- decode.field(7, decode.string)
    use created_at <- decode.field(8, pog.timestamp_decoder())
    use updated_at <- decode.field(9, pog.timestamp_decoder())
    use storage_quota <- decode.field(10, decode.int)
    use storage_quota_used <- decode.field(11, decode.int)
    decode.success(UserFindByNameRow(
      id:,
      username:,
      first_name:,
      last_name:,
      bio:,
      available_for_hire:,
      premium:,
      password:,
      created_at:,
      updated_at:,
      storage_quota:,
      storage_quota_used:,
    ))
  }

  "SELECT *
FROM users
WHERE username = $1
LIMIT 1;
"
  |> pog.query
  |> pog.parameter(pog.text(username))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `user_liked_photo` query
/// defined in `./src/server/sql/user_liked_photo.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UserLikedPhotoRow {
  UserLikedPhotoRow(user_liked: Bool)
}

/// Runs the `user_liked_photo` query
/// defined in `./src/server/sql/user_liked_photo.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn user_liked_photo(
  db: pog.Connection,
  user_id: Uuid,
  arg_2: Uuid,
) -> Result(pog.Returned(UserLikedPhotoRow), pog.QueryError) {
  let decoder = {
    use user_liked <- decode.field(0, decode.bool)
    decode.success(UserLikedPhotoRow(user_liked:))
  }

  "SELECT true AS user_liked
FROM likes
WHERE user_id = $1 
AND photo_id = $2;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(user_id)))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `user_likes_photo_add` query
/// defined in `./src/server/sql/user_likes_photo_add.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UserLikesPhotoAddRow {
  UserLikesPhotoAddRow(
    id: Uuid,
    public_id: String,
    asset_id: Uuid,
    description: Option(String),
    creator: Uuid,
    file_size: Int,
    privacy: PhotoPrivacy,
    show_on_profile: Bool,
    mimetype: Mimetype,
    location: Option(String),
    camera: Option(String),
    likes_count: Int,
    views: Int,
    downloads: Int,
    created_at: Timestamp,
  )
}

/// Runs the `user_likes_photo_add` query
/// defined in `./src/server/sql/user_likes_photo_add.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn user_likes_photo_add(
  db: pog.Connection,
  arg_1: Uuid,
  arg_2: Uuid,
) -> Result(pog.Returned(UserLikesPhotoAddRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use asset_id <- decode.field(2, uuid_decoder())
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use file_size <- decode.field(5, decode.int)
    use privacy <- decode.field(6, photo_privacy_decoder())
    use show_on_profile <- decode.field(7, decode.bool)
    use mimetype <- decode.field(8, mimetype_decoder())
    use location <- decode.field(9, decode.optional(decode.string))
    use camera <- decode.field(10, decode.optional(decode.string))
    use likes_count <- decode.field(11, decode.int)
    use views <- decode.field(12, decode.int)
    use downloads <- decode.field(13, decode.int)
    use created_at <- decode.field(14, pog.timestamp_decoder())
    decode.success(UserLikesPhotoAddRow(
      id:,
      public_id:,
      asset_id:,
      description:,
      creator:,
      file_size:,
      privacy:,
      show_on_profile:,
      mimetype:,
      location:,
      camera:,
      likes_count:,
      views:,
      downloads:,
      created_at:,
    ))
  }

  "WITH new_like AS (
    INSERT INTO likes (user_id, photo_id)
    VALUES ($1, $2)
    ON CONFLICT (user_id, photo_id) DO NOTHING
    RETURNING photo_id
)
UPDATE photos
SET likes_count = likes_count + 1
FROM new_like
WHERE photos.id = new_like.photo_id
RETURNING photos.*;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.parameter(pog.text(uuid.to_string(arg_2)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `user_likes_photo_remove` query
/// defined in `./src/server/sql/user_likes_photo_remove.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UserLikesPhotoRemoveRow {
  UserLikesPhotoRemoveRow(
    id: Uuid,
    public_id: String,
    asset_id: Uuid,
    description: Option(String),
    creator: Uuid,
    file_size: Int,
    privacy: PhotoPrivacy,
    show_on_profile: Bool,
    mimetype: Mimetype,
    location: Option(String),
    camera: Option(String),
    likes_count: Int,
    views: Int,
    downloads: Int,
    created_at: Timestamp,
  )
}

/// Runs the `user_likes_photo_remove` query
/// defined in `./src/server/sql/user_likes_photo_remove.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn user_likes_photo_remove(
  db: pog.Connection,
  user_id: Uuid,
  photo_id: Uuid,
) -> Result(pog.Returned(UserLikesPhotoRemoveRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use public_id <- decode.field(1, decode.string)
    use asset_id <- decode.field(2, uuid_decoder())
    use description <- decode.field(3, decode.optional(decode.string))
    use creator <- decode.field(4, uuid_decoder())
    use file_size <- decode.field(5, decode.int)
    use privacy <- decode.field(6, photo_privacy_decoder())
    use show_on_profile <- decode.field(7, decode.bool)
    use mimetype <- decode.field(8, mimetype_decoder())
    use location <- decode.field(9, decode.optional(decode.string))
    use camera <- decode.field(10, decode.optional(decode.string))
    use likes_count <- decode.field(11, decode.int)
    use views <- decode.field(12, decode.int)
    use downloads <- decode.field(13, decode.int)
    use created_at <- decode.field(14, pog.timestamp_decoder())
    decode.success(UserLikesPhotoRemoveRow(
      id:,
      public_id:,
      asset_id:,
      description:,
      creator:,
      file_size:,
      privacy:,
      show_on_profile:,
      mimetype:,
      location:,
      camera:,
      likes_count:,
      views:,
      downloads:,
      created_at:,
    ))
  }

  "WITH deleted_like AS (
    DELETE FROM likes 
    WHERE user_id = $1 AND photo_id = $2
    RETURNING photo_id
)
UPDATE photos
SET likes_count = likes_count - 1 
FROM deleted_like
WHERE photos.id = deleted_like.photo_id
RETURNING photos.*;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(user_id)))
  |> pog.parameter(pog.text(uuid.to_string(photo_id)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `user_list_likes` query
/// defined in `./src/server/sql/user_list_likes.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UserListLikesRow {
  UserListLikesRow(photo_id: Uuid)
}

/// Runs the `user_list_likes` query
/// defined in `./src/server/sql/user_list_likes.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn user_list_likes(
  db: pog.Connection,
  arg_1: Uuid,
) -> Result(pog.Returned(UserListLikesRow), pog.QueryError) {
  let decoder = {
    use photo_id <- decode.field(0, uuid_decoder())
    decode.success(UserListLikesRow(photo_id:))
  }

  "SELECT photo_id
FROM likes
WHERE user_id = $1;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `user_search` query
/// defined in `./src/server/sql/user_search.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UserSearchRow {
  UserSearchRow(
    id: Uuid,
    username: String,
    first_name: String,
    last_name: Option(String),
    bio: Option(String),
    available_for_hire: Bool,
    premium: Bool,
    password: String,
    created_at: Timestamp,
    updated_at: Timestamp,
    storage_quota: Int,
    storage_quota_used: Int,
  )
}

/// Runs the `user_search` query
/// defined in `./src/server/sql/user_search.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn user_search(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(UserSearchRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use username <- decode.field(1, decode.string)
    use first_name <- decode.field(2, decode.string)
    use last_name <- decode.field(3, decode.optional(decode.string))
    use bio <- decode.field(4, decode.optional(decode.string))
    use available_for_hire <- decode.field(5, decode.bool)
    use premium <- decode.field(6, decode.bool)
    use password <- decode.field(7, decode.string)
    use created_at <- decode.field(8, pog.timestamp_decoder())
    use updated_at <- decode.field(9, pog.timestamp_decoder())
    use storage_quota <- decode.field(10, decode.int)
    use storage_quota_used <- decode.field(11, decode.int)
    decode.success(UserSearchRow(
      id:,
      username:,
      first_name:,
      last_name:,
      bio:,
      available_for_hire:,
      premium:,
      password:,
      created_at:,
      updated_at:,
      storage_quota:,
      storage_quota_used:,
    ))
  }

  "SELECT *
FROM users
WHERE username ILIKE $1 || '%' ORDER BY created_at ASC;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `user_update` query
/// defined in `./src/server/sql/user_update.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UserUpdateRow {
  UserUpdateRow(
    id: Uuid,
    username: String,
    first_name: String,
    last_name: Option(String),
    bio: Option(String),
    available_for_hire: Bool,
    premium: Bool,
    password: String,
    created_at: Timestamp,
    updated_at: Timestamp,
    storage_quota: Int,
    storage_quota_used: Int,
  )
}

/// Runs the `user_update` query
/// defined in `./src/server/sql/user_update.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn user_update(
  db: pog.Connection,
  id: Uuid,
  arg_2: String,
  first_name: String,
  arg_4: String,
  arg_5: String,
  available_for_hire: Bool,
) -> Result(pog.Returned(UserUpdateRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, uuid_decoder())
    use username <- decode.field(1, decode.string)
    use first_name <- decode.field(2, decode.string)
    use last_name <- decode.field(3, decode.optional(decode.string))
    use bio <- decode.field(4, decode.optional(decode.string))
    use available_for_hire <- decode.field(5, decode.bool)
    use premium <- decode.field(6, decode.bool)
    use password <- decode.field(7, decode.string)
    use created_at <- decode.field(8, pog.timestamp_decoder())
    use updated_at <- decode.field(9, pog.timestamp_decoder())
    use storage_quota <- decode.field(10, decode.int)
    use storage_quota_used <- decode.field(11, decode.int)
    decode.success(UserUpdateRow(
      id:,
      username:,
      first_name:,
      last_name:,
      bio:,
      available_for_hire:,
      premium:,
      password:,
      created_at:,
      updated_at:,
      storage_quota:,
      storage_quota_used:,
    ))
  }

  "UPDATE users
SET username = $2,
    first_name = $3 ,
    last_name = nullif($4,''),
    bio = nullif($5,''),
    available_for_hire = $6
where id = $1
RETURNING *;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(id)))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(first_name))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.parameter(pog.bool(available_for_hire))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `user_update_password` query
/// defined in `./src/server/sql/user_update_password.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn user_update_password(
  db: pog.Connection,
  arg_1: Uuid,
  password: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "UPDATE users
SET password = $2
where id = $1;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.parameter(pog.text(password))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `user_update_quota` query
/// defined in `./src/server/sql/user_update_quota.sql`.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn user_update_quota(
  db: pog.Connection,
  arg_1: Uuid,
  arg_2: Int,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "UPDATE users SET storage_quota_used = storage_quota_used + $2 WHERE id = $1;
"
  |> pog.query
  |> pog.parameter(pog.text(uuid.to_string(arg_1)))
  |> pog.parameter(pog.int(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

// --- Enums -------------------------------------------------------------------

/// Corresponds to the Postgres `mimetype` enum.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type Mimetype {
  Other
  Webp
  Jpg
  Png
}

fn mimetype_decoder() -> decode.Decoder(Mimetype) {
  use mimetype <- decode.then(decode.string)
  case mimetype {
    "other" -> decode.success(Other)
    "webp" -> decode.success(Webp)
    "jpg" -> decode.success(Jpg)
    "png" -> decode.success(Png)
    _ -> decode.failure(Other, "Mimetype")
  }
}

fn mimetype_encoder(mimetype) -> pog.Value {
  case mimetype {
    Other -> "other"
    Webp -> "webp"
    Jpg -> "jpg"
    Png -> "png"
  }
  |> pog.text
}

/// Corresponds to the Postgres `photo_privacy` enum.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type PhotoPrivacy {
  Public
  Premium
  Private
}

fn photo_privacy_decoder() -> decode.Decoder(PhotoPrivacy) {
  use photo_privacy <- decode.then(decode.string)
  case photo_privacy {
    "public" -> decode.success(Public)
    "premium" -> decode.success(Premium)
    "private" -> decode.success(Private)
    _ -> decode.failure(Public, "PhotoPrivacy")
  }
}

fn photo_privacy_encoder(photo_privacy) -> pog.Value {
  case photo_privacy {
    Public -> "public"
    Premium -> "premium"
    Private -> "private"
  }
  |> pog.text
}

// --- Encoding/decoding utils -------------------------------------------------

/// A decoder to decode `Uuid`s coming from a Postgres query.
///
fn uuid_decoder() {
  use bit_array <- decode.then(decode.bit_array)
  case uuid.from_bit_array(bit_array) {
    Ok(uuid) -> decode.success(uuid)
    Error(_) -> decode.failure(uuid.v7(), "Uuid")
  }
}
