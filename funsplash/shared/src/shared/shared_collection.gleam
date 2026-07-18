import formal/form.{type Form}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option}
import shared/shared_user

pub type PublicId =
  String

pub type Collection {
  Collection(
    public_id: PublicId,
    name: String,
    private: Bool,
    user: shared_user.User,
    description: Option(String),
  )
}

pub fn collection_to_json(collection: Collection) -> json.Json {
  let Collection(public_id:, name:, user:, description:, private:) = collection
  json.object([
    #("public_id", json.string(public_id)),
    #("name", json.string(name)),
    #("user", shared_user.user_to_json(user)),
    #("description", case description {
      option.None -> json.null()
      option.Some(value) -> json.string(value)
    }),
    #("private", json.bool(private)),
  ])
}

pub fn collection_decoder() -> decode.Decoder(Collection) {
  use public_id <- decode.field("public_id", decode.string)
  use name <- decode.field("name", decode.string)
  use user <- decode.field("user", shared_user.user_decoder())
  use description <- decode.field("description", decode.optional(decode.string))
  use private <- decode.field("private", decode.bool)
  decode.success(Collection(public_id:, name:, user:, description:, private:))
}

pub type CollectionCreateRequest {
  CollectionCreateRequest(
    name: String,
    description: String,
    private: Bool,
    photo_public_id: Option(String),
    redirect_to: Option(String),
  )
}

pub fn collection_create_form() -> Form(CollectionCreateRequest) {
  form.new({
    use name <- form.field(
      "name",
      form.parse_string
        |> form.check_not_empty,
    )
    use description <- form.field(
      "description",
      form.parse_optional(form.parse_string),
    )
    use private <- form.field("private", form.parse_checkbox)
    use photo_public_id <- form.field(
      "photo_public_id",
      form.parse_optional(form.parse_string),
    )
    use redirect_to <- form.field(
      "redirect_to",
      form.parse_optional(form.parse_string),
    )

    form.success(CollectionCreateRequest(
      name:,
      description: option.unwrap(description, ""),
      private:,
      photo_public_id:,
      redirect_to:,
    ))
  })
}

pub type CollectionUpdateRequest {
  CollectionUpdateRequest(name: String, description: String, private: Bool)
}

pub fn collection_update_form() -> Form(CollectionUpdateRequest) {
  form.new({
    use name <- form.field(
      "name",
      form.parse_string
        |> form.check_not_empty,
    )
    use description <- form.field(
      "description",
      form.parse_optional(form.parse_string),
    )
    use private <- form.field("private", form.parse_checkbox)

    form.success(CollectionUpdateRequest(
      name:,
      description: option.unwrap(description, ""),
      private:,
    ))
  })
}
