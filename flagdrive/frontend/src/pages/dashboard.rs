use crate::app::{AppState, Page};
use crate::components::download_modal::DownloadModal;
use crate::components::file_card::FileCard;
use crate::components::navbar::Navbar;
use crate::components::upload_modal::UploadModal;
use flagdrive_shared::{FileListRequest, FlagDriveFile};
use leptos::prelude::*;
use wasm_bindgen::JsCast;

#[component]
pub fn Dashboard() -> impl IntoView {
    let state = expect_context::<AppState>();

    Effect::new(move |_| {
        if state.username.get().is_none() {
            state.page.set(Page::Login);
        }
    });

    let username = move || state.username.get().unwrap_or_default();

    let show_upload_modal = RwSignal::new(false);
    let download_target = RwSignal::new(None::<FlagDriveFile>);

    let files_resource = LocalResource::new(move || {
        let user = username();
        let token = state.auth_token.get_untracked();
        async move {
            if user.is_empty() {
                return None;
            }
            let origin = web_sys::window().unwrap().location().origin().unwrap();
            let opts = web_sys::RequestInit::new();

            if let Some(t) = token {
                opts.set_method("POST");
                let json_payload = serde_json::to_string(&FileListRequest { token: t }).unwrap();
                opts.set_body(&wasm_bindgen::JsValue::from_str(&json_payload));
                let headers = web_sys::Headers::new().unwrap();
                headers.append("Content-Type", "application/json").unwrap();
                opts.set_headers(&headers);
            } else {
                opts.set_method("GET");
            }

            let request = web_sys::Request::new_with_str_and_init(
                &format!("{}/api/files/{}", origin, user),
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
            leptos::serde_json::from_str::<Vec<FlagDriveFile>>(&text_str).ok()
        }
    });

    let trigger_download = move |file: FlagDriveFile| {
        download_target.set(Some(file));
    };

    let on_upload_success = move || {
        files_resource.refetch();
    };

    view! {
        <div class="flex flex-col min-h-screen">
            <Navbar />

            <main class="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-8 relative">
                <div class="flex justify-between items-center mb-8">
                    <div>
                        <h1 class="text-3xl font-bold text-neutral-900 dark:text-white tracking-tight flex items-center">
                            <span class="material-icons mr-2 text-gov-red text-3xl">"folder"</span>
                            "Documents"
                        </h1>
                        <p class="text-neutral-600 dark:text-neutral-400 mt-1">"Access, manage, and securely upload your documents."</p>
                    </div>

                    <button
                        class="flex items-center space-x-2 px-5 py-2.5 bg-gov-red text-white font-bold rounded-lg hover:bg-gov-red-dark shadow-sm hover:shadow-md transition-all"
                        on:click=move |_| show_upload_modal.set(true)
                    >
                        <span class="material-icons">"upload_file"</span>
                        <span>"Upload File"</span>
                    </button>
                </div>

                <Suspense fallback=move || view! { <div class="text-center p-8">"Loading..."</div> }>
                    {move || match files_resource.get() {
                        None => view! { <div></div> }.into_any(),
                        Some(None) => view! { <div class="text-center p-8 text-red-500">"Failed to load files"</div> }.into_any(),
                        Some(Some(files)) => view! {
                            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                                {files.into_iter().map(move |f| {
                                    view! { <FileCard file=f on_download=trigger_download /> }
                                }).collect_view()}
                            </div>
                        }.into_any()
                    }}
                </Suspense>
            </main>

            <UploadModal show=show_upload_modal on_success=on_upload_success />
            <DownloadModal target=download_target />
        </div>
    }
}
