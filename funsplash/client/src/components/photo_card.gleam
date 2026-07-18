import api/api_collection
import api/api_photo
import api/api_user
import auth
import gleam/dynamic/decode
import gleam/list
import gleam/option
import lustre/attribute.{alt, class, href, placeholder, src, type_, value}
import lustre/effect.{type Effect}
import lustre/element.{type Element, text}
import lustre/element/html.{
  a, button, div, form, h3, img, input, p, span, textarea,
}
import lustre/event
import route
import rsvp
import shared/shared_collection
import shared/shared_privacy
import shared/shared_thumbnail.{type Thumbnail}
import shared/shared_user

pub type Model {
  Model(
    thumb: Thumbnail,
    dropdown_open: Bool,
    user_collections: option.Option(List(shared_collection.Collection)),
    image_failed: Bool,
    creating_collection: Bool,
  )
}

pub fn init(thumb: Thumbnail) -> Model {
  Model(thumb, False, option.None, False, False)
}

pub type Message {
  UserClickedLike
  ApiReturnedLike(Result(Nil, rsvp.Error(String)))
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
}

pub fn update(model: Model, msg: Message) -> #(Model, Effect(Message)) {
  case msg {
    CloseDropdown -> #(
      Model(..model, dropdown_open: False, creating_collection: False),
      effect.none(),
    )
    NoOp -> #(model, effect.none())
    OpenCreateCollection -> #(
      Model(..model, creating_collection: True),
      effect.none(),
    )
    CloseCreateCollection -> #(
      Model(..model, creating_collection: False),
      effect.none(),
    )
    ImageLoadError -> #(Model(..model, image_failed: True), effect.none())
    UserClickedLike -> {
      let is_like = !model.thumb.user_liked
      let new_thumb =
        shared_thumbnail.Thumbnail(..model.thumb, user_liked: is_like)
      #(
        Model(..model, thumb: new_thumb),
        api_photo.like(model.thumb.public_id, is_like, ApiReturnedLike),
      )
    }
    ApiReturnedLike(Error(_)) -> {
      // Rollback on error
      let new_thumb =
        shared_thumbnail.Thumbnail(
          ..model.thumb,
          user_liked: !model.thumb.user_liked,
        )
      #(Model(..model, thumb: new_thumb), effect.none())
    }
    ToggleDropdown(username) -> {
      let new_open = !model.dropdown_open
      let eff = case new_open, model.user_collections {
        True, option.None ->
          api_user.fetch_collections(username, ApiReturnedCollections)
        _, _ -> effect.none()
      }
      #(
        Model(..model, dropdown_open: new_open, creating_collection: False),
        eff,
      )
    }
    ApiReturnedCollections(Ok(collections)) -> {
      #(
        Model(..model, user_collections: option.Some(collections)),
        effect.none(),
      )
    }
    AddPhotoToCollection(cid) -> {
      #(
        model,
        api_collection.add_photo(cid, model.thumb.public_id, fn(res) {
          ApiReturnedAddPhoto(#(cid, res))
        }),
      )
    }
    ApiReturnedAddPhoto(#(cid, Ok(_))) -> {
      let new_thumb =
        shared_thumbnail.Thumbnail(..model.thumb, current_user_collections: [
          cid,
          ..model.thumb.current_user_collections
        ])
      #(Model(..model, thumb: new_thumb), effect.none())
    }
    RemovePhotoFromCollection(cid) -> {
      #(
        model,
        api_collection.remove_photo(cid, model.thumb.public_id, fn(res) {
          ApiReturnedRemovePhoto(#(cid, res))
        }),
      )
    }
    ApiReturnedRemovePhoto(#(cid, Ok(_))) -> {
      let new_thumb =
        shared_thumbnail.Thumbnail(
          ..model.thumb,
          current_user_collections: list.filter(
            model.thumb.current_user_collections,
            fn(c) { c != cid },
          ),
        )
      #(Model(..model, thumb: new_thumb), effect.none())
    }
    _ -> #(model, effect.none())
  }
}

