use crate::app::AppState;
use flagdrive_shared::{DownloadRequest, FlagDriveFile};
use leptos::prelude::*;
use wasm_bindgen::JsCast;

#[component]
pub fn DownloadModal(target: RwSignal<Option<FlagDriveFile>>) -> impl IntoView {
    let state = expect_context::<AppState>();
    let decryption_key = RwSignal::new(String::new());

    let download_action = Action::new_local({
        let state = state.clone();
        move |(file, dec_key): &(FlagDriveFile, String)| {
            let file = file.clone();
            let dec_key = dec_key.clone();
            let token = state.auth_token.get_untracked().unwrap_or_default();

            async move {
                let json_payload = serde_json::to_string(&DownloadRequest {
                    token,
                    key: Some(dec_key),
                    backup: None,
                })
                .unwrap();

                let opts = web_sys::RequestInit::new();
                opts.set_method("POST");
                opts.set_body(&wasm_bindgen::JsValue::from_str(&json_payload));

                let headers = web_sys::Headers::new().unwrap();
                headers.append("Content-Type", "application/json").unwrap();
                opts.set_headers(&headers);

                let origin = web_sys::window().unwrap().location().origin().unwrap();
                let request = web_sys::Request::new_with_str_and_init(
                    &format!("{}/api/file/download/{}", origin, file.id),
                    &opts,
                )
                .unwrap();
                let window = web_sys::window().unwrap();

                if let Ok(resp_value) =
                    wasm_bindgen_futures::JsFuture::from(window.fetch_with_request(&request)).await
                {
                    if let Ok(resp) = resp_value.dyn_into::<web_sys::Response>() {
                        if resp.ok() {
                            if let Ok(blob_promise) = resp.blob() {
                                if let Ok(blob_value) =
                                    wasm_bindgen_futures::JsFuture::from(blob_promise).await
                                {
                                    if let Ok(blob) = blob_value.dyn_into::<web_sys::Blob>() {
                                        let url = web_sys::Url::create_object_url_with_blob(&blob)
                                            .unwrap();
                                        let document = window.document().unwrap();
                                        let a = document
                                            .create_element("a")
                                            .unwrap()
                                            .dyn_into::<web_sys::HtmlAnchorElement>()
                                            .unwrap();
                                        a.set_href(&url);
                                        a.set_download(&file.name);
                                        a.click();
                                        web_sys::Url::revoke_object_url(&url).unwrap();
                                        return Ok(());
                                    }
                                }
                            }
                        }
                    }
                }
                Err("Download failed".to_string())
            }
        }
    });

    Effect::new(move |_| {
        if let Some(file) = target.get() {
            download_action.value().set(None);
            decryption_key.set(String::new());
            if !file.is_protected {
                download_action.dispatch((file, String::new()));
            }
        }
    });

    Effect::new(move |_| {
        if let Some(Ok(())) = download_action.value().get() {
            target.set(None);
            decryption_key.set(String::new());
            download_action.value().set(None);
        }
    });

    view! {
        {move || if let Some(file) = target.get() {
            if file.is_protected {
                view! {
                    <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-neutral-900/60 backdrop-blur-sm">
                        <div class="bg-white dark:bg-gov-surface-dark rounded-2xl shadow-2xl w-full max-w-sm border border-neutral-200 dark:border-neutral-700 overflow-hidden flex flex-col">
                            <div class="px-6 py-4 border-b border-neutral-200 dark:border-neutral-700 flex justify-between items-center bg-neutral-50 dark:bg-gov-bg-dark/50">
                                <h3 class="text-lg font-bold text-neutral-900 dark:text-white flex items-center">
                                    <span class="material-icons mr-2 text-gov-red">"lock"</span>
                                    "Encrypted File"
                                </h3>
                                <button
                                    class="text-neutral-400 hover:text-neutral-600 dark:hover:text-neutral-200 transition-colors"
                                    on:click=move |_| target.set(None)
                                >
                                    <span class="material-icons">"close"</span>
                                </button>
                            </div>

                            <div class="p-6 text-center">
                                <p class="text-sm text-neutral-600 dark:text-neutral-400 mb-4">
                                    "The file " <span class="font-bold text-neutral-900 dark:text-white">{file.name.clone()}</span> " is end-to-end encrypted. Enter the decryption key to access it."
                                </p>

                                <input
                                    type="password"
                                    placeholder="Decryption Key"
                                    class="w-full mb-4 px-4 py-3 bg-neutral-50 dark:bg-gov-bg-dark border border-neutral-300 dark:border-neutral-600 rounded-lg focus:outline-none focus:border-gov-red focus:ring-1 focus:ring-gov-red text-neutral-900 dark:text-white transition-all text-center"
                                    on:input=move |ev| decryption_key.set(event_target_value(&ev))
                                />
                                {move || if download_action.pending().get() {
                                    view! { <p class="text-center text-sm text-neutral-500 mt-2 mb-2">"Decrypting & Downloading..."</p> }.into_any()
                                } else if let Some(Err(e)) = download_action.value().get() {
                                    view! { <p class="text-center text-sm text-red-500 mt-2 mb-2 font-bold">{e}</p> }.into_any()
                                } else {
                                    view! { <span/> }.into_any()
                                }}
                            </div>

                            <div class="px-6 py-4 bg-neutral-50 dark:bg-gov-bg-dark/50 border-t border-neutral-200 dark:border-neutral-700 flex justify-end gap-3">
                                <button
                                    class="px-4 py-2 font-bold text-neutral-600 dark:text-neutral-300 hover:bg-neutral-200 dark:hover:bg-neutral-700 rounded-lg transition-colors w-1/2"
                                    on:click=move |_| target.set(None)
                                >
                                    "Cancel"
                                </button>
                                <button
                                    class="px-4 py-2 font-bold text-white bg-gov-red hover:bg-gov-red-dark rounded-lg shadow-sm transition-colors w-1/2 flex items-center justify-center"
                                    class=("opacity-50", move || decryption_key.get().is_empty() || download_action.pending().get())
                                    class=("cursor-not-allowed", move || decryption_key.get().is_empty() || download_action.pending().get())
                                    disabled=move || decryption_key.get().is_empty() || download_action.pending().get()
                                    on:click=move |_| {
                                        download_action.dispatch((file.clone(), decryption_key.get()));
                                    }
                                >
                                    <span class="material-icons mr-2 text-[18px]">"download"</span>
                                    "Unlock"
                                </button>
                            </div>
                        </div>
                    </div>
                }.into_any()
            } else {
                view! { <div class="hidden"></div> }.into_any()
            }
        } else {
            view! { <div class="hidden"></div> }.into_any()
        }}
    }
}
