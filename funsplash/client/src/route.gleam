import gleam/int
import gleam/option
import gleam/uri
import lustre/attribute

pub type Route {
  Index
  Photo(id: String)
  Censor(id: String)
  Collection(id: String)
  User(name: String)
  UserCollections(name: String)
  UserStats(name: String)
  Login(query: option.Option(String))
  Join(query: option.Option(String))
  Upload(query: option.Option(String))
  UsersSearch(username: String)
  NotFound(uri: uri.Uri)
  Redirect(url: String)
  Account(query: option.Option(String))
  AccountPassword(query: option.Option(String))
}

pub fn parse(uri: uri.Uri) -> Route {
  case uri.path_segments(uri.path) {
    [] | [""] -> Index
    ["@" <> username] -> User(name: username)
    ["@" <> username, "collections"] -> UserCollections(name: username)
    ["@" <> username, "stats"] -> UserStats(name: username)
    ["photos", photo_id] -> Photo(id: photo_id)
    ["photos", photo_id, "censor"] -> Censor(id: photo_id)

    ["collections", collection_id] -> Collection(id: collection_id)

    ["login"] -> Login(query: uri.query)
    ["join"] -> Join(query: uri.query)
    ["upload"] -> Upload(query: uri.query)
    ["account"] -> Account(query: uri.query)
    ["account", "password"] -> AccountPassword(query: uri.query)
    ["s", "users", username] -> UsersSearch(username)
    [username] -> Redirect("/@" <> username)

    _ -> NotFound(uri:)
  }
}

pub fn href(route: Route) -> attribute.Attribute(message) {
  let url = case route {
    Index -> "/"
    Photo(id:) -> "/photos/" <> id
    Censor(id:) -> "/photos/" <> id <> "/censor"
    Collection(id:) -> "/collections/" <> id
    User(name:) -> "/@" <> name
    UserCollections(name:) -> "/@" <> name <> "/collections"
    UserStats(name:) -> "/@" <> name <> "/stats"
    Login(_) -> "/login/"
    Join(_) -> "/join/"
    Upload(_) -> "/upload/"
    UsersSearch(_) -> "/users/"
    Account(_) -> "/account"
    AccountPassword(_) -> "/account/password"
    NotFound(uri: _) -> "/404?"
    Redirect(url:) -> url
  }

  attribute.href(url)
}
