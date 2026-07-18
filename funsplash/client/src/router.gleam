import auth.{type Auth}
import components/layout
import components/navbar
import gleam/option.{None}
import gleam/uri.{type Uri}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import modem
import pages/account as account_page
import pages/auth as auth_page
import pages/censor
import pages/collection
import pages/home
import pages/not_found
import pages/photo
import pages/profile
import pages/upload
import pages/users_search
import route.{
  Collection, Index, Join, Login, NotFound, Photo, Redirect, Upload, User,
  UsersSearch,
}

pub fn init(initial_uri: Result(Uri, Nil)) -> #(Page, Effect(Message)) {
  case initial_uri {
    Ok(uri) -> route.parse(uri)
    Error(_) -> Index
  }
  |> page_from_route(auth.Unknown)
}

pub type Page {
  HomePage(model: home.Model)
  PhotoPage(model: photo.Model)
  ProfilePage(model: profile.Model)
  AuthPage(model: auth_page.Model)
  UploadPage(model: upload.Model)
  UsersSearchPage(model: users_search.Model)
  CensorPage(model: censor.Model)
  AccountPage(model: account_page.Model)
  CollectionPage(model: collection.Model)
  NotFoundPage
}

pub type Message {
  OnRouteChanged(route: route.Route)
  HomePageSentMessage(message: home.Message)
  PhotoPageSentMessage(message: photo.Message)
  ProfilePageSentMessage(message: profile.Message)
  AuthPageSentMessage(message: auth_page.Message)
  UploadPageSentMessage(message: upload.Message)
  UsersSearchPageSentMessage(message: users_search.Message)
  CensorPageSentMessage(message: censor.Message)
  AccountPageSentMessage(message: account_page.Message)
  CollectionPageSentMessage(message: collection.Message)
  NavbarSentMessage(message: navbar.Message)
}

pub fn update(
  page: Page,
  msg: Message,
  auth: Auth,
) -> #(Page, Effect(Message)) {
  case msg, page {
    OnRouteChanged(route), current_page -> {
      case current_page {
        CensorPage(_) -> censor.close_censor_ws()
        _ -> Nil
      }
      page_from_route(route, auth)
    }
    NavbarSentMessage(nav_msg), _ -> {
      let effect = navbar.update(nav_msg)
      #(page, effect.map(effect, NavbarSentMessage))
    }
    HomePageSentMessage(p_msg), HomePage(p_model) -> {
      let #(model, effect) = home.update(p_model, p_msg)
      #(HomePage(model), effect.map(effect, HomePageSentMessage))
    }
    PhotoPageSentMessage(p_msg), PhotoPage(p_model) -> {
      let #(model, effect) = photo.update(p_model, p_msg)
      #(PhotoPage(model), effect.map(effect, PhotoPageSentMessage))
    }
    ProfilePageSentMessage(p_msg), ProfilePage(p_model) -> {
      let #(model, effect) = profile.update(p_model, p_msg)
      #(ProfilePage(model), effect.map(effect, ProfilePageSentMessage))
    }
    AuthPageSentMessage(p_msg), AuthPage(p_model) -> {
      let #(model, effect) = auth_page.update(p_model, p_msg)
      #(AuthPage(model), effect.map(effect, AuthPageSentMessage))
    }
    UploadPageSentMessage(p_msg), UploadPage(p_model) -> {
      let #(model, effect) = upload.update(p_model, p_msg)
      #(UploadPage(model), effect.map(effect, UploadPageSentMessage))
    }
    UsersSearchPageSentMessage(p_msg), UsersSearchPage(p_model) -> {
      let #(model, effect) = users_search.update(p_model, p_msg)
      #(UsersSearchPage(model), effect.map(effect, UsersSearchPageSentMessage))
    }
    CensorPageSentMessage(p_msg), CensorPage(p_model) -> {
      let #(model, effect) = censor.update(p_model, p_msg)
      #(CensorPage(model), effect.map(effect, CensorPageSentMessage))
    }
    AccountPageSentMessage(p_msg), AccountPage(p_model) -> {
      let #(model, effect) = account_page.update(p_model, p_msg)
      #(AccountPage(model), effect.map(effect, AccountPageSentMessage))
    }
    CollectionPageSentMessage(p_msg), CollectionPage(p_model) -> {
      let #(model, effect) = collection.update(p_model, p_msg)
      #(CollectionPage(model), effect.map(effect, CollectionPageSentMessage))
    }
    _, _ -> #(page, effect.none())
  }
}

