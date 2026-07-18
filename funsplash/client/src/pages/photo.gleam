import api/api_collection
import api/api_photo
import api/api_user
import auth.{type Auth}
import browser
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option
import gleam/string
import lustre/attribute.{
  action, alt, checked, class, for, id, method, name, placeholder, rows,
  selected, src, type_, value,
}
import lustre/effect.{type Effect}
import lustre/element.{type Element, text}
import lustre/element/html.{
  a, button, div, form, h1, img, input, label, option as html_option, p, select,
  span, textarea,
}
import lustre/event
import route
import rsvp
import shared/shared_collection
import shared/shared_photo
import shared/shared_privacy
import shared/shared_stats
import shared/shared_thumbnail
import shared/shared_user

// MODEL -----------------------------------------------------------------------

pub type Model {
  Loading
  Loaded(
    photo: shared_photo.Photo,
    liked: Bool,
    dropdown_open: Bool,
    user_collections: option.Option(List(shared_collection.Collection)),
    image_failed: Bool,
    creating_collection: Bool,
    editing_photo: Bool,
  )
  Failed
}

pub fn init(id: String) -> #(Model, Effect(Message)) {
  let effect = api_photo.fetch(id, ApiReturnedPhoto)
  #(Loading, effect)
}

// UPDATE ----------------------------------------------------------------------

