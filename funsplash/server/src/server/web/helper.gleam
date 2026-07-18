import gleam/option.{None, Some}
import gleam/result
import server/collections
import server/models/photo.{type Photo}
import server/web
import shared/shared_collection

pub fn current_user_collections(
  context: web.Context,
  photo p: Photo,
) -> List(shared_collection.PublicId) {
  case context.user {
    Some(viewer) -> {
      let values: List(String) =
        collections.get_containing_photo_from_user(
          context.state,
          p.id,
          viewer.id,
        )
        |> result.unwrap([])
      values
    }
    None -> []
  }
}
