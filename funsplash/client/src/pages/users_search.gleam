import api/api_user
import gleam/list
import gleam/option
import gleam/string
import gleam/uri
import lustre/attribute.{class, placeholder, type_, value}
import lustre/effect.{type Effect}
import lustre/element.{type Element, text}
import lustre/element/html.{a, button, div, h1, h2, input, p}
import lustre/event
import route
import rsvp
import shared/shared_user

pub type Model {
  Model(query: String, users: List(shared_user.User), loading: Bool)
}

pub type Message {
  UserUpdatedQuery(query: String)
  UserClickedSearch
  ApiReturnedUsers(Result(List(shared_user.User), rsvp.Error(String)))
}

pub fn init(username: String) -> #(Model, Effect(Message)) {
  let initial_model = Model(query: username, users: [], loading: username != "")
  let eff = case username {
    "" -> effect.none()
    q -> api_user.search(q, ApiReturnedUsers)
  }
  #(initial_model, eff)
}

pub fn update(model: Model, msg: Message) -> #(Model, Effect(Message)) {
  case msg {
    UserUpdatedQuery(q) -> #(Model(..model, query: q), effect.none())
    UserClickedSearch -> #(
      Model(..model, loading: True),
      api_user.search(model.query, ApiReturnedUsers),
    )
    ApiReturnedUsers(Ok(users)) -> #(
      Model(..model, loading: False, users: users),
      effect.none(),
    )
    ApiReturnedUsers(Error(_)) -> #(
      Model(..model, loading: False, users: []),
      effect.none(),
    )
  }
}

pub fn view(model: Model) -> Element(Message) {
  div([class("max-w-3xl mx-auto py-12 px-4")], [
    h1([class("text-3xl font-bold mb-6")], [text("Search Users")]),
    case model.loading, model.users {
      True, _ -> p([class("text-gray-500")], [text("Loading...")])
      False, [] ->
        case model.query {
          "" ->
            p([class("text-gray-500")], [
              text("Search for a user from the navigation bar."),
            ])
          _ -> p([class("text-gray-500")], [text("No users found.")])
        }
      False, users ->
        div(
          [class("grid gap-4 sm:grid-cols-2 md:grid-cols-3")],
          list.map(users, user_card),
        )
    },
  ])
}

fn user_card(user: shared_user.User) -> Element(Message) {
  a(
    [
      route.href(route.User(user.username)),
      class(
        "block rounded-lg border border-gray-200 p-4 hover:border-gray-300 hover:shadow-sm transition-all",
      ),
    ],
    [
      div([class("flex items-center gap-3")], [
        div(
          [
            class(
              "flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-full bg-gray-100 text-lg font-medium text-gray-700",
            ),
          ],
          [text(string.slice(user.first_name, 0, 1))],
        ),
        div([class("overflow-hidden")], [
          h2([class("font-semibold text-gray-900 truncate")], [
            text(user.first_name),
          ]),
          p([class("text-sm text-gray-500 truncate")], [
            text("@" <> user.username),
          ]),
        ]),
      ]),
    ],
  )
}
