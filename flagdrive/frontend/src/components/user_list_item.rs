use crate::app::AppState;
use leptos::prelude::*;

#[component]
pub fn UserListItem<F, G>(
    user: String,
    is_followed: bool,
    on_navigate: F,
    on_toggle: G,
) -> impl IntoView
where
    F: Fn(String) + 'static + Send + Sync + Clone,
    G: Fn(String, bool) + 'static + Send + Sync + Clone,
{
    let state = expect_context::<AppState>();
    let u_clone = user.clone();
    let on_nav_clone = on_navigate.clone();

    let is_self = Memo::new({
        let user = user.clone();
        move |_| {
            let current = state.username.get();
            current
                .map(|name| name.to_lowercase() == user.to_lowercase())
                .unwrap_or(false)
        }
    });

    view! {
        <li class="flex items-center justify-between p-3 rounded-lg bg-neutral-50 dark:bg-gov-bg-dark border border-neutral-100 dark:border-neutral-800 hover:border-gov-red/30 transition-colors">
            <div class="flex items-center gap-3 cursor-pointer" on:click=move |_| on_nav_clone(u_clone.clone())>
                <div class="w-10 h-10 rounded-full bg-neutral-200 dark:bg-neutral-700 flex items-center justify-center text-neutral-500 shrink-0">
                    <span class="material-icons text-sm">"person"</span>
                </div>
                <span class="font-medium text-neutral-900 dark:text-white">{user.clone()}</span>
            </div>
            {move || if !is_self.get() {
                let u_clone1 = user.clone();
                let on_toggle_clone = on_toggle.clone();
                if is_followed {
                    view! {
                        <button
                            class="px-3 py-1.5 text-xs font-semibold rounded-md bg-neutral-200 dark:bg-neutral-800 text-neutral-700 dark:text-neutral-300 hover:bg-neutral-300 dark:hover:bg-neutral-700 transition-colors"
                            on:click=move |_| { on_toggle_clone(u_clone1.clone(), true); }
                        >
                            "Unfollow"
                        </button>
                    }.into_any()
                } else {
                    view! {
                        <button
                            class="px-3 py-1.5 text-xs font-semibold rounded-md bg-gov-red text-white hover:bg-gov-red-dark transition-colors"
                            on:click=move |_| { on_toggle_clone(u_clone1.clone(), false); }
                        >
                            "Follow"
                        </button>
                    }.into_any()
                }
            } else {
                view! { <div class="hidden"></div> }.into_any()
            }}
        </li>
    }
}