pub type Message {
  ApiReturnedPhoto(Result(shared_photo.Photo, rsvp.Error(String)))
  UserClickedLike
  ToggleDropdown(username: String)
  ApiReturnedCollections(
    Result(List(shared_collection.Collection), rsvp.Error(String)),
  )
  AddPhotoToCollection(collection_id: String)
  ApiReturnedAddPhoto(#(String, Result(Nil, rsvp.Error(String))))
  RemovePhotoFromCollection(collection_id: String)
  ApiReturnedRemovePhoto(#(String, Result(Nil, rsvp.Error(String))))
  CloseDropdown
  ImageLoadError
  NoOp
  OpenCreateCollection
  CloseCreateCollection
  OpenEditPhoto
  CloseEditPhoto
  DeletePhoto
  ApiReturnedDeletePhoto(Result(Nil, rsvp.Error(String)))
}

pub fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message, model {
    ApiReturnedPhoto(Ok(photo)), _ -> #(
      Loaded(
        photo,
        liked: photo.thumbnail.user_liked,
        dropdown_open: False,
        user_collections: option.None,
        image_failed: False,
        creating_collection: False,
        editing_photo: False,
      ),
      effect.none(),
    )
    ApiReturnedPhoto(_), _ -> #(Failed, effect.none())
    CloseDropdown,
      Loaded(photo, liked, _, user_collections, image_failed, _, ep)
    -> #(
      Loaded(photo, liked, False, user_collections, image_failed, False, ep),
      effect.none(),
    )
    ImageLoadError,
      Loaded(
        photo,
        liked,
        dropdown_open,
        user_collections,
        _,
        creating_collection,
        ep,
      )
    -> #(
      Loaded(
        photo,
        liked,
        dropdown_open,
        user_collections,
        True,
        creating_collection,
        ep,
      ),
      effect.none(),
    )
    NoOp, _ -> #(model, effect.none())
    OpenCreateCollection,
      Loaded(photo, liked, dropdown_open, user_collections, image_failed, _, ep)
    -> #(
      Loaded(
        photo,
        liked,
        dropdown_open,
        user_collections,
        image_failed,
        True,
        ep,
      ),
      effect.none(),
    )
    CloseCreateCollection,
      Loaded(photo, liked, dropdown_open, user_collections, image_failed, _, ep)
    -> #(
      Loaded(
        photo,
        liked,
        dropdown_open,
        user_collections,
        image_failed,
        False,
        ep,
      ),
      effect.none(),
    )
    UserClickedLike,
      Loaded(
        photo,
        liked,
        dropdown_open,
        user_collections,
        image_failed,
        creating_collection,
        ep,
      )
    -> {
      let new_liked = !liked
      let delta = case new_liked {
        True -> 1
        False -> -1
      }
      let new_stats =
        shared_stats.Stats(..photo.stats, likes: photo.stats.likes + delta)
      #(
        Loaded(
          shared_photo.Photo(..photo, stats: new_stats),
          new_liked,
          dropdown_open,
          user_collections,
          image_failed,
          creating_collection,
          ep,
        ),
        effect.none(),
      )
    }
    ToggleDropdown(username),
      Loaded(photo, liked, dropdown_open, user_collections, image_failed, _, ep)
    -> {
      let new_open = !dropdown_open
      let eff = case new_open, user_collections {
        True, option.None ->
          api_user.fetch_collections(username, ApiReturnedCollections)
        _, _ -> effect.none()
      }
      #(
        Loaded(
          photo,
          liked,
          new_open,
          user_collections,
          image_failed,
          False,
          ep,
        ),
        eff,
      )
    }
    ApiReturnedCollections(Ok(collections)),
      Loaded(
        photo,
        liked,
        dropdown_open,
        _,
        image_failed,
        creating_collection,
        ep,
      )
    -> {
      #(
        Loaded(
          photo,
          liked,
          dropdown_open,
          option.Some(collections),
          image_failed,
          creating_collection,
          ep,
        ),
        effect.none(),
      )
    }
    AddPhotoToCollection(cid), Loaded(photo, _, _, _, _, _, ep) -> {
      #(
        model,
        api_collection.add_photo(cid, photo.thumbnail.public_id, fn(res) {
          ApiReturnedAddPhoto(#(cid, res))
        }),
      )
    }
    ApiReturnedAddPhoto(#(cid, Ok(_))),
      Loaded(
        photo,
        liked,
        dropdown_open,
        user_collections,
        image_failed,
        creating_collection,
        ep,
      )
    -> {
      let new_thumb =
        shared_thumbnail.Thumbnail(..photo.thumbnail, current_user_collections: [
          cid,
          ..photo.thumbnail.current_user_collections
        ])
      let new_photo = shared_photo.Photo(..photo, thumbnail: new_thumb)
      #(
        Loaded(
          new_photo,
          liked,
          dropdown_open,
          user_collections,
          image_failed,
          creating_collection,
          ep,
        ),
        effect.none(),
      )
    }
    RemovePhotoFromCollection(cid), Loaded(photo, _, _, _, _, _, ep) -> {
      #(
        model,
        api_collection.remove_photo(cid, photo.thumbnail.public_id, fn(res) {
          ApiReturnedRemovePhoto(#(cid, res))
        }),
      )
    }
    ApiReturnedRemovePhoto(#(cid, Ok(_))),
      Loaded(
        photo,
        liked,
        dropdown_open,
        user_collections,
        image_failed,
        creating_collection,
        ep,
      )
    -> {
      let new_thumb =
        shared_thumbnail.Thumbnail(
          ..photo.thumbnail,
          current_user_collections: list.filter(
            photo.thumbnail.current_user_collections,
            fn(c) { c != cid },
          ),
        )
      let new_photo = shared_photo.Photo(..photo, thumbnail: new_thumb)
      #(
        Loaded(
          new_photo,
          liked,
          dropdown_open,
          user_collections,
          image_failed,
          creating_collection,
          ep,
        ),
        effect.none(),
      )
    }

    OpenEditPhoto,
      Loaded(
        photo,
        liked,
        dropdown_open,
        user_collections,
        image_failed,
        creating_collection,
        _,
      )
    -> #(
      Loaded(
        photo,
        liked,
        dropdown_open,
        user_collections,
        image_failed,
        creating_collection,
        True,
      ),
      effect.none(),
    )
    CloseEditPhoto,
      Loaded(
        photo,
        liked,
        dropdown_open,
        user_collections,
        image_failed,
        creating_collection,
        _,
      )
    -> #(
      Loaded(
        photo,
        liked,
        dropdown_open,
        user_collections,
        image_failed,
        creating_collection,
        False,
      ),
      effect.none(),
    )
    DeletePhoto, Loaded(photo, _, _, _, _, _, _) -> #(
      model,
      api_photo.delete_photo(photo.thumbnail.public_id, ApiReturnedDeletePhoto),
    )
    ApiReturnedDeletePhoto(Ok(_)), Loaded(photo, _, _, _, _, _, _) -> {
      browser.navigate_to("/users/" <> photo.thumbnail.creator.username)
      #(model, effect.none())
    }
    ApiReturnedDeletePhoto(Error(_)), _ -> #(model, effect.none())
    _, _ -> #(model, effect.none())
  }
}

