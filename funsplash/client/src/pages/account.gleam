import auth.{type Auth}
import formal/form
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/uri
import lustre/attribute.{class, name, type_}
import lustre/effect.{type Effect}
import lustre/element.{type Element, text}
import lustre/element/html.{a, button, div, h1, h2, input, label, p, small}
import shared/shared_account
import shared/shared_user

// MODEL -----------------------------------------------------------------------

pub type Mode {
  EditProfileMode
  ChangePasswordMode
}

pub type Model {
  Model(
    mode: Mode,
    error: Option(String),
    success: Option(String),
    edit_form: form.Form(shared_account.User),
    password_form: form.Form(shared_account.ChangePasswordForm),
  )
}

pub fn init(mode: Mode, query: Option(String)) -> #(Model, Effect(Message)) {
  let params = case query {
    Some(q) -> uri.parse_query(q) |> result.unwrap([])
    None -> []
  }
  let error = list.key_find(params, "error") |> option.from_result
  let success = list.key_find(params, "ok") |> option.from_result
  let error_msg = case error {
    Some(e) -> Some(e |> uri.percent_decode |> result.unwrap(e))
    None -> None
  }
  let success_msg = case success {
    Some(_) -> Some("Updated successfully.")
    _ -> None
  }
  #(
    Model(
      mode:,
      error: error_msg,
      success: success_msg,
      edit_form: shared_account.edit_form(),
      password_form: shared_account.change_password_form(),
    ),
    effect.none(),
  )
}

// UPDATE ----------------------------------------------------------------------

import browser
import lustre/event

pub type Message {
  EditProfileSubmitted(values: List(#(String, String)))
  ChangePasswordSubmitted(values: List(#(String, String)))
}

pub fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    EditProfileSubmitted(values) -> {
      let f = shared_account.edit_form() |> form.add_values(values)
      case form.run(f) {
        Ok(_) -> #(model, browser.submit_form_effect("edit-profile-form"))
        Error(f_with_errors) -> #(
          Model(..model, edit_form: f_with_errors),
          effect.none(),
        )
      }
    }
    ChangePasswordSubmitted(values) -> {
      let f = shared_account.change_password_form() |> form.add_values(values)
      case form.run(f) {
        Ok(_) -> #(model, browser.submit_form_effect("change-password-form"))
        Error(f_with_errors) -> #(
          Model(..model, password_form: f_with_errors),
          effect.none(),
        )
      }
    }
  }
}

// VIEW ------------------------------------------------------------------------

pub fn view(model: Model, current_auth: Auth) -> Element(Message) {
  case current_auth {
    auth.LoggedIn(user) -> account_view(model, user)
    _ -> div([class("p-8")], [text("Please log in to view this page.")])
  }
}

fn account_view(model: Model, user: shared_user.User) -> Element(Message) {
  div([class("max-w-4xl mx-auto py-8 px-4 flex flex-col md:flex-row gap-8")], [
    // Sidebar
    div([class("w-full md:w-64 shrink-0")], [
      h1([class("text-2xl font-bold mb-4")], [text("Account Settings")]),
      div([class("flex flex-col space-y-1")], [
        nav_link("Edit Profile", "/account", model.mode == EditProfileMode),
        nav_link(
          "Change Password",
          "/account/password",
          model.mode == ChangePasswordMode,
        ),
      ]),
    ]),

    // Content
    div([class("flex-grow")], [
      case model.mode {
        EditProfileMode -> edit_profile_view(model, user)
        ChangePasswordMode -> change_password_view(model)
      },
    ]),
  ])
}

fn nav_link(label_text: String, href: String, active: Bool) -> Element(msg) {
  let base_class = "px-3 py-2 rounded-md text-sm font-medium transition-colors"
  let classes = case active {
    True -> base_class <> " bg-gray-100 text-gray-900"
    False -> base_class <> " text-gray-600 hover:bg-gray-50 hover:text-gray-900"
  }
  a([attribute.href(href), class(classes)], [text(label_text)])
}

