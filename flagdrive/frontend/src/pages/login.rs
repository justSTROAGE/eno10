use crate::app::{AppState, Page};
use crate::components::auth_form::AuthForm;
use flagdrive_shared::{AuthRequest, AuthResponse, ErrorResponse};
use leptos::prelude::*;
use wasm_bindgen::JsCast;

#[component]
pub fn Login() -> impl IntoView {
    let state = expect_context::<AppState>();

    let login_action = Action::new_local(|(username, password): &(String, String)| {
        let username = username.clone();
        let password = password.clone();
        async move {
            let json_payload = serde_json::to_string(&AuthRequest { username, password }).unwrap();

            let opts = web_sys::RequestInit::new();
            opts.set_method("POST");
            opts.set_body(&wasm_bindgen::JsValue::from_str(&json_payload));

            let headers = web_sys::Headers::new().unwrap();
            headers.append("Content-Type", "application/json").unwrap();
            opts.set_headers(&headers);

            let origin = web_sys::window().unwrap().location().origin().unwrap();
            let request = web_sys::Request::new_with_str_and_init(
                &format!("{}/api/auth/login", origin),
                &opts,
            )
            .unwrap();
            let window = web_sys::window().unwrap();

            if let Ok(resp_value) =
                wasm_bindgen_futures::JsFuture::from(window.fetch_with_request(&request)).await
            {
                if let Ok(resp) = resp_value.dyn_into::<web_sys::Response>() {
                    if let Ok(text_promise) = resp.text() {
                        if let Ok(text_value) =
                            wasm_bindgen_futures::JsFuture::from(text_promise).await
                        {
                            if let Some(text_str) = text_value.as_string() {
                                if resp.ok() {
                                    if let Ok(json_resp) =
                                        leptos::serde_json::from_str::<AuthResponse>(&text_str)
                                    {
                                        return Ok((json_resp.token, json_resp.username));
                                    }
                                    return Err("Invalid response format".to_string());
                                } else {
                                    if let Ok(json_resp) =
                                        leptos::serde_json::from_str::<ErrorResponse>(&text_str)
                                    {
                                        return Err(json_resp.error);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Err("Login failed".to_string())
        }
    });

    let value = login_action.value();

    Effect::new(move |_| {
        if let Some(Ok((token, username))) = value.get() {
            state.set_auth_token.set(Some(token));
            state.set_username.set(Some(username));
            state.page.set(Page::Dashboard);
        }
    });

    let on_submit = move |username: String, password: String| {
        login_action.dispatch((username, password));
    };

    let is_pending = Signal::derive(move || login_action.pending().get());
    let error_msg = Signal::derive(move || value.get().and_then(|res| res.err()));

    view! {
        <div class="flex flex-col min-h-screen">
            <crate::components::navbar::Navbar />
            <AuthForm
                title="Sign In"
                subtitle="Sign in to your official FlagDrive account."
                button_label="Sign In"
                loading_label="Signing In..."
                is_pending=is_pending
                error_msg=error_msg
                on_submit=on_submit
                footer=move || view! {
                    <p class="text-sm text-neutral-600 dark:text-neutral-400">
                        "Don't have a FlagDrive account? "
                        <span
                            class="text-gov-red hover:underline cursor-pointer font-bold transition-colors"
                            on:click=move |_| state.page.set(Page::Register)
                        >
                            "Register here"
                        </span>
                    </p>
                }
            />
        </div>
    }
}
