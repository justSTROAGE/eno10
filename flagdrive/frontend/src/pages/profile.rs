use crate::app::{AppState, Page};
use crate::components::navbar::Navbar;
use crate::components::profile_card::ProfileCard;
use crate::components::user_list_item::UserListItem;
use flagdrive_shared::{
    FlagDriveUser, FollowRequest, FollowersResponse, FollowingResponse, GdprRequest,
    GdprRequestResponse,
};
use leptos::prelude::*;
use leptos::serde_json;
use leptos::web_sys;
use wasm_bindgen::JsCast;

#[derive(Clone, PartialEq)]
pub enum ProfileModal {
    None,
    Followers,
    Following,
}

#[component]
pub fn Profile(username: String) -> impl IntoView {
    let state = expect_context::<AppState>();

    let is_me = Some(username.clone()) == state.username.get_untracked();

    let display_name = if is_me {
        state
            .username
            .get_untracked()
            .unwrap_or_else(|| username.clone())
    } else {
        username.clone()
    };

    let user_resource = LocalResource::new({
        let display_name = display_name.clone();
        move || {
            let name = display_name.clone();
            let logged_in_user = state.username.get_untracked();
            async move {
                let origin = web_sys::window().unwrap().location().origin().unwrap();
                let opts = web_sys::RequestInit::new();
                opts.set_method("GET");
                let request = web_sys::Request::new_with_str_and_init(
                    &format!("{}/api/user/{}", origin, name),
                    &opts,
                )
                .ok()?;
                let window = web_sys::window().unwrap();
                let resp_value =
                    wasm_bindgen_futures::JsFuture::from(window.fetch_with_request(&request))
                        .await
                        .ok()?;
                let resp: web_sys::Response = resp_value.dyn_into().ok()?;
                if !resp.ok() {
                    return None;
                }
                let text_promise = resp.text().ok()?;
                let text_value = wasm_bindgen_futures::JsFuture::from(text_promise)
                    .await
                    .ok()?;
                let text_str = text_value.as_string()?;
                let mut user: FlagDriveUser = serde_json::from_str(&text_str).ok()?;

                if let Some(me) = logged_in_user {
                    if me.to_lowercase() == name.to_lowercase() {
                        user.is_followed = false;
                    } else {
                        let request = web_sys::Request::new_with_str_and_init(
                            &format!("{}/api/user/{}/following", origin, me),
                            &opts,
                        )
                        .ok()?;
                        if let Ok(resp_value) = wasm_bindgen_futures::JsFuture::from(
                            window.fetch_with_request(&request),
                        )
                        .await
                        {
                            if let Ok(resp) = resp_value.dyn_into::<web_sys::Response>() {
                                if resp.ok() {
                                    if let Ok(text_promise) = resp.text() {
                                        if let Ok(text_value) =
                                            wasm_bindgen_futures::JsFuture::from(text_promise).await
                                        {
                                            if let Some(text_str) = text_value.as_string() {
                                                if let Ok(json) =
                                                    serde_json::from_str::<FollowingResponse>(
                                                        &text_str,
                                                    )
                                                {
                                                    let is_following =
                                                        json.following.iter().any(|s| {
                                                            s.to_lowercase() == name.to_lowercase()
                                                        });
                                                    user.is_followed = is_following;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Some(user)
            }
        }
    });

    let search_query = RwSignal::new(String::new());
    let handle_search = move |ev: leptos::ev::SubmitEvent| {
        ev.prevent_default();
        let query = search_query.get();
        if !query.is_empty() {
            state.page.set(Page::Profile(query));
        }
    };

    let gdpr_action = Action::new_local(move |_: &()| {
        let token = state.auth_token.get_untracked().unwrap_or_default();
        let current_username = state.username.get_untracked().unwrap_or_default();
        async move {
            let origin = web_sys::window().unwrap().location().origin().unwrap();
            let json_payload = serde_json::to_string(&GdprRequest {
                username: Some(current_username),
                token: token,
            })
            .unwrap();

            let opts = web_sys::RequestInit::new();
            opts.set_method("POST");
            opts.set_body(&wasm_bindgen::JsValue::from_str(&json_payload));
            let headers = web_sys::Headers::new().unwrap();
            headers.append("Content-Type", "application/json").unwrap();
            opts.set_headers(&headers);

            let request = web_sys::Request::new_with_str_and_init(
                &format!("{}/api/gdpr/request", origin),
                &opts,
            )
            .unwrap();
            let window = web_sys::window().unwrap();

            if let Ok(resp_value) =
                wasm_bindgen_futures::JsFuture::from(window.fetch_with_request(&request)).await
            {
                if let Ok(resp) = resp_value.dyn_into::<web_sys::Response>() {
                    if resp.ok() {
                        if let Ok(text_promise) = resp.text() {
                            if let Ok(text_value) =
                                wasm_bindgen_futures::JsFuture::from(text_promise).await
                            {
                                if let Some(text_str) = text_value.as_string() {
                                    if let Ok(json) =
                                        serde_json::from_str::<GdprRequestResponse>(&text_str)
                                    {
                                        let gdpr_id = &json.gdpr_id;
                                        if let Some(window) = web_sys::window() {
                                            let origin = window.location().origin().unwrap();
                                            let _ = window.location().assign(&format!(
                                                "{}/api/gdpr/download/{}",
                                                origin, gdpr_id
                                            ));
                                        }
                                        return Ok(());
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Err("Failed to request GDPR data".to_string())
        }
    });

    let follow_action = Action::new_local({
        let display_name = display_name.clone();
        move |is_following: &bool| {
            let is_following = *is_following;
            let display_name = display_name.clone();
            let token = state.auth_token.get_untracked().unwrap_or_default();
            let current_username = state.username.get_untracked().unwrap_or_default();
            async move {
                let action_endpoint = if is_following { "unfollow" } else { "follow" };
                let origin = web_sys::window().unwrap().location().origin().unwrap();
                let json_payload = serde_json::to_string(&FollowRequest {
                    username: display_name,
                    token: token,
                })
                .unwrap();

                let opts = web_sys::RequestInit::new();
                opts.set_method("POST");
                opts.set_body(&wasm_bindgen::JsValue::from_str(&json_payload));
                let headers = web_sys::Headers::new().unwrap();
                headers.append("Content-Type", "application/json").unwrap();
                opts.set_headers(&headers);

                let request = web_sys::Request::new_with_str_and_init(
                    &format!(
                        "{}/api/user/{}/{}",
                        origin, current_username, action_endpoint
                    ),
                    &opts,
                )
                .unwrap();
                let window = web_sys::window().unwrap();

                if let Ok(resp_value) =
                    wasm_bindgen_futures::JsFuture::from(window.fetch_with_request(&request)).await
                {
                    if let Ok(resp) = resp_value.dyn_into::<web_sys::Response>() {
                        if resp.ok() {
                            return Ok(());
                        }
                    }
                }
                Err("Failed to update follow relationship".to_string())
            }
        }
    });

    Effect::new(move |_| {
        if let Some(Ok(())) = follow_action.value().get() {
            user_resource.refetch();
        }
    });

    let modal_state = RwSignal::new(ProfileModal::None);

    let modal_users_resource = LocalResource::new({
        let display_name = display_name.clone();
        let state = state.clone();
        move || {
            let current_modal = modal_state.get();
            let name = display_name.clone();
            let logged_in_user = state.username.get_untracked();
            async move {
                if current_modal == ProfileModal::None {
                    return None;
                }
                let endpoint = if current_modal == ProfileModal::Followers {
                    "followers"
                } else {
                    "following"
                };
                let origin = web_sys::window().unwrap().location().origin().unwrap();

                let opts = web_sys::RequestInit::new();
                opts.set_method("GET");
                let request = web_sys::Request::new_with_str_and_init(
                    &format!("{}/api/user/{}/{}", origin, name, endpoint),
                    &opts,
                )
                .ok()?;
                let window = web_sys::window().unwrap();

                let resp_value =
                    wasm_bindgen_futures::JsFuture::from(window.fetch_with_request(&request))
                        .await
                        .ok()?;
                let resp: web_sys::Response = resp_value.dyn_into().ok()?;
                if !resp.ok() {
                    return None;
                }
                let text_promise = resp.text().ok()?;
                let text_value = wasm_bindgen_futures::JsFuture::from(text_promise)
                    .await
                    .ok()?;
                let text_str = text_value.as_string()?;

                let usernames: Vec<String> = if current_modal == ProfileModal::Followers {
                    let json = serde_json::from_str::<FollowersResponse>(&text_str).ok()?;
                    json.followers
                } else {
                    let json = serde_json::from_str::<FollowingResponse>(&text_str).ok()?;
                    json.following
                };

                let mut my_following = std::collections::HashSet::new();
                if let Some(me) = logged_in_user {
                    let request2 = web_sys::Request::new_with_str_and_init(
                        &format!("{}/api/user/{}/following", origin, me),
                        &opts,
                    )
                    .ok()?;
                    if let Ok(resp_value2) =
                        wasm_bindgen_futures::JsFuture::from(window.fetch_with_request(&request2))
                            .await
                    {
                        if let Ok(resp2) = resp_value2.dyn_into::<web_sys::Response>() {
                            if resp2.ok() {
                                if let Ok(text_promise2) = resp2.text() {
                                    if let Ok(text_value2) =
                                        wasm_bindgen_futures::JsFuture::from(text_promise2).await
                                    {
                                        if let Some(text_str2) = text_value2.as_string() {
                                            if let Ok(json2) =
                                                serde_json::from_str::<FollowingResponse>(
                                                    &text_str2,
                                                )
                                            {
                                                for s in json2.following {
                                                    my_following.insert(s.to_lowercase());
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                let result: Vec<(String, bool)> = usernames
                    .into_iter()
                    .map(|u| {
                        let is_followed = my_following.contains(&u.to_lowercase());
                        (u, is_followed)
                    })
                    .collect();

                Some(result)
            }
        }
    });

    let modal_follow_action = Action::new_local({
        let state = state.clone();
        move |(target_user, is_following): &(String, bool)| {
            let is_following = *is_following;
            let target_user = target_user.clone();
            let token = state.auth_token.get_untracked().unwrap_or_default();
            let current_username = state.username.get_untracked().unwrap_or_default();
            async move {
                let action_endpoint = if is_following { "unfollow" } else { "follow" };
                let origin = web_sys::window().unwrap().location().origin().unwrap();
                let json_payload = serde_json::to_string(&FollowRequest {
                    username: target_user,
                    token: token,
                })
                .unwrap();

                let opts = web_sys::RequestInit::new();
                opts.set_method("POST");
                opts.set_body(&wasm_bindgen::JsValue::from_str(&json_payload));
                let headers = web_sys::Headers::new().unwrap();
                headers.append("Content-Type", "application/json").unwrap();
                opts.set_headers(&headers);

                let request = web_sys::Request::new_with_str_and_init(
                    &format!(
                        "{}/api/user/{}/{}",
                        origin, current_username, action_endpoint
                    ),
                    &opts,
                )
                .unwrap();
                let window = web_sys::window().unwrap();

                if let Ok(resp_value) =
                    wasm_bindgen_futures::JsFuture::from(window.fetch_with_request(&request)).await
                {
                    if let Ok(resp) = resp_value.dyn_into::<web_sys::Response>() {
                        if resp.ok() {
                            return Ok(());
                        }
                    }
                }
                Err("Failed to update follow relationship".to_string())
            }
        }
    });

    Effect::new({
        let modal_users_resource = modal_users_resource.clone();
        let user_resource = user_resource.clone();
        move |_| {
            if let Some(Ok(())) = modal_follow_action.value().get() {
                modal_users_resource.refetch();
                user_resource.refetch();
            }
        }
    });

    view! {
        <div class="flex flex-col min-h-screen">
            <Navbar />

            <main class="flex-1 max-w-4xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-12 relative">

                <form on:submit=handle_search class="mb-8 flex gap-2 w-full">
                    <div class="relative flex-1">
                        <span class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                            <span class="material-icons text-neutral-400">"search"</span>
                        </span>
                        <input
                            type="text"
                            class="block w-full pl-10 pr-3 py-2 border border-neutral-300 dark:border-neutral-700 rounded-lg leading-5 bg-white dark:bg-gov-surface-dark text-neutral-900 dark:text-neutral-100 placeholder-neutral-500 focus:outline-none focus:ring-1 focus:ring-gov-red focus:border-gov-red sm:text-sm transition-colors"
                            placeholder="Search user..."
                            on:input=move |ev| search_query.set(event_target_value(&ev))
                            prop:value=search_query
                        />
                    </div>
                    <button type="submit" class="px-4 py-2 bg-gov-red text-white font-medium rounded-lg hover:bg-gov-red-dark transition-colors shadow-sm text-sm flex items-center">
                        "Search"
                    </button>
                </form>

                <div class="bg-white dark:bg-gov-surface-dark rounded-2xl border border-neutral-200 dark:border-neutral-700 relative overflow-hidden shadow-sm">
                    <div class="absolute top-0 left-0 w-full h-32 bg-neutral-100 dark:bg-gov-bg-dark border-b border-neutral-200 dark:border-neutral-700"></div>

                    <Suspense fallback=move || view! { <div class="relative z-10 p-8 text-center">"Loading..."</div> }>
                        {
                            move || match user_resource.get() {
                            None => view! { <div></div> }.into_any(),
                            Some(None) => view! { <div class="relative z-10 p-8 text-center text-red-500">"Failed to load profile"</div> }.into_any(),
                            Some(Some(user)) => {
                                view! {
                                    <ProfileCard
                                        user=user
                                        is_me=is_me
                                        gdpr_action=gdpr_action
                                        follow_action=follow_action
                                        modal_state=modal_state
                                    />
                                }.into_any()
                            }
                        }}
                    </Suspense>
                </div>
            </main>

            {move || {
                let current_modal = modal_state.get();
                if current_modal != ProfileModal::None {
                    let title = if current_modal == ProfileModal::Followers { "Followers" } else { "Following" };
                    view! {
                        <div class="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-0">
                            <div class="fixed inset-0 bg-black/60 backdrop-blur-sm transition-opacity" on:click=move |_| modal_state.set(ProfileModal::None)></div>

                            <div class="relative bg-white dark:bg-gov-surface-dark rounded-2xl shadow-2xl w-full max-w-md flex flex-col max-h-[80vh] border border-neutral-200 dark:border-neutral-700 transform transition-all">
                                <div class="px-6 py-4 border-b border-neutral-200 dark:border-neutral-800 flex justify-between items-center">
                                    <h2 class="text-xl font-bold text-neutral-900 dark:text-white">{title}</h2>
                                    <button
                                        class="text-neutral-400 hover:text-neutral-600 dark:hover:text-neutral-200 transition-colors"
                                        on:click=move |_| modal_state.set(ProfileModal::None)
                                    >
                                        <span class="material-icons">"close"</span>
                                    </button>
                                </div>

                                <div class="px-6 py-4 overflow-y-auto flex-1">
                                    <Suspense fallback=move || view! { <div class="text-center py-8 text-neutral-500">"Loading users..."</div> }>
                                        {move || match modal_users_resource.get() {
                                            None => view! { <div></div> }.into_any(),
                                            Some(None) => view! { <div class="text-center py-8 text-red-500">"Failed to load users"</div> }.into_any(),
                                            Some(Some(users)) => {
                                                if users.is_empty() {
                                                    view! { <div class="text-center py-8 text-neutral-500">"No users found."</div> }.into_any()
                                                } else {
                                                    let modal_follow_clone = modal_follow_action.clone();
                                                    view! {
                                                        <ul class="space-y-3">
                                                            {users.into_iter().map(|(u, is_followed)| {
                                                                let state_clone = state.clone();
                                                                let u_clone = u.clone();
                                                                let on_nav = move |_nav_u| {
                                                                    modal_state.set(ProfileModal::None);
                                                                    state_clone.page.set(Page::Profile(u_clone.clone()));
                                                                };
                                                                let modal_follow_dispatch = modal_follow_clone.clone();
                                                                let on_toggle = move |target_user: String, cur_following: bool| {
                                                                    modal_follow_dispatch.dispatch((target_user, cur_following));
                                                                };
                                                                view! {
                                                                    <UserListItem user=u is_followed=is_followed on_navigate=on_nav on_toggle=on_toggle />
                                                                }
                                                            }).collect_view()}
                                                        </ul>
                                                    }.into_any()
                                                }
                                            }
                                        }}
                                    </Suspense>
                                </div>
                            </div>
                        </div>
                    }.into_any()
                } else {
                    view! { <div class="hidden"></div> }.into_any()
                }
            }}
        </div>
    }
}
