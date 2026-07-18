import api/api_collection
import auth
import browser
import components/photo_card
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute.{
  action, checked, class, for, id, method, placeholder, required, type_, value,
}
import lustre/effect.{type Effect}
import lustre/element.{type Element, text}
import lustre/element/html.{
  button, div, form, h1, input, label, p, span, textarea,
}
import lustre/event
import rsvp
import shared/shared_collection
import shared/shared_thumbnail

pub type Model {
  Loading(
    id: String,
    collection: option.Option(shared_collection.Collection),
    photos: option.Option(List(shared_thumbnail.Thumbnail)),
  )
  Loaded(
    collection: shared_collection.Collection,
    photos: List(shared_thumbnail.Thumbnail),
    cards: dict.Dict(String, photo_card.Model),
    editing_collection: Bool,
  )
  Failed(error: String)
}

pub fn init(id: String) -> #(Model, Effect(Message)) {
  #(
    Loading(id, None, None),
    effect.batch([
      api_collection.fetch(id, ApiReturnedCollection),
      api_collection.fetch_photos(id, ApiReturnedPhotos),
    ]),
  )
}

pub type Message {
  ApiReturnedCollection(
    Result(shared_collection.Collection, rsvp.Error(String)),
  )
  ApiReturnedPhotos(
    Result(List(shared_thumbnail.Thumbnail), rsvp.Error(String)),
  )
  CardMsg(photo_id: String, msg: photo_card.Message)
  CloseAllDropdowns
  OpenEditCollection
  CloseEditCollection
  DeleteCollection
  ApiReturnedDeleteCollection(Result(Nil, rsvp.Error(String)))
}

pub fn update(model: Model, msg: Message) -> #(Model, Effect(Message)) {
  case msg {
    ApiReturnedCollection(Ok(collection)) -> {
      case model {
        Loading(id, _, p) -> check_loaded(id, Some(collection), p)
        Loaded(_, p, cards, ec) -> #(
          Loaded(collection, p, cards, ec),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
    }
    ApiReturnedCollection(Error(_)) -> #(
      Failed("Failed to load collection"),
      effect.none(),
    )
    ApiReturnedPhotos(Ok(photos)) -> {
      case model {
        Loading(id, c, _) -> check_loaded(id, c, Some(photos))
        Loaded(c, _, cards, ec) -> {
          let new_cards =
            list.fold(photos, cards, fn(acc, p) {
              case dict.has_key(acc, p.public_id) {
                True -> acc
                False -> dict.insert(acc, p.public_id, photo_card.init(p))
              }
            })
          #(Loaded(c, photos, new_cards, ec), effect.none())
        }
        _ -> #(model, effect.none())
      }
    }
    ApiReturnedPhotos(Error(_)) -> {
      // TTL fallback
      case model {
        Loading(id, c, _) -> check_loaded(id, c, Some([]))
        Loaded(c, _, cards, ec) -> #(Loaded(c, [], cards, ec), effect.none())
        _ -> #(model, effect.none())
      }
    }
    CardMsg(pid, m) ->
      case model {
        Loaded(col, photos, cards, ec) -> {
          case dict.get(cards, pid) {
            Ok(card_model) -> {
              let #(new_card_model, eff) = photo_card.update(card_model, m)
              let new_cards = dict.insert(cards, pid, new_card_model)
              #(
                Loaded(col, photos, new_cards, ec),
                effect.map(eff, fn(em) { CardMsg(pid, em) }),
              )
            }
            Error(_) -> #(model, effect.none())
          }
        }
        _ -> #(model, effect.none())
      }

    OpenEditCollection ->
      case model {
        Loaded(c, p, cards, _) -> #(Loaded(c, p, cards, True), effect.none())
        _ -> #(model, effect.none())
      }
    CloseEditCollection ->
      case model {
        Loaded(c, p, cards, _) -> #(Loaded(c, p, cards, False), effect.none())
        _ -> #(model, effect.none())
      }
    DeleteCollection ->
      case model {
        Loaded(c, _, _, _) -> #(
          model,
          api_collection.delete_collection(c.public_id, ApiReturnedDeleteCollection),
        )
        _ -> #(model, effect.none())
      }
    ApiReturnedDeleteCollection(Ok(_)) ->
      case model {
        Loaded(c, _, _, _) -> {
          browser.navigate_to("/users/" <> c.user.username)
          #(model, effect.none())
        }
        _ -> #(model, effect.none())
      }
    ApiReturnedDeleteCollection(Error(_)) -> #(model, effect.none())
    CloseAllDropdowns ->
      case model {
        Loaded(col, photos, cards, ec) -> {
          let new_cards =
            dict.map_values(cards, fn(_, c) {
              let #(new_c, _) = photo_card.update(c, photo_card.CloseDropdown)
              new_c
            })
          #(Loaded(col, photos, new_cards, ec), effect.none())
        }
        _ -> #(model, effect.none())
      }
  }
}

fn check_loaded(
  id: String,
  col: option.Option(shared_collection.Collection),
  photos: option.Option(List(shared_thumbnail.Thumbnail)),
) -> #(Model, Effect(Message)) {
  case col, photos {
    Some(c), Some(p) -> {
      let cards =
        list.fold(p, dict.new(), fn(acc, photo) {
          dict.insert(acc, photo.public_id, photo_card.init(photo))
        })
      #(Loaded(c, p, cards, False), effect.none())
    }
    _, _ -> #(Loading(id, col, photos), effect.none())
  }
}

