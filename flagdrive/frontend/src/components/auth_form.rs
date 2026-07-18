use leptos::html::Input;
use leptos::prelude::*;

#[component]
pub fn AuthForm<F>(
    title: &'static str,
    subtitle: &'static str,
    button_label: &'static str,
    loading_label: &'static str,
    is_pending: Signal<bool>,
    error_msg: Signal<Option<String>>,
    on_submit: F,
    footer: impl IntoView + 'static,
) -> impl IntoView
where
    F: Fn(String, String) + Send + Sync + 'static,
{
    let username_ref = NodeRef::<Input>::new();
    let password_ref = NodeRef::<Input>::new();

    let on_form_submit = move |ev: leptos::ev::SubmitEvent| {
        ev.prevent_default();
        let username = username_ref.get().unwrap().value();
        let password = password_ref.get().unwrap().value();
        on_submit(username, password);
    };

    view! {
        <div class="flex-1 flex items-center justify-center w-full p-4 bg-gov-bg-light dark:bg-gov-bg-dark">
            <div class="w-full max-w-md bg-white dark:bg-gov-surface-dark border border-neutral-200 dark:border-neutral-700 rounded-2xl p-8 shadow-lg">
                <div class="text-center mb-8 flex flex-col items-center">
                    <h2 class="text-3xl font-bold text-neutral-900 dark:text-white mb-2 tracking-tight">{title}</h2>
                    <p class="text-neutral-500 dark:text-neutral-400">{subtitle}</p>
                </div>

                <form class="space-y-6" on:submit=on_form_submit>
                    <div>
                        <label class="block text-sm font-bold text-neutral-700 dark:text-neutral-300 mb-2">"Username"</label>
                        <input
                            node_ref=username_ref
                            type="text"
                            class="w-full px-4 py-3 bg-neutral-50 dark:bg-gov-bg-dark border border-neutral-300 dark:border-neutral-600 rounded-lg focus:outline-none focus:border-gov-red focus:ring-1 focus:ring-gov-red text-neutral-900 dark:text-white transition-all"
                            placeholder="username"
                            required
                        />
                    </div>

                    <div>
                        <label class="block text-sm font-bold text-neutral-700 dark:text-neutral-300 mb-2">"Password"</label>
                        <input
                            node_ref=password_ref
                            type="password"
                            class="w-full px-4 py-3 bg-neutral-50 dark:bg-gov-bg-dark border border-neutral-300 dark:border-neutral-600 rounded-lg focus:outline-none focus:border-gov-red focus:ring-1 focus:ring-gov-red text-neutral-900 dark:text-white transition-all"
                            placeholder="••••••••"
                            required
                        />
                    </div>

                    {move || match error_msg.get() {
                        Some(msg) => view! {
                            <div class="text-red-500 text-sm font-bold">{msg}</div>
                        }.into_any(),
                        _ => view! { <div class="hidden"></div> }.into_any(),
                    }}

                    <button
                        type="submit"
                        disabled=move || is_pending.get()
                        class="w-full py-3 px-4 bg-gov-red text-white font-bold rounded-lg shadow-sm hover:shadow-md hover:bg-gov-red-dark transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                        {move || if is_pending.get() { loading_label } else { button_label }}
                    </button>
                </form>

                <div class="mt-8 text-center pt-6 border-t border-neutral-100 dark:border-neutral-700">
                    {footer}
                </div>
            </div>
        </div>
    }
}
