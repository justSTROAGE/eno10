import api/api_user
import auth
import components/photo_card
import gleam/dict
import gleam/list
import gleam/option
import gleam/string
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element, text}
import lustre/element/html.{a, button, div, h1, p, span}
import lustre/event
import route
import rsvp
import shared/shared_collection
import shared/shared_thumbnail
import shared/shared_user

// MODEL -----------------------------------------------------------------------

pub type Tab {
  PhotosTab
  CollectionsTab
}

pub type Model {
  Loading(
    username: String,
    user: option.Option(shared_user.User),
    photos: option.Option(List(shared_thumbnail.Thumbnail)),
    collections: option.Option(List(shared_collection.Collection)),
  )
  Loaded(
    user: shared_user.User,
    photos: List(shared_thumbnail.Thumbnail),
    collections: List(shared_collection.Collection),
    active_tab: Tab,
    photo_cards: dict.Dict(String, photo_card.Model),
  )
  Failed
}

pub fn init(username: String) -> #(Model, Effect(Message)) {
  #(
    Loading(username, option.None, option.None, option.None),
    effect.batch([
      api_user.fetch(username, ApiReturnedUser),
      api_user.fetch_photos(username, ApiReturnedPhotos),
      api_user.fetch_collections(username, ApiReturnedCollections),
    ]),
  )
}

fn check_loaded(
  username: String,
  user: option.Option(shared_user.User),
  photos: option.Option(List(shared_thumbnail.Thumbnail)),
  collections: option.Option(List(shared_collection.Collection)),
) -> #(Model, Effect(Message)) {
  case user, photos, collections {
    option.Some(u), option.Some(p), option.Some(c) -> {
      let cards =
        list.fold(p, dict.new(), fn(acc, photo) {
          dict.insert(acc, photo.public_id, photo_card.init(photo))
        })
      #(Loaded(u, p, c, PhotosTab, cards), effect.none())
    }
    _, _, _ -> #(Loading(username, user, photos, collections), effect.none())
  }
}

// UPDATE ----------------------------------------------------------------------

pub type Message {
  ApiReturnedUser(Result(shared_user.User, rsvp.Error(String)))
  ApiReturnedPhotos(
    Result(List(shared_thumbnail.Thumbnail), rsvp.Error(String)),
  )
  ApiReturnedCollections(
    Result(List(shared_collection.Collection), rsvp.Error(String)),
  )
  TabClicked(tab: Tab)
  CardMsg(photo_id: String, msg: photo_card.Message)
  CloseAllDropdowns
}

pub fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    ApiReturnedUser(res) -> {
      case model, res {
        Loading(uname, _, p, c), Ok(u) ->
          check_loaded(uname, option.Some(u), p, c)
        Loading(_, _, _, _), Error(_) -> #(Failed, effect.none())
        _, _ -> #(model, effect.none())
      }
    }
    ApiReturnedPhotos(res) -> {
      let photos = case res {
        Ok(p) -> p
        Error(_) -> []
      }
      case model {
        Loading(uname, u, _, c) ->
          check_loaded(uname, u, option.Some(photos), c)
        Loaded(u, _, c, t, cards) -> {
          let new_cards =
            list.fold(photos, cards, fn(acc, p) {
              case dict.has_key(acc, p.public_id) {
                True -> acc
                False -> dict.insert(acc, p.public_id, photo_card.init(p))
              }
            })
          #(Loaded(u, photos, c, t, new_cards), effect.none())
        }
        _ -> #(model, effect.none())
      }
    }
    ApiReturnedCollections(res) -> {
      let cols = case res {
        Ok(c) -> c
        Error(_) -> []
      }
      case model {
        Loading(uname, u, p, _) -> check_loaded(uname, u, p, option.Some(cols))
        Loaded(u, p, _, t, cards) -> #(
          Loaded(u, p, cols, t, cards),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
    }
    TabClicked(tab) ->
      case model {
        Loaded(user, photos, cols, _, cards) -> #(
          Loaded(user, photos, cols, tab, cards),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
    CardMsg(pid, msg) ->
      case model {
        Loaded(user, photos, cols, tab, cards) -> {
          case dict.get(cards, pid) {
            Ok(card_model) -> {
              let #(new_card_model, eff) = photo_card.update(card_model, msg)
              let new_cards = dict.insert(cards, pid, new_card_model)
              #(
                Loaded(user, photos, cols, tab, new_cards),
                effect.map(eff, fn(m) { CardMsg(pid, m) }),
              )
            }
            Error(_) -> #(model, effect.none())
          }
        }
        _ -> #(model, effect.none())
      }
    CloseAllDropdowns ->
      case model {
        Loaded(user, photos, cols, tab, cards) -> {
          let new_cards =
            dict.map_values(cards, fn(_, c) {
              let #(new_c, _) = photo_card.update(c, photo_card.CloseDropdown)
              new_c
            })
          #(Loaded(user, photos, cols, tab, new_cards), effect.none())
        }
        _ -> #(model, effect.none())
      }
  }
}