fn edit_profile_view(model: Model, user: shared_user.User) -> Element(Message) {
  let form = model.edit_form
  div([], [
    h2([class("text-xl font-semibold mb-6")], [text("Edit Profile")]),
    success_banner(model.success),
    error_banner(model.error),
    html.form(
      [
        attribute.action("/napi/account"),
        attribute.method("POST"),
        attribute.id("edit-profile-form"),
        event.on_submit(EditProfileSubmitted),
        class("space-y-4 max-w-md"),
      ],
      [
        field(form, "username", "Username", "text", Some(user.username)),
        field(form, "first_name", "First name", "text", Some(user.first_name)),
        field(form, "last_name", "Last name", "text", user.last_name),
        field(form, "bio", "Bio", "text", user.bio),
        checkbox_field(
          form,
          "available_for_hire",
          "Available for hire",
          user.available_for_hire,
        ),
        button(
          [
            type_("submit"),
            class(
              "rounded-md bg-black px-4 py-2 text-sm font-medium text-white hover:bg-gray-800",
            ),
          ],
          [text("Update Profile")],
        ),
      ],
    ),
  ])
}

fn change_password_view(model: Model) -> Element(Message) {
  let form = model.password_form
  div([], [
    h2([class("text-xl font-semibold mb-6")], [text("Change Password")]),
    success_banner(model.success),
    error_banner(model.error),
    html.form(
      [
        attribute.action("/napi/account/password"),
        attribute.method("POST"),
        attribute.id("change-password-form"),
        event.on_submit(ChangePasswordSubmitted),
        class("space-y-4 max-w-md"),
      ],
      [
        field(form, "old_password", "Current Password", "password", None),
        field(form, "new_password", "New Password", "password", None),
        field(
          form,
          "confirm_new_password",
          "Confirm New Password",
          "password",
          None,
        ),
        button(
          [
            type_("submit"),
            class(
              "rounded-md bg-black px-4 py-2 text-sm font-medium text-white hover:bg-gray-800",
            ),
          ],
          [text("Change Password")],
        ),
      ],
    ),
  ])
}

fn field(
  form: form.Form(t),
  field_name: String,
  label_text: String,
  kind: String,
  default_val: Option(String),
) -> Element(msg) {
  let errors = form.field_error_messages(form, field_name)
  let val = option.unwrap(default_val, "")
  div([], [
    label([class("block text-sm font-medium text-gray-700 mb-1")], [
      text(label_text),
    ]),
    input([
      type_(kind),
      name(field_name),
      attribute.value(val),
      class(
        "w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:border-black focus:ring-1 focus:ring-black focus:outline-none",
      ),
      case errors {
        [] -> attribute.none()
        _ -> attribute.attribute("aria-invalid", "true")
      },
    ]),
    ..list.map(errors, fn(msg) {
      small([class("text-xs text-red-600")], [text(msg)])
    })
  ])
}

fn checkbox_field(
  form: form.Form(t),
  field_name: String,
  label_text: String,
  default_checked: Bool,
) -> Element(msg) {
  let errors = form.field_error_messages(form, field_name)
  div([class("flex items-center")], [
    input([
      type_("checkbox"),
      name(field_name),
      attribute.value("true"),
      attribute.checked(default_checked),
      class("h-4 w-4 rounded border-gray-300 text-black focus:ring-black"),
    ]),
    label([class("ml-2 block text-sm text-gray-900")], [
      text(label_text),
    ]),
    ..list.map(errors, fn(msg) {
      small([class("text-xs text-red-600 block w-full mt-1")], [text(msg)])
    })
  ])
}

fn error_banner(error: Option(String)) -> Element(msg) {
  case error {
    Some(msg) ->
      div(
        [
          class(
            "rounded-md bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-700 mb-4",
          ),
        ],
        [text(msg)],
      )
    None -> element.none()
  }
}

fn success_banner(success: Option(String)) -> Element(msg) {
  case success {
    Some(msg) ->
      div(
        [
          class(
            "rounded-md bg-green-50 border border-green-200 px-4 py-3 text-sm text-green-700 mb-4",
          ),
        ],
        [text(msg)],
      )
    None -> element.none()
  }
}