pub fn page_from_route(
  route: route.Route,
  auth: Auth,
) -> #(Page, Effect(Message)) {
  case route, auth {
    Index, _ -> {
      let #(model, eff) = home.init()
      #(HomePage(model), effect.map(eff, HomePageSentMessage))
    }
    Photo(id), _ -> {
      let #(model, eff) = photo.init(id)
      #(PhotoPage(model), effect.map(eff, PhotoPageSentMessage))
    }
    route.Censor(id), _ -> {
      let #(model, eff) = censor.init(id)
      #(CensorPage(model), effect.map(eff, CensorPageSentMessage))
    }
    User(name), _ | route.UserCollections(name), _ | route.UserStats(name), _ -> {
      let #(model, eff) = profile.init(name)
      #(ProfilePage(model), effect.map(eff, ProfilePageSentMessage))
    }
    // Logged in → redirect away from auth pages
    Login(_), auth.LoggedIn(_) | Join(_), auth.LoggedIn(_) -> redirect_home()
    Login(query), _ -> {
      let #(model, eff) = auth_page.init(auth_page.LoginMode, query)
      #(AuthPage(model), effect.map(eff, AuthPageSentMessage))
    }
    Join(query), _ -> {
      let #(model, eff) = auth_page.init(auth_page.SignUpMode, query)
      #(AuthPage(model), effect.map(eff, AuthPageSentMessage))
    }
    // Logged in or Unknown → allow upload/account
    Upload(query), auth.LoggedIn(_) | Upload(query), auth.Unknown -> {
      let #(model, eff) = upload.init(query)
      #(UploadPage(model), effect.map(eff, UploadPageSentMessage))
    }
    route.Account(query), auth.LoggedIn(_)
    | route.Account(query), auth.Unknown
    -> {
      let #(model, eff) = account_page.init(account_page.EditProfileMode, query)
      #(AccountPage(model), effect.map(eff, AccountPageSentMessage))
    }
    route.AccountPassword(query), auth.LoggedIn(_)
    | route.AccountPassword(query), auth.Unknown
    -> {
      let #(model, eff) =
        account_page.init(account_page.ChangePasswordMode, query)
      #(AccountPage(model), effect.map(eff, AccountPageSentMessage))
    }
    UsersSearch(username), _ -> {
      let #(model, eff) = users_search.init(username)
      #(UsersSearchPage(model), effect.map(eff, UsersSearchPageSentMessage))
    }
    // Not logged in → redirect to login
    Upload(_), _ | route.Account(_), _ | route.AccountPassword(_), _ ->
      redirect_login()
    Collection(id), _ -> {
      let #(model, eff) = collection.init(id)
      #(CollectionPage(model), effect.map(eff, CollectionPageSentMessage))
    }
    NotFound(_), _ -> #(NotFoundPage, effect.none())
    Redirect(url), _ -> {
      let target = route.parse(uri.Uri(..uri.empty, path: url))
      let #(page, page_effect) = page_from_route(target, auth)
      #(page, effect.batch([page_effect, modem.replace(url, None, None)]))
    }
  }
}

fn redirect_home() -> #(Page, Effect(Message)) {
  let #(model, eff) = home.init()
  #(
    HomePage(model),
    effect.batch([
      effect.map(eff, HomePageSentMessage),
      modem.replace("/", None, None),
    ]),
  )
}

fn redirect_login() -> #(Page, Effect(Message)) {
  let #(model, eff) = auth_page.init(auth_page.LoginMode, None)
  #(
    AuthPage(model),
    effect.batch([
      effect.map(eff, AuthPageSentMessage),
      modem.replace("/login", None, None),
    ]),
  )
}

pub fn view(page: Page, auth: Auth) -> Element(Message) {
  layout.page_layout(auth, NavbarSentMessage, [
    case page {
      HomePage(model) -> home.view(model) |> element.map(HomePageSentMessage)
      PhotoPage(model) ->
        photo.view(model, auth) |> element.map(PhotoPageSentMessage)
      ProfilePage(model) ->
        profile.view(model, auth) |> element.map(ProfilePageSentMessage)
      AuthPage(model) ->
        auth_page.view(model) |> element.map(AuthPageSentMessage)
      UploadPage(model) ->
        upload.view(model) |> element.map(UploadPageSentMessage)
      UsersSearchPage(model) ->
        users_search.view(model) |> element.map(UsersSearchPageSentMessage)
      CensorPage(model) ->
        censor.view(model) |> element.map(CensorPageSentMessage)
      AccountPage(model) ->
        account_page.view(model, auth) |> element.map(AccountPageSentMessage)
      CollectionPage(model) ->
        collection.view(model, auth) |> element.map(CollectionPageSentMessage)
      NotFoundPage -> not_found.view()
    },
  ])
}

pub fn on_url_change(uri: Uri) -> Message {
  OnRouteChanged(route.parse(uri))
}

/// Re-check the current page after auth state changes.
/// If the user is now logged in but on an auth page, redirect home.
/// If the user is logged out but on upload, redirect to login.
pub fn check_auth_redirect(page: Page, auth: Auth) -> #(Page, Effect(Message)) {
  case page, auth {
    AuthPage(_), auth.LoggedIn(_) -> redirect_home()
    UploadPage(_), auth.LoggedOut -> redirect_login()
    AccountPage(_), auth.LoggedOut -> redirect_login()
    _, _ -> #(page, effect.none())
  }
}