// VIEW ------------------------------------------------------------------------

pub fn view(model: Model, auth: Auth) -> Element(Message) {
  div([class("max-w-4xl mx-auto py-8 px-4"), event.on_click(CloseDropdown)], [
    case model {
      Loading -> loading_view()
      Loaded(
        photo,
        liked,
        dropdown_open,
        user_collections,
        image_failed,
        creating_collection,
        ep,
      ) ->
        photo_view(
          photo,
          liked,
          dropdown_open,
          user_collections,
          image_failed,
          creating_collection,
          ep,
          auth,
        )
      Failed -> error_view()
    },
  ])
}

fn loading_view() -> Element(Message) {
  div([class("flex justify-center py-20")], [
    p([class("text-gray-400 text-sm")], [text("Loading…")]),
  ])
}

fn error_view() -> Element(Message) {
  div([class("flex justify-center py-20")], [
    p([class("text-red-500 text-sm")], [text("Photo not found.")]),
  ])
}

fn photo_view(
  photo: shared_photo.Photo,
  liked: Bool,
  dropdown_open: Bool,
  user_collections: option.Option(List(shared_collection.Collection)),
  image_failed: Bool,
  creating_collection: Bool,
  editing_photo: Bool,
  auth: Auth,
) -> Element(Message) {
  let is_owner = case auth {
    auth.LoggedIn(user) -> user.username == photo.thumbnail.creator.username
    _ -> False
  }

  div([class("space-y-6")], [
    // Header with creator
    div([class("flex items-center justify-between")], [
      div([class("flex items-center gap-3")], [
        a(
          [
            route.href(route.User(photo.thumbnail.creator.username)),
            class("text-sm font-medium text-gray-800 hover:text-black"),
          ],
          [text(photo.thumbnail.creator.username)],
        ),
        case photo.thumbnail.privacy {
          shared_privacy.Premium ->
            span(
              [
                class(
                  "bg-yellow-100 text-yellow-800 text-[10px] font-bold px-2 py-0.5 rounded",
                ),
              ],
              [text("PREMIUM")],
            )
          shared_privacy.Private ->
            span(
              [
                class(
                  "bg-red-100 text-red-800 text-[10px] font-bold px-2 py-0.5 rounded",
                ),
              ],
              [text("PRIVATE")],
            )
          shared_privacy.Public -> element.none()
        },
        case photo.thumbnail.show_on_profile {
          False ->
            span(
              [
                class(
                  "bg-gray-200 text-gray-800 text-[10px] font-bold px-2 py-0.5 rounded",
                ),
              ],
              [text("HIDDEN FROM PROFILE")],
            )
          True -> element.none()
        },
      ]),
      div([class("flex items-center gap-2")], [
        a(
          [
            route.href(route.Censor(photo.thumbnail.public_id)),
            class(
              "flex items-center gap-1 rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-100",
            ),
          ],
          [text("Censor Image")],
        ),

        case is_owner {
          True ->
            div([class("flex items-center gap-2")], [
              button(
                [
                  type_("button"),
                  event.on_click(OpenEditPhoto),
                  class(
                    "rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-blue-600 hover:bg-blue-50",
                  ),
                ],
                [text("Edit")],
              ),
              button(
                [
                  type_("button"),
                  event.on_click(DeletePhoto),
                  class(
                    "rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-600 hover:bg-red-50",
                  ),
                ],
                [text("Delete")],
              ),
            ])
          False -> element.none()
        },

        case auth.is_logged_in(auth) {
          True -> {
            let logged_in_username = case auth {
              auth.LoggedIn(u) -> u.username
              _ -> ""
            }
            div(
              [
                class("relative inline-block"),
                event.stop_propagation(event.on_click(NoOp)),
              ],
              [
                button(
                  [
                    event.on_click(ToggleDropdown(logged_in_username)),
                    class({
                      let in_any =
                        !list.is_empty(photo.thumbnail.current_user_collections)
                      case dropdown_open, in_any {
                        True, _ ->
                          "flex items-center justify-center rounded-md border border-blue-300 bg-blue-50 w-9 h-9 text-lg font-medium text-blue-600 hover:bg-blue-100"
                        False, True ->
                          "flex items-center justify-center rounded-md border border-green-300 bg-green-500 w-9 h-9 text-lg font-medium text-white hover:bg-green-600"
                        False, False ->
                          "flex items-center justify-center rounded-md border border-gray-300 w-9 h-9 text-lg font-medium text-gray-600 hover:bg-gray-50"
                      }
                    }),
                  ],
                  [text("+")],
                ),
                case dropdown_open {
                  True ->
                    div(
                      [
                        class(
                          "absolute right-0 mt-2 w-64 bg-white border border-gray-200 rounded-md shadow-lg z-10 p-4",
                        ),
                      ],
                      case creating_collection {
                        True -> [
                          div([class("flex items-center gap-2 mb-4")], [
                            button(
                              [
                                type_("button"),
                                event.prevent_default(
                                  event.stop_propagation(event.on_click(
                                    CloseCreateCollection,
                                  )),
                                ),
                                class(
                                  "text-gray-500 hover:text-black font-bold",
                                ),
                              ],
                              [text("<")],
                            ),
                            html.h3([class("text-sm font-bold text-gray-800")], [
                              text("Create a new collection"),
                            ]),
                          ]),
                          html.form(
                            [
                              attribute.action("/napi/collections"),
                              attribute.method("POST"),
                            ],
                            [
                              html.input([
                                type_("hidden"),
                                attribute.name("redirect_to"),
                                value("/photos/" <> photo.thumbnail.public_id),
                              ]),
                              html.input([
                                type_("hidden"),
                                attribute.name("photo_public_id"),
                                value(photo.thumbnail.public_id),
                              ]),
                              p(
                                [class("text-xs font-bold text-gray-700 mb-1")],
                                [text("Name")],
                              ),
                              html.input([
                                type_("text"),
                                attribute.name("name"),
                                placeholder("New collection name"),
                                attribute.required(True),
                                class(
                                  "w-full border border-gray-300 rounded px-2 py-1 text-sm mb-3",
                                ),
                              ]),
                              p(
                                [class("text-xs font-bold text-gray-700 mb-1")],
                                [text("Description (optional)")],
                              ),
                              textarea(
                                [
                                  attribute.name("description"),
                                  attribute.rows(2),
                                  class(
                                    "w-full border border-gray-300 rounded px-2 py-1 text-sm mb-3 resize-none",
                                  ),
                                ],
                                "",
                              ),
                              div([class("flex items-center gap-2 mb-4")], [
                                html.input([
                                  type_("checkbox"),
                                  attribute.name("private"),
                                  attribute.id(
                                    "private_collection_"
                                    <> photo.thumbnail.public_id,
                                  ),
                                ]),
                                html.label(
                                  [
                                    attribute.for(
                                      "private_collection_"
                                      <> photo.thumbnail.public_id,
                                    ),
                                    class("text-xs text-gray-700"),
                                  ],
                                  [text("Private")],
                                ),
                              ]),
                              div(
                                [
                                  class(
                                    "flex items-center justify-between mt-2",
                                  ),
                                ],
                                [
                                  button(
                                    [
                                      type_("button"),
                                      event.prevent_default(
                                        event.stop_propagation(event.on_click(
                                          CloseCreateCollection,
                                        )),
                                      ),
                                      class(
                                        "text-sm text-gray-500 hover:text-black font-medium",
                                      ),
                                    ],
                                    [text("Cancel")],
                                  ),
                                  button(
                                    [
                                      type_("submit"),
                                      class(
                                        "bg-black text-white rounded px-4 py-1 text-sm font-medium",
                                      ),
                                    ],
                                    [text("Create collection")],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ]
                        False -> [
                          html.h3(
                            [class("text-sm font-bold text-gray-800 mb-2")],
                            [text("Add to Collection")],
                          ),
                          case user_collections {
                            option.None ->
                              p([class("text-xs text-gray-500")], [
                                text("Loading..."),
                              ])
                            option.Some([]) ->
                              p([class("text-xs text-gray-500 mb-2")], [
                                text("No collections yet."),
                              ])
                            option.Some(cols) ->
                              div(
                                [
                                  class(
                                    "max-h-40 overflow-y-auto mb-2 space-y-1",
                                  ),
                                ],
                                list.map(cols, fn(c) {
                                  let in_collection =
                                    list.contains(
                                      photo.thumbnail.current_user_collections,
                                      c.public_id,
                                    )
                                  let click_msg = case in_collection {
                                    True -> RemovePhotoFromCollection(c.public_id)
                                    False -> AddPhotoToCollection(c.public_id)
                                  }
                                  button(
                                    [
                                      event.prevent_default(
                                        event.stop_propagation(event.on_click(
                                          click_msg,
                                        )),
                                      ),
                                      class(
                                        "w-full text-left flex items-center justify-between group hover:bg-gray-100 px-2 py-1.5 rounded",
                                      ),
                                    ],
                                    [
                                      span(
                                        [
                                          class(
                                            "text-sm text-gray-700 truncate max-w-[150px]",
                                          ),
                                        ],
                                        [text(c.name)],
                                      ),
                                      case in_collection {
                                        True ->
                                          div(
                                            [
                                              class(
                                                "flex items-center justify-center w-5",
                                              ),
                                            ],
                                            [
                                              span(
                                                [
                                                  class(
                                                    "text-green-600 group-hover:hidden",
                                                  ),
                                                ],
                                                [text("✓")],
                                              ),
                                              span(
                                                [
                                                  class(
                                                    "hidden group-hover:inline text-red-600 font-bold",
                                                  ),
                                                ],
                                                [text("-")],
                                              ),
                                            ],
                                          )
                                        False ->
                                          div(
                                            [
                                              class(
                                                "flex items-center justify-center w-5",
                                              ),
                                            ],
                                            [
                                              span(
                                                [
                                                  class(
                                                    "hidden group-hover:inline text-gray-600 font-bold",
                                                  ),
                                                ],
                                                [text("+")],
                                              ),
                                            ],
                                          )
                                      },
                                    ],
                                  )
                                }),
                              )
                          },
                          div([class("pt-3 mt-2 border-t border-gray-200")], [
                            button(
                              [
                                type_("button"),
                                event.prevent_default(
                                  event.stop_propagation(event.on_click(
                                    OpenCreateCollection,
                                  )),
                                ),
                                class(
                                  "w-full text-left flex items-center gap-2 text-sm text-gray-700 hover:text-black font-medium",
                                ),
                              ],
                              [
                                span([class("text-lg font-normal")], [text("+")]),
                                text("Create a new collection"),
                              ],
                            ),
                          ]),
                        ]
                      },
                    )
                  False -> element.none()
                },
              ],
            )
          }
          False -> element.none()
        },
        case auth.is_logged_in(auth) {
          True ->
            button(
              [
                event.on_click(UserClickedLike),
                class(case liked {
                  True ->
                    "flex items-center gap-1 rounded-md border border-red-300 bg-red-50 px-3 py-1.5 text-sm font-medium text-red-600 hover:bg-red-100"
                  False ->
                    "flex items-center gap-1 rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-600 hover:bg-gray-50"
                }),
              ],
              [
                text(case liked {
                  True -> "♥ Liked"
                  False -> "♡ Like"
                }),
              ],
            )
          False -> element.none()
        },
      ]),
    ]),

    case editing_photo {
      True ->
        form(
          [
            action("/napi/photos/" <> photo.thumbnail.public_id),
            method("POST"),
            class("bg-gray-50 p-6 rounded-lg space-y-4"),
          ],
          [
            h1([class("text-xl font-bold text-gray-900 mb-4")], [
              text("Edit Photo"),
            ]),
            p([class("text-xs font-bold text-gray-700 mb-1")], [
              text("Description"),
            ]),
            textarea(
              [
                name("description"),
                rows(3),
                class("w-full border border-gray-300 rounded px-3 py-2 text-sm"),
              ],
              case photo.description {
                option.Some(d) -> d
                option.None -> ""
              },
            ),

            p([class("text-xs font-bold text-gray-700 mt-3 mb-1")], [
              text("Location"),
            ]),
            input([
              type_("text"),
              name("location"),
              value(case photo.location {
                option.Some(l) -> l
                option.None -> ""
              }),
              class("w-full border border-gray-300 rounded px-3 py-2 text-sm"),
            ]),

            p([class("text-xs font-bold text-gray-700 mt-3 mb-1")], [
              text("Camera"),
            ]),
            input([
              type_("text"),
              name("camera"),
              value(case photo.camera {
                option.Some(c) -> c
                option.None -> ""
              }),
              class("w-full border border-gray-300 rounded px-3 py-2 text-sm"),
            ]),

            p([class("text-xs font-bold text-gray-700 mt-3 mb-1")], [
              text("Tags (comma separated)"),
            ]),
            input([
              type_("text"),
              name("tags"),
              value(string.join(photo.tags, ",")),
              class("w-full border border-gray-300 rounded px-3 py-2 text-sm"),
            ]),

            p([class("text-xs font-bold text-gray-700 mt-3 mb-1")], [
              text("Privacy"),
            ]),
            select(
              [
                name("privacy"),
                class("w-full border border-gray-300 rounded px-3 py-2 text-sm"),
              ],
              [
                html_option(
                  [
                    value("public"),
                    selected(photo.thumbnail.privacy == shared_privacy.Public),
                  ],
                  "Public",
                ),
                html_option(
                  [
                    value("premium"),
                    selected(photo.thumbnail.privacy == shared_privacy.Premium),
                  ],
                  "Premium",
                ),
                html_option(
                  [
                    value("private"),
                    selected(photo.thumbnail.privacy == shared_privacy.Private),
                  ],
                  "Private",
                ),
              ],
            ),

            div([class("flex items-center gap-2 mt-4 mb-4")], [
              input([
                type_("checkbox"),
                name("show_on_profile"),
                id("show_on_profile"),
                checked(photo.thumbnail.show_on_profile),
              ]),
              label([for("show_on_profile"), class("text-sm text-gray-700")], [
                text("Show on Profile"),
              ]),
            ]),

            div(
              [
                class(
                  "flex items-center justify-between mt-4 pt-4 border-t border-gray-200",
                ),
              ],
              [
                button(
                  [
                    type_("button"),
                    event.prevent_default(
                      event.stop_propagation(event.on_click(CloseEditPhoto)),
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
              ],
            ),
          ],
        )
      False ->
        div([class("space-y-6")], [
          // Photo image
          case image_failed {
            True ->
              div(
                [
                  class(
                    "w-full rounded-lg min-h-96 bg-gray-200 flex flex-col items-center justify-center text-gray-400",
                  ),
                ],
                [
                  div([class("text-6xl mb-4")], [text("🔒")]),
                  span([class("text-lg font-medium")], [text("Premium content")]),
                ],
              )
            False ->
              img([
                src(api_photo.src_url(photo.thumbnail, auth)),
                alt(case photo.description {
                  option.Some(t) -> t
                  option.None -> "Photo"
                }),
                event.on("error", decode.success(ImageLoadError)),
                class("w-full rounded-lg"),
              ])
          },
          // Description
          case photo.thumbnail.description {
            option.Some(desc) ->
              p([class("text-sm text-gray-600")], [text(desc)])
            option.None -> element.none()
          },
          // Stats row
          div([class("flex gap-6 text-sm text-gray-500")], [
            stat("Views", photo.stats.views),
            stat("Likes", photo.stats.likes),
            stat("Downloads", photo.stats.downloads),
          ]),
          // Details
          case photo.location {
            option.Some(loc) ->
              p([class("text-sm text-gray-500")], [text("📍 " <> loc)])
            option.None -> element.none()
          },
          case photo.camera {
            option.Some(cam) ->
              p([class("text-sm text-gray-500")], [text("📷 " <> cam)])
            option.None -> element.none()
          },
          // Tags
          case photo.tags {
            [] -> element.none()
            tags ->
              div(
                [class("flex flex-wrap gap-2")],
                list.map(tags, fn(tag) {
                  span(
                    [
                      class(
                        "rounded-full bg-gray-100 px-3 py-1 text-xs text-gray-600",
                      ),
                    ],
                    [text(tag)],
                  )
                }),
              )
          },
        ])
    },
  ])
}

fn stat(label: String, value: Int) -> Element(msg) {
  span([], [
    span([class("font-medium text-gray-800")], [text(int.to_string(value))]),
    text(" " <> label),
  ])
}
