import bravo/uset
import formal/form
import gleam/bool
import gleam/result
import server/sql
import server/users
import server/web
import server/web/auth
import shared/shared_account
import utils

import wisp

pub fn update(request: wisp.Request, context: web.Context) -> wisp.Response {
  use context_user <- auth.require_login(context)
  use form_data <- wisp.require_form(request)

  let new_user = {
    use form <- result.try(
      shared_account.edit_form()
      |> form.add_values(form_data.values)
      |> form.run
      |> result.replace_error(shared_account.InvalidData),
    )

    shared_account.UpdateUser(
      username: form.username,
      first_name: form.first_name,
      last_name: form.last_name,
      bio: form.bio,
      available_for_hire: form.available_for_hire,
    )
    |> users.update(context_user.id, context.state)
  }

  case new_user {
    Ok(new_user) -> {
      let _ = uset.insert_new(context.state.user_cache, new_user.id, new_user)
      wisp.redirect("/?ok")
    }
    Error(e) -> wisp.redirect("/?error=" <> shared_account.error_to_uri(e))
  }
}

pub fn change_password(
  request: wisp.Request,
  context: web.Context,
) -> wisp.Response {
  use user <- auth.require_login(context)
  use form_data <- wisp.require_form(request)

  let change_result = {
    use form <- result.try(
      shared_account.change_password_form()
      |> form.add_values(form_data.values)
      |> form.run
      |> result.replace_error(shared_account.InvalidData),
    )

    // Verify the old password against the stored value before accepting the
    // new one (audit HIGH: change_password never checked the old password, so
    // a forged/hijacked session could reset the victim's password). The stored
    // value may be hashed or plain text (see auth.verify_password).
    use stored <- result.try(
      case utils.db_limit(sql.user_find_by_id(context.state.db, user.id)) {
        Ok(row) -> Ok(row.password)
        Error(_) -> Error(shared_account.InternalError)
      },
    )
    use <- bool.guard(
      !auth.verify_password(stored, form.old),
      Error(shared_account.InvalidData),
    )

    let update_res =
      sql.user_update_password(context.state.db, user.id, auth.hash_password(form.new))
    use <- bool.guard(
      result.is_error(update_res),
      Error(shared_account.InternalError),
    )

    Ok(Nil)
  }

  case change_result {
    Ok(_) -> wisp.redirect("/account/password?ok=true")
    Error(e) ->
      wisp.redirect(
        "/account/password?error=" <> shared_account.error_to_uri(e),
      )
  }
}
