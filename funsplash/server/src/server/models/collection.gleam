import gleam/option.{type Option}
import server/models/user
import server/sql
import shared/shared_collection
import shared/shared_user
import youid/uuid.{type Uuid}

pub type Id =
  Uuid

pub type PublicId =
  String

pub type Collection {
  Collection(
    id: Id,
    public_id: PublicId,
    name: String,
    description: Option(String),
    creator: user.Id,
    private: Bool,
  )
}

pub fn to_shared(
  collection c: Collection,
  user u: shared_user.User,
) -> shared_collection.Collection {
  shared_collection.Collection(
    public_id: c.public_id,
    name: c.name,
    private: c.private,
    user: u,
    description: c.description,
  )
}

pub fn from_add_photo(c: sql.CollectionAddPhotoRow) -> #(Id, Uuid) {
  #(c.collection_id, c.photo_id)
}

pub fn from_remove_photo(c: sql.CollectionRemovePhotoRow) -> #(Id, Uuid) {
  #(c.collection_id, c.photo_id)
}

pub fn from_create(c: sql.CollectionCreateRow) -> Collection {
  Collection(
    id: c.id,
    public_id: c.public_id,
    name: c.name,
    description: c.description,
    creator: c.creator,
    private: c.private,
  )
}

pub fn from_find_by_id(c: sql.CollectionFindByIdRow) -> Collection {
  Collection(
    id: c.id,
    public_id: c.public_id,
    name: c.name,
    description: c.description,
    creator: c.creator,
    private: c.private,
  )
}

pub fn from_find_by_public_id(
  c: sql.CollectionFindByPublicIdRow,
) -> Collection {
  Collection(
    id: c.id,
    public_id: c.public_id,
    name: c.name,
    description: c.description,
    creator: c.creator,
    private: c.private,
  )
}

pub fn from_update(c: sql.CollectionUpdateRow) -> Collection {
  Collection(
    id: c.id,
    public_id: c.public_id,
    name: c.name,
    description: c.description,
    creator: c.creator,
    private: c.private,
  )
}

pub fn from_user_collections_list(c: sql.UserCollectionsListRow) -> Collection {
  Collection(
    id: c.id,
    public_id: c.public_id,
    name: c.name,
    description: c.description,
    creator: c.creator,
    private: c.private,
  )
}