// VIEW ------------------------------------------------------------------------

pub fn view(model: Model, current_auth: auth.Auth) -> Element(Message) {
  div(
    [class("max-w-5xl mx-auto py-8 px-4"), event.on_click(CloseAllDropdowns)],
    [
      case model {
        Loading(username, _, _, _) ->
          p([class("text-center text-gray-400 text-sm py-20")], [
            text("Loading @" <> username <> "…"),
          ])
        Loaded(user, photos, cols, tab, cards) ->
          profile_view(user, photos, cols, tab, cards, current_auth)
        Failed ->
          p([class("text-center text-red-500 text-sm py-20")], [
            text("User not found."),
          ])
      },
    ],
  )
}

fn profile_view(
  user: shared_user.User,
  photos: List(shared_thumbnail.Thumbnail),
  collections: List(shared_collection.Collection),
  active_tab: Tab,
  cards: dict.Dict(String, photo_card.Model),
  current_auth: auth.Auth,
) -> Element(Message) {
  div([class("space-y-8")], [
    // Profile header
    div([class("flex flex-col items-center text-center space-y-2")], [
      div(
        [
          class(
            "w-16 h-16 rounded-full bg-gray-200 flex items-center justify-center text-2xl font-bold text-gray-500",
          ),
        ],
        [text(string.slice(user.first_name, 0, 1))],
      ),
      h1([class("text-xl font-bold text-gray-900")], [text(user.first_name)]),
      p([class("text-sm text-gray-500")], [text("@" <> user.username)]),
      case user.bio {
        option.Some(bio) ->
          p([class("text-sm text-gray-600 max-w-md")], [text(bio)])
        option.None -> element.none()
      },
      case user.available_for_hire {
        True ->
          span(
            [
              class(
                "inline-block rounded-full bg-green-50 border border-green-200 px-3 py-0.5 text-xs text-green-700",
              ),
            ],
            [text("Available for hire")],
          )
        False -> element.none()
      },
      case current_auth {
        auth.LoggedIn(logged_in_user)
          if logged_in_user.username == user.username
        ->
          a(
            [
              route.href(route.Account(option.None)),
              class(
                "mt-4 inline-block rounded-md border border-gray-300 px-4 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50",
              ),
            ],
            [text("Edit Profile")],
          )
        _ -> element.none()
      },
    ]),

    // Tabs
    div([class("flex justify-center space-x-8 border-b border-gray-200")], [
      button(
        [
          class(case active_tab {
            PhotosTab ->
              "py-4 px-1 border-b-2 border-black font-medium text-sm text-black"
            CollectionsTab ->
              "py-4 px-1 border-b-2 border-transparent font-medium text-sm text-gray-500 hover:text-gray-700 hover:border-gray-300"
          }),
          event.on_click(TabClicked(PhotosTab)),
        ],
        [text("Photos")],
      ),
      button(
        [
          class(case active_tab {
            CollectionsTab ->
              "py-4 px-1 border-b-2 border-black font-medium text-sm text-black"
            PhotosTab ->
              "py-4 px-1 border-b-2 border-transparent font-medium text-sm text-gray-500 hover:text-gray-700 hover:border-gray-300"
          }),
          event.on_click(TabClicked(CollectionsTab)),
        ],
        [text("Collections")],
      ),
    ]),

    // Tab content
    case active_tab {
      PhotosTab ->
        case list.is_empty(photos) {
          True ->
            p([class("text-center text-gray-500")], [
              text("No photos yet."),
            ])
          False ->
            div(
              [
                class(
                  "grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6",
                ),
              ],
              list.map(photos, fn(p) {
                case dict.get(cards, p.public_id) {
                  Ok(card_model) ->
                    element.map(
                      photo_card.view(card_model, current_auth),
                      fn(msg) { CardMsg(p.public_id, msg) },
                    )
                  Error(_) -> element.none()
                }
              }),
            )
        }
      CollectionsTab ->
        case collections {
          [] ->
            p([class("text-center text-gray-400 text-sm py-8")], [
              text("No collections yet."),
            ])
          collections ->
            div(
              [class("grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4")],
              list.map(collections, fn(c) {
                a(
                  [
                    route.href(route.Collection(c.public_id)),
                    class(
                      "block p-6 bg-white border border-gray-200 rounded-lg shadow hover:bg-gray-100 transition-colors duration-200",
                    ),
                  ],
                  [
                    h1(
                      [
                        class(
                          "mb-2 text-2xl font-bold tracking-tight text-gray-900",
                        ),
                      ],
                      [text(c.name)],
                    ),
                    case c.private {
                      True ->
                        span(
                          [
                            class(
                              "inline-block rounded bg-red-100 px-2 py-0.5 text-xs text-red-800 font-semibold",
                            ),
                          ],
                          [text("Private")],
                        )
                      False -> element.none()
                    },
                  ],
                )
              }),
            )
        }
    },
  ])
}