pub fn view(model: Model, current_auth: auth.Auth) -> Element(Message) {
  let thumb = model.thumb
  div(
    [
      class("group relative overflow-visible rounded-lg bg-gray-100"),
    ],
    [
      a(
        [
          href("/photos/" <> thumb.public_id),
          class("block h-full overflow-hidden rounded-lg"),
        ],
        [
          case model.image_failed {
            True ->
              div(
                [
                  class(
                    "w-full h-full min-h-48 bg-gray-200 flex flex-col items-center justify-center text-gray-400",
                  ),
                ],
                [
                  div([class("text-4xl mb-2")], [text("🔒")]),
                  span([class("text-sm font-medium")], [text("Premium content")]),
                ],
              )
            False ->
              img([
                src(api_photo.src_url(thumb, current_auth)),
                alt(case thumb.description {
                  option.Some(d) -> d
                  option.None -> "Photo by " <> thumb.creator.username
                }),
                event.on("error", decode.success(ImageLoadError)),
                class(
                  "w-full h-full object-cover transition-transform duration-300 group-hover:scale-105",
                ),
              ])
          },
        ],
      ),
      div(
        [
          class(
            "absolute top-2 right-2 flex flex-col gap-1 items-end pointer-events-none",
          ),
        ],
        [
          case thumb.privacy {
            shared_privacy.Premium ->
              div(
                [
                  class(
                    "bg-yellow-500/90 text-white text-[10px] font-bold px-1.5 py-0.5 rounded shadow-sm backdrop-blur-sm",
                  ),
                ],
                [text("PREMIUM")],
              )
            shared_privacy.Private ->
              div(
                [
                  class(
                    "bg-red-500/90 text-white text-[10px] font-bold px-1.5 py-0.5 rounded shadow-sm backdrop-blur-sm",
                  ),
                ],
                [text("PRIVATE")],
              )
            shared_privacy.Public -> element.none()
          },
          case thumb.show_on_profile {
            False ->
              div(
                [
                  class(
                    "bg-gray-800/90 text-white text-[10px] font-bold px-1.5 py-0.5 rounded shadow-sm backdrop-blur-sm",
                  ),
                ],
                [text("HIDDEN")],
              )
            True -> element.none()
          },
        ],
      ),
      div(
        [
          class(
            "absolute top-2 left-2 flex flex-col gap-2 opacity-0 group-hover:opacity-100 transition-opacity z-10",
          ),
        ],
        [
          case current_auth {
            auth.LoggedIn(u) -> {
              let logged_in_username = u.username
              div(
                [
                  class("relative inline-block"),
                  event.stop_propagation(event.on_click(NoOp)),
                ],
                [
                  div([class("flex flex-col gap-2")], [
                    button(
                      [
                        event.on_click(UserClickedLike),
                        class(
                          "bg-white/90 text-black hover:bg-white p-1.5 rounded shadow-sm backdrop-blur-sm transition-colors flex items-center justify-center w-8 h-8",
                        ),
                      ],
                      [
                        case thumb.user_liked {
                          True -> text("♥")
                          False -> text("♡")
                        },
                      ],
                    ),
                    button(
                      [
                        event.on_click(ToggleDropdown(logged_in_username)),
                        class({
                          let in_any =
                            !list.is_empty(thumb.current_user_collections)
                          case model.dropdown_open, in_any {
                            True, _ ->
                              "bg-blue-500/90 text-white hover:bg-blue-600 p-1.5 rounded shadow-sm backdrop-blur-sm transition-colors flex items-center justify-center w-8 h-8 font-bold text-lg"
                            False, True ->
                              "bg-green-500/90 text-white hover:bg-green-600 p-1.5 rounded shadow-sm backdrop-blur-sm transition-colors flex items-center justify-center w-8 h-8 font-bold text-lg"
                            False, False ->
                              "bg-white/90 text-black hover:bg-white p-1.5 rounded shadow-sm backdrop-blur-sm transition-colors flex items-center justify-center w-8 h-8 font-bold text-lg"
                          }
                        }),
                      ],
                      [text("+")],
                    ),
                  ]),
                  case model.dropdown_open {
                    True ->
                      div(
                        [
                          class(
                            "absolute left-10 top-10 mt-1 w-64 bg-white border border-gray-200 rounded-md shadow-lg z-50 p-4",
                          ),
                        ],
                        case model.creating_collection {
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
                              h3([class("text-sm font-bold text-gray-800")], [
                                text("Create a new collection"),
                              ]),
                            ]),
                            form(
                              [
                                attribute.action("/napi/collections"),
                                attribute.method("POST"),
                              ],
                              [
                                input([
                                  type_("hidden"),
                                  attribute.name("redirect_to"),
                                  value("/photos/" <> thumb.public_id),
                                ]),
                                input([
                                  type_("hidden"),
                                  attribute.name("photo_public_id"),
                                  value(thumb.public_id),
                                ]),
                                p(
                                  [
                                    class(
                                      "text-xs font-bold text-gray-700 mb-1",
                                    ),
                                  ],
                                  [text("Name")],
                                ),
                                input([
                                  type_("text"),
                                  attribute.name("name"),
                                  placeholder("New collection name"),
                                  attribute.required(True),
                                  class(
                                    "w-full border border-gray-300 rounded px-2 py-1 text-sm mb-3",
                                  ),
                                ]),
                                p(
                                  [
                                    class(
                                      "text-xs font-bold text-gray-700 mb-1",
                                    ),
                                  ],
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
                                  input([
                                    type_("checkbox"),
                                    attribute.name("private"),
                                    attribute.id(
                                      "private_collection_" <> thumb.public_id,
                                    ),
                                  ]),
                                  html.label(
                                    [
                                      attribute.for(
                                        "private_collection_" <> thumb.public_id,
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
                            h3([class("text-sm font-bold text-gray-800 mb-2")], [
                              text("Add to Collection"),
                            ]),
                            case model.user_collections {
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
                                        thumb.current_user_collections,
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
                                  span([class("text-lg font-normal")], [
                                    text("+"),
                                  ]),
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
            auth.LoggedOut | auth.Unknown -> element.none()
          },
        ],
      ),
      div(
        [
          class(
            "absolute bottom-0 left-0 right-0 p-3 bg-gradient-to-t from-black/60 to-transparent opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none rounded-b-lg",
          ),
        ],
        [
          a(
            [
              route.href(route.User(thumb.creator.username)),
              class(
                "text-sm text-white font-medium hover:underline pointer-events-auto",
              ),
            ],
            [text(thumb.creator.username)],
          ),
          case thumb.description {
            option.Some(desc) ->
              p([class("text-xs text-white/80 mt-0.5 line-clamp-2")], [
                text(desc),
              ])
            option.None -> element.none()
          },
        ],
      ),
    ],
  )
}