pub fn view(model: Model, current_auth: auth.Auth) -> Element(Message) {
  div(
    [class("max-w-5xl mx-auto py-8 px-4"), event.on_click(CloseAllDropdowns)],
    [
      case model {
        Loading(_, _, _) ->
          p([class("text-center text-gray-500 py-20")], [
            text("Loading collection..."),
          ])
        Failed(err) -> p([class("text-center text-red-500 py-20")], [text(err)])
        Loaded(col, photos, cards, ec) ->
          collection_view(col, photos, cards, ec, current_auth)
      },
    ],
  )
}

fn collection_view(
  col: shared_collection.Collection,
  photos: List(shared_thumbnail.Thumbnail),
  cards: dict.Dict(String, photo_card.Model),
  editing_collection: Bool,
  current_auth: auth.Auth,
) -> Element(Message) {
  let is_owner = case current_auth {
    auth.LoggedIn(user) -> user.username == col.user.username
    _ -> False
  }

  div([class("space-y-8")], [
    case editing_collection {
      True ->
        form(
          [
            action("/napi/collections/" <> col.public_id),
            method("POST"),
            class(
              "flex flex-col items-center space-y-4 mb-8 bg-gray-50 p-6 rounded-lg",
            ),
          ],
          [
            h1([class("text-xl font-bold text-gray-900 mb-2")], [
              text("Edit Collection"),
            ]),
            div([class("w-full max-w-md")], [
              p([class("text-xs font-bold text-gray-700 mb-1")], [text("Name")]),
              input([
                type_("text"),
                attribute.name("name"),
                value(col.name),
                required(True),
                class(
                  "w-full border border-gray-300 rounded px-3 py-2 text-sm mb-3",
                ),
              ]),

              p([class("text-xs font-bold text-gray-700 mb-1")], [
                text("Description (optional)"),
              ]),
              textarea(
                [
                  attribute.name("description"),
                  attribute.rows(3),
                  class(
                    "w-full border border-gray-300 rounded px-3 py-2 text-sm mb-3",
                  ),
                ],
                case col.description {
                  Some(desc) -> desc
                  None -> ""
                },
              ),

              div([class("flex items-center gap-2 mb-4")], [
                input([
                  type_("checkbox"),
                  attribute.name("private"),
                  id("private_collection"),
                  checked(col.private),
                ]),
                label(
                  [for("private_collection"), class("text-sm text-gray-700")],
                  [text("Private Collection")],
                ),
              ]),

              div([class("flex items-center justify-between mt-2")], [
                button(
                  [
                    type_("button"),
                    event.prevent_default(
                      event.stop_propagation(event.on_click(CloseEditCollection)),
                    ),
                    class("text-sm text-gray-500 hover:text-black font-medium"),
                  ],
                  [text("Cancel")],
                ),
                button(
                  [
                    type_("submit"),
                    class(
                      "bg-black text-white rounded px-4 py-2 text-sm font-medium hover:bg-gray-800",
                    ),
                  ],
                  [text("Save Changes")],
                ),
              ]),
            ]),
          ],
        )
      False ->
        div([class("flex flex-col items-center text-center space-y-2 mb-8")], [
          h1([class("text-3xl font-bold text-gray-900")], [text(col.name)]),
          p([class("text-sm text-gray-500")], [
            text(
              "By " <> col.user.first_name <> " (@" <> col.user.username <> ")",
            ),
          ]),
          case col.description {
            Some(desc) ->
              p([class("text-sm text-gray-600 max-w-md")], [text(desc)])
            None -> element.none()
          },
          case col.private {
            True ->
              span(
                [
                  class(
                    "inline-block rounded-full bg-red-50 border border-red-200 px-3 py-0.5 text-xs text-red-700",
                  ),
                ],
                [text("Private Collection")],
              )
            False -> element.none()
          },
          case is_owner {
            True ->
              div([class("flex items-center gap-4 mt-4")], [
                button(
                  [
                    type_("button"),
                    event.on_click(OpenEditCollection),
                    class(
                      "text-sm font-medium text-blue-600 hover:text-blue-800",
                    ),
                  ],
                  [text("Edit Collection")],
                ),
                button(
                  [
                    type_("button"),
                    event.on_click(DeleteCollection),
                    class("text-sm font-medium text-red-600 hover:text-red-800"),
                  ],
                  [text("Delete Collection")],
                ),
              ])
            False -> element.none()
          },
        ])
    },
    case photos {
      [] ->
        p([class("text-center text-gray-400 text-sm py-8")], [
          text("No photos in this collection."),
        ])
      photos_list ->
        div(
          [class("grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4")],
          list.map(photos_list, fn(p) {
            case dict.get(cards, p.public_id) {
              Ok(card_model) ->
                element.map(photo_card.view(card_model, current_auth), fn(msg) {
                  CardMsg(p.public_id, msg)
                })
              Error(_) -> element.none()
            }
          }),
        )
    },
  ])
}
