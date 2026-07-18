use crate::pages::profile::ProfileModal;
use flagdrive_shared::FlagDriveUser;
use leptos::prelude::*;

#[component]
pub fn ProfileCard(
    user: FlagDriveUser,
    is_me: bool,
    gdpr_action: Action<(), Result<(), String>>,
    follow_action: Action<bool, Result<(), String>>,
    modal_state: RwSignal<ProfileModal>,
) -> impl IntoView {
    let followers_count = user.followers_count;
    let following_count = user.following_count;
    let u_name = user.username.clone();

    view! {
        <div class="relative z-10 p-8">
            <div class="flex flex-col md:flex-row items-center md:items-end gap-8 mt-4 mb-6">
                <div class="w-40 h-40 rounded-full bg-white dark:bg-gov-surface-dark border-4 border-white dark:border-neutral-800 flex items-center justify-center text-neutral-400 shadow-md relative overflow-hidden shrink-0">
                    <span class="material-icons mt-8" style="font-size: 200px;">"person"</span>
                </div>

                <div class="flex-1 text-center md:text-left mb-2">
                    <h1 class="text-4xl font-bold text-neutral-900 dark:text-white">
                        {u_name.clone()}
                    </h1>
                </div>

                <div class="flex justify-center md:justify-end gap-4 mb-2">
                    {if is_me {
                        view! {
                            <button
                                class="flex items-center px-4 py-2 rounded-lg font-bold text-sm bg-gov-red text-white hover:bg-gov-red-dark shadow-sm transition-all"
                                on:click=move |_| { gdpr_action.dispatch(()); }
                                title="Download GDPR Data"
                            >
                                <span class="material-icons text-[18px] mr-2">"download"</span>
                                "GDPR Data"
                            </button>
                        }.into_any()
                    } else {
                        let is_followed = user.is_followed;
                        let follow_action_clone = follow_action.clone();
                        view! {
                            {if is_followed {
                                view! {
                                    <button
                                        class="flex items-center px-6 py-2 rounded-lg font-bold text-sm bg-neutral-200 dark:bg-neutral-800 text-neutral-700 dark:text-neutral-300 hover:bg-neutral-300 dark:hover:bg-neutral-700 shadow-sm transition-all"
                                        on:click=move |_| { follow_action_clone.dispatch(true); }
                                    >
                                        <span class="material-icons text-[18px] mr-1">"person_remove"</span>
                                        "Unfollow"
                                    </button>
                                }.into_any()
                            } else {
                                view! {
                                    <button
                                        class="flex items-center px-6 py-2 rounded-lg font-bold text-sm bg-gov-red text-white hover:bg-gov-red-dark shadow-sm transition-all"
                                        on:click=move |_| { follow_action_clone.dispatch(false); }
                                    >
                                        <span class="material-icons text-[18px] mr-1">"person_add"</span>
                                        "Follow"
                                    </button>
                                }.into_any()
                            }}
                        }.into_any()
                    }}
                </div>
            </div>

            <div class="grid grid-cols-2 gap-4 mt-8 pt-8 border-t border-neutral-100 dark:border-neutral-700">
                <div
                    class="text-center p-4 bg-neutral-50 dark:bg-gov-bg-dark/50 rounded-xl border border-neutral-100 dark:border-neutral-800 cursor-pointer hover:bg-neutral-100 dark:hover:bg-neutral-800 transition-colors"
                    on:click=move |_| modal_state.set(ProfileModal::Followers)
                >
                    <div class="text-3xl font-bold text-neutral-900 dark:text-white">{followers_count}</div>
                    <div class="text-sm text-neutral-500 dark:text-neutral-400 mt-1 uppercase tracking-wider font-semibold">"Followers"</div>
                </div>
                <div
                    class="text-center p-4 bg-neutral-50 dark:bg-gov-bg-dark/50 rounded-xl border border-neutral-100 dark:border-neutral-800 cursor-pointer hover:bg-neutral-100 dark:hover:bg-neutral-800 transition-colors"
                    on:click=move |_| modal_state.set(ProfileModal::Following)
                >
                    <div class="text-3xl font-bold text-neutral-900 dark:text-white">{following_count}</div>
                    <div class="text-sm text-neutral-500 dark:text-neutral-400 mt-1 uppercase tracking-wider font-semibold">"Following"</div>
                </div>
            </div>
        </div>
    }
}
