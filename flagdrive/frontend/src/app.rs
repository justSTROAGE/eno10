use codee::string::JsonSerdeCodec;
use flagdrive_shared::TokenRequest;
use leptos::prelude::*;
use leptos_use::storage::use_local_storage;
use leptos_use::{ColorMode, UseColorModeOptions, UseColorModeReturn, use_color_mode_with_options};
use wasm_bindgen::JsCast;

use crate::pages::{
    dashboard::Dashboard, landing::Landing, login::Login, profile::Profile, register::Register,
};

#[derive(Clone, Debug, PartialEq)]
pub enum Page {
    Landing,
    Login,
    Register,
    Dashboard,
    Profile(String),
}

#[derive(Copy, Clone)]
pub struct AppState {
    pub page: RwSignal<Page>,
    pub auth_token: Signal<Option<String>>,
    pub set_auth_token: WriteSignal<Option<String>>,
    pub username: Signal<Option<String>>,
    pub set_username: WriteSignal<Option<String>>,
}

#[component]
pub fn App() -> impl IntoView {
    let (auth_token, set_auth_token, _) =
        use_local_storage::<Option<String>, JsonSerdeCodec>("flagdrive_auth_token");
    let (username, set_username, _) =
        use_local_storage::<Option<String>, JsonSerdeCodec>("flagdrive_username");

    let initial_page = if auth_token.get_untracked().is_some() {
        Page::Dashboard
    } else {
        Page::Landing
    };

    let page = RwSignal::new(initial_page);

    if let Some(token) = auth_token.get_untracked() {
        let set_auth_token_clone = set_auth_token;
        let set_username_clone = set_username;
        let page_clone = page;

        leptos::task::spawn_local(async move {
            let opts = web_sys::RequestInit::new();
            opts.set_method("POST");

            let headers = web_sys::Headers::new().unwrap();
            headers.append("Content-Type", "application/json").unwrap();
            opts.set_headers(&headers);

            let payload = serde_json::to_string(&TokenRequest { token }).unwrap();
            opts.set_body(&wasm_bindgen::JsValue::from_str(&payload));

            if let Some(window) = web_sys::window() {
                if let Ok(origin) = window.location().origin() {
                    if let Ok(request) = web_sys::Request::new_with_str_and_init(
                        &format!("{}/api/token/verify", origin),
                        &opts,
                    ) {
                        if let Ok(resp_value) = wasm_bindgen_futures::JsFuture::from(
                            window.fetch_with_request(&request),
                        )
                        .await
                        {
                            if let Ok(resp) = resp_value.dyn_into::<web_sys::Response>() {
                                if !resp.ok() {
                                    set_auth_token_clone.set(None);
                                    set_username_clone.set(None);
                                    page_clone.set(Page::Landing);
                                }
                            }
                        }
                    }
                }
            }
        });
    }

    provide_context(AppState {
        page,
        auth_token,
        set_auth_token,
        username,
        set_username,
    });

    let UseColorModeReturn { mode, set_mode, .. } = use_color_mode_with_options(
        UseColorModeOptions::default()
            .attribute("class")
            .storage_key("theme")
            .initial_value(ColorMode::Auto),
    );

    let toggle_mode = move |_| {
        if mode.get() == ColorMode::Dark {
            set_mode.set(ColorMode::Light);
        } else {
            set_mode.set(ColorMode::Dark);
        }
    };

    view! {
        <div class="min-h-screen bg-gov-bg-light dark:bg-gov-bg-dark text-neutral-800 dark:text-neutral-200 font-sans flex flex-col transition-colors duration-300">
            {move || match page.get() {
                Page::Landing => view! { <Landing/> }.into_any(),
                Page::Login => view! { <Login/> }.into_any(),
                Page::Register => view! { <Register/> }.into_any(),
                Page::Dashboard => view! { <Dashboard/> }.into_any(),
                Page::Profile(username) => view! { <Profile username=username/> }.into_any(),
            }}

            <button
                class="fixed bottom-6 right-6 p-4 rounded-full shadow-lg bg-white dark:bg-gov-surface-dark text-gov-red hover:shadow-xl hover:scale-110 transition-all border border-neutral-200 dark:border-neutral-700 flex items-center justify-center z-50"
                on:click=toggle_mode
                title="Toggle Theme"
            >
                {move || if mode.get() == ColorMode::Dark {
                    view! { <span class="material-icons">"light_mode"</span> }
                } else {
                    view! { <span class="material-icons">"dark_mode"</span> }
                }}
            </button>
        </div>
    }
}
