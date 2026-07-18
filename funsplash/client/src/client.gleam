import api/api_auth
import auth.{type Auth}
import lustre
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import modem
import router
import rsvp
import shared/shared_user

// MAIN ------------------------------------------------------------------------

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(page: router.Page, auth: Auth)
}

type Message {
  RouterMessage(router.Message)
  ApiReturnedMe(Result(shared_user.User, rsvp.Error(String)))
}

fn init(_) -> #(Model, Effect(Message)) {
  let #(page, page_effect) = router.init(modem.initial_uri())

  #(
    Model(page:, auth: auth.Unknown),
    effect.batch([
      modem.init(fn(uri) { RouterMessage(router.on_url_change(uri)) }),
      effect.map(page_effect, RouterMessage),
      api_auth.fetch_me(ApiReturnedMe),
    ]),
  )
}

// UPDATE ----------------------------------------------------------------------

fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    RouterMessage(msg) -> {
      let #(page, effect) = router.update(model.page, msg, model.auth)
      #(Model(..model, page:), effect.map(effect, RouterMessage))
    }
    ApiReturnedMe(Ok(user)) -> {
      let new_auth = auth.LoggedIn(user)
      let #(page, eff) = router.check_auth_redirect(model.page, new_auth)
      #(Model(page:, auth: new_auth), effect.map(eff, RouterMessage))
    }
    ApiReturnedMe(Error(_)) -> {
      let new_auth = auth.LoggedOut
      let #(page, eff) = router.check_auth_redirect(model.page, new_auth)
      #(Model(page:, auth: new_auth), effect.map(eff, RouterMessage))
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Message) {
  router.view(model.page, model.auth) |> element.map(RouterMessage)
}
