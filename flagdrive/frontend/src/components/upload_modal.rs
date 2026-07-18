use crate::app::AppState;
use flagdrive_shared::FlagDriveFileVisibility;
use leptos::prelude::*;
use wasm_bindgen::JsCast;

#[component]
pub fn UploadModal<F>(show: RwSignal<bool>, on_success: F) -> impl IntoView
where
    F: Fn() + 'static,
{
    let state = expect_context::<AppState>();

    let is_dragging = RwSignal::new(false);
    let visibility = RwSignal::new(FlagDriveFileVisibility::Private);
    let encryption_key = RwSignal::new(String::new());
    let selected_file = RwSignal::new(None::<web_sys::File>);
    let file_input_ref = NodeRef::<leptos::html::Input>::new();

    let on_drag_enter = move |ev: leptos::ev::DragEvent| {
        ev.prevent_default();
        is_dragging.set(true);
    };

    let on_drag_leave = move |ev: leptos::ev::DragEvent| {
        ev.prevent_default();
        is_dragging.set(false);
    };

    let on_drag_over = move |ev: leptos::ev::DragEvent| {
        ev.prevent_default();
        is_dragging.set(true);
    };

    let on_drop = move |ev: leptos::ev::DragEvent| {
        ev.prevent_default();
        is_dragging.set(false);
        if let Some(dt) = ev.data_transfer() {
            if let Some(files) = dt.files() {
                if let Some(file) = files.get(0) {
                    selected_file.set(Some(file));
                }
            }
        }
    };

    let on_file_change = move |ev: leptos::ev::Event| {
        if let Some(target) = ev
            .target()
            .and_then(|t| t.dyn_into::<web_sys::HtmlInputElement>().ok())
        {
            if let Some(files) = target.files() {
                if let Some(file) = files.get(0) {
                    selected_file.set(Some(file));
                }
            }
        }
    };

    let trigger_file_select = move |_| {
        if let Some(input) = file_input_ref.get() {
            input.click();
        }
    };

    let upload_action = Action::new_local({
        let state = state.clone();
        move |(file, enc_key, vis): &(web_sys::File, String, FlagDriveFileVisibility)| {
            let file = file.clone();
            let enc_key = enc_key.clone();
            let vis = vis.clone();
            let token = state.auth_token.get_untracked().unwrap_or_default();

            async move {
                let form_data = web_sys::FormData::new().unwrap();
                form_data
                    .append_with_blob_and_filename("file", &file, &file.name())
                    .unwrap();

                let json_payload = serde_json::to_string(&flagdrive_shared::UploadMetadata {
                    token,
                    key: if enc_key.is_empty() {
                        None
                    } else {
                        Some(enc_key)
                    },
                    visibility: vis,
                    backup: None,
                })
                .unwrap();

                form_data.append_with_str("json", &json_payload).unwrap();

                let opts = web_sys::RequestInit::new();
                opts.set_method("POST");
                opts.set_body(&form_data.into());

                let origin = web_sys::window().unwrap().location().origin().unwrap();
                let request = web_sys::Request::new_with_str_and_init(
                    &format!("{}/api/file/upload", origin),
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
                Err("Upload failed".to_string())
            }
        }
    });

    Effect::new(move |_| {
        if let Some(Ok(())) = upload_action.value().get() {
            show.set(false);
            selected_file.set(None);
            encryption_key.set(String::new());
            upload_action.value().set(None);
            on_success();
        }
    });

    view! {
        {move || if show.get() {
            view! {
                <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-neutral-900/60 backdrop-blur-sm">
                    <div class="bg-white dark:bg-gov-surface-dark rounded-2xl shadow-2xl w-full max-w-lg border border-neutral-200 dark:border-neutral-700 overflow-hidden flex flex-col">
                        <div class="px-6 py-4 border-b border-neutral-200 dark:border-neutral-700 flex justify-between items-center bg-neutral-50 dark:bg-gov-bg-dark/50">
                            <h3 class="text-lg font-bold text-neutral-900 dark:text-white flex items-center">
                                <span class="material-icons mr-2 text-gov-red">"upload"</span>
                                "Secure Upload"
                            </h3>
                            <button
                                class="text-neutral-400 hover:text-neutral-600 dark:hover:text-neutral-200 transition-colors"
                                on:click=move |_| show.set(false)
                            >
                                <span class="material-icons">"close"</span>
                            </button>
                        </div>

                        <div class="p-6">
                            <label class="block text-sm font-bold text-neutral-700 dark:text-neutral-300 mb-2">"Visibility Clearance"</label>
                            <select
                                class="w-full mb-4 px-4 py-3 bg-neutral-50 dark:bg-gov-bg-dark border border-neutral-300 dark:border-neutral-600 rounded-lg focus:outline-none focus:border-gov-red focus:ring-1 focus:ring-gov-red text-neutral-900 dark:text-white transition-all appearance-none"
                                on:change=move |ev| {
                                    let val = event_target_value(&ev);
                                    let vis = match val.as_str() {
                                        "Public" => FlagDriveFileVisibility::Public,
                                        "Following" => FlagDriveFileVisibility::Following,
                                        "Followers" => FlagDriveFileVisibility::Followers,
                                        _ => FlagDriveFileVisibility::Private,
                                    };
                                    visibility.set(vis);
                                }
                            >
                                <option value="Private" selected=true>"Private (Only Me)"</option>
                                <option value="Following">"Following (Only people I follow)"</option>
                                <option value="Followers">"Followers (Only my followers)"</option>
                                <option value="Public">"Public (Everyone)"</option>
                            </select>

                            <label class="block text-sm font-bold text-neutral-700 dark:text-neutral-300 mb-2">"Protection Password (Optional)"</label>
                            <input
                                type="password"
                                placeholder="Leave blank for unprotected"
                                class="w-full mb-6 px-4 py-3 bg-neutral-50 dark:bg-gov-bg-dark border border-neutral-300 dark:border-neutral-600 rounded-lg focus:outline-none focus:border-gov-red focus:ring-1 focus:ring-gov-red text-neutral-900 dark:text-white transition-all"
                                on:input=move |ev| encryption_key.set(event_target_value(&ev))
                            />

                            <input
                                type="file"
                                class="hidden"
                                node_ref=file_input_ref
                                on:change=on_file_change
                            />

                            <div
                                class="relative h-40 rounded-xl border-2 border-dashed border-neutral-300 dark:border-neutral-600 flex flex-col items-center justify-center transition-all cursor-pointer hover:bg-neutral-50 dark:hover:bg-neutral-900/30"
                                class=("border-gov-red", move || is_dragging.get())
                                class=("bg-red-50", move || is_dragging.get())
                                class=("dark:bg-red-900/10", move || is_dragging.get())
                                on:dragenter=on_drag_enter
                                on:dragleave=on_drag_leave
                                on:dragover=on_drag_over
                                on:drop=on_drop
                                on:click=trigger_file_select
                            >
                                {move || if let Some(file) = selected_file.get() {
                                    view! {
                                        <span class="material-icons text-4xl text-green-500 mb-2">"check_circle"</span>
                                        <p class="text-neutral-900 dark:text-white font-bold px-4 truncate max-w-xs">{file.name()}</p>
                                        <p class="text-xs text-neutral-500 mt-1">"Click or drag to change file"</p>
                                    }.into_any()
                                } else {
                                    view! {
                                        <span class="material-icons text-4xl text-neutral-400 mb-2" class=("text-gov-red", move || is_dragging.get()) class=("animate-bounce", move || is_dragging.get())>"cloud_upload"</span>
                                        <p class="text-neutral-600 dark:text-neutral-400 font-medium text-center px-4">
                                            "Drag and drop file here, or click to browse"
                                        </p>
                                    }.into_any()
                                }}
                            </div>
                            {move || if upload_action.pending().get() {
                                view! { <p class="text-center text-sm text-neutral-500 mt-4">"Uploading..."</p> }.into_any()
                            } else if let Some(Err(e)) = upload_action.value().get() {
                                view! { <p class="text-center text-sm text-red-500 mt-4 font-bold">{e}</p> }.into_any()
                            } else {
                                view! { <span/> }.into_any()
                            }}
                        </div>

                        <div class="px-6 py-4 bg-neutral-50 dark:bg-gov-bg-dark/50 border-t border-neutral-200 dark:border-neutral-700 flex justify-end gap-3">
                            <button
                                class="px-4 py-2 font-bold text-neutral-600 dark:text-neutral-300 hover:bg-neutral-200 dark:hover:bg-neutral-700 rounded-lg transition-colors"
                                on:click=move |_| show.set(false)
                            >
                                "Cancel"
                            </button>
                            <button
                                class="px-4 py-2 font-bold text-white bg-gov-red rounded-lg shadow-sm transition-colors"
                                class=("opacity-50", move || selected_file.get().is_none() || upload_action.pending().get())
                                class=("cursor-not-allowed", move || selected_file.get().is_none() || upload_action.pending().get())
                                class=("hover:bg-gov-red-dark", move || selected_file.get().is_some() && !upload_action.pending().get())
                                disabled=move || selected_file.get().is_none() || upload_action.pending().get()
                                on:click=move |_| {
                                    if let Some(f) = selected_file.get() {
                                        upload_action.dispatch((f, encryption_key.get(), visibility.get()));
                                    }
                                }
                            >
                                "Upload"
                            </button>
                        </div>
                    </div>
                </div>
            }.into_any()
        } else {
            view! { <div class="hidden"></div> }.into_any()
        }}
    }
}
