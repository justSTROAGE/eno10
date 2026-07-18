import api/api_photo
import auth.{type Auth}
import browser
import gleam/list
import gleam/option
import gleam/uri
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element, text}
import lustre/element/html.{a, button, div, form, input, nav}
import lustre/event
import modem
import route
import rsvp
import shared/shared_user

pub type Message {
  UserClickedLogout
  LogoutCompleted(Result(String, rsvp.Error(String)))
  SearchSubmitted(data: List(#(String, String)))
}

pub fn update(message: Message) -> Effect(Message) {
  case message {
    UserClickedLogout -> {
      let url = api_photo.api_base_url() <> "/logout"
      let handler = rsvp.expect_text(LogoutCompleted)
      rsvp.get(url, handler)
    }
    LogoutCompleted(_) -> {
      effect.from(fn(_) { browser.navigate_to("/") })
    }
    SearchSubmitted(data) -> {
      case list.key_find(data, "search_bar") {
        Ok(username) ->
          modem.push(
            shared_user.search_uri <> uri.percent_encode(username),
            option.None,
            option.None,
          )

        Error(_) -> effect.none()
      }
    }
  }
}

pub fn navbar(auth: Auth) -> Element(Message) {
  nav(
    [
      class(
        "flex items-center gap-6 px-5 py-3 border-b border-gray-200 bg-white",
      ),
    ],
    [
      div([class("flex items-center gap-6 flex-shrink-0")], [
        a(
          [
            attribute.href("/"),
            class("text-xl font-bold tracking-tight text-black"),
          ],
          [
            text("funsplash"),
          ],
        ),
        a(
          [
            attribute.href("/users"),
            class("text-sm font-medium text-gray-600 hover:text-black"),
          ],
          [
            text("Users"),
          ],
        ),
      ]),
      form(
        [event.on_submit(SearchSubmitted), class("flex-1 flex items-center")],
        [
          input([
            attribute.type_("text"),
            attribute.name("search_bar"),
            attribute.placeholder("Search users..."),
            class(
              "w-full rounded-full bg-gray-100 border-transparent px-4 py-1.5 text-sm focus:border-black focus:bg-white focus:ring-1 focus:ring-black focus:outline-none transition-all",
            ),
          ]),
          button([attribute.type_("submit"), class("hidden")], []),
        ],
      ),
      div([class("flex items-center gap-4 flex-shrink-0")], case auth {
        auth.LoggedIn(user) -> [
          a(
            [
              route.href(route.Upload(option.None)),
              class("text-sm text-gray-600 hover:text-black"),
            ],
            [text("Upload")],
          ),
          a(
            [
              route.href(route.User(user.username)),
              class("text-sm text-gray-600 hover:text-black"),
            ],
            [text("@" <> user.username)],
          ),
          button(
            [
              event.on_click(UserClickedLogout),
              class("text-sm text-gray-500 hover:text-black cursor-pointer"),
            ],
            [text("Log out")],
          ),
        ]
        _ -> [
          a(
            [
              route.href(route.Login(option.None)),
              class("text-sm text-gray-600 hover:text-black"),
            ],
            [text("Log in")],
          ),
          a(
            [
              route.href(route.Join(option.None)),
              class(
                "rounded-md bg-black px-4 py-1.5 text-sm text-white hover:bg-gray-800",
              ),
            ],
            [text("Join")],
          ),
        ]
      }),
    ],
  )
}
