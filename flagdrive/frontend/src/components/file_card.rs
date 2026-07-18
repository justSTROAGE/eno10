use flagdrive_shared::{FlagDriveFile, FlagDriveFileVisibility};
use leptos::prelude::*;

#[component]
pub fn FileCard<F>(file: FlagDriveFile, on_download: F) -> impl IntoView
where
    F: Fn(FlagDriveFile) + 'static + Send + Sync + Clone,
{
    let visibility_class = match file.visibility {
        FlagDriveFileVisibility::Private => {
            "text-purple-700 dark:text-purple-400 bg-purple-100 dark:bg-purple-900/30 border-purple-200 dark:border-purple-800/50"
        }
        FlagDriveFileVisibility::Public => {
            "text-green-700 dark:text-green-400 bg-green-100 dark:bg-green-900/30 border-green-200 dark:border-green-800/50"
        }
        FlagDriveFileVisibility::Following => {
            "text-amber-700 dark:text-amber-400 bg-amber-100 dark:bg-amber-900/30 border-amber-200 dark:border-amber-800/50"
        }
        FlagDriveFileVisibility::Followers => {
            "text-sky-700 dark:text-sky-400 bg-sky-100 dark:bg-sky-900/30 border-sky-200 dark:border-sky-800/50"
        }
    };

    let visibility_label = match file.visibility {
        FlagDriveFileVisibility::Private => "Private",
        FlagDriveFileVisibility::Public => "Public",
        FlagDriveFileVisibility::Following => "Following",
        FlagDriveFileVisibility::Followers => "Followers",
    };

    let icon = match file.visibility {
        FlagDriveFileVisibility::Private => "visibility_off",
        FlagDriveFileVisibility::Public => "public",
        FlagDriveFileVisibility::Following => "person_add",
        FlagDriveFileVisibility::Followers => "groups",
    };

    let f_clone = file.clone();

    view! {
        <div class="group bg-white dark:bg-gov-surface-dark rounded-xl border border-neutral-200 dark:border-neutral-700 p-5 hover:border-gov-red dark:hover:border-gov-red transition-all duration-300 hover:shadow-md relative">
            <div class="flex justify-between items-start mb-4 mt-2">
                <div class="flex-1 min-w-0 pr-4">
                    <h3 class="text-lg font-bold text-neutral-900 dark:text-white truncate group-hover:text-gov-red transition-colors flex items-center">
                        <span class="material-icons mr-2 text-neutral-400 group-hover:text-gov-red" title=if file.is_protected { "Protected" } else { "" }>
                            {if file.is_protected { "lock" } else { "description" }}
                        </span>
                        {file.name.clone()}
                    </h3>
                    <p class="text-sm text-neutral-500 dark:text-neutral-400 mt-2">"Owner: " <span class="font-medium text-neutral-700 dark:text-neutral-300">{file.owner.clone()}</span></p>
                </div>
                <span class=format!("flex items-center px-2.5 py-1 text-xs font-semibold rounded-full border {}", visibility_class)>
                    <span class="material-icons text-[14px] mr-1">{icon}</span>
                    {visibility_label}
                </span>
            </div>

            <div class="flex justify-between items-end mt-6 border-t border-neutral-100 dark:border-neutral-700 pt-4">
                <div class="flex flex-col">
                    <span class="text-xs font-medium text-neutral-500 dark:text-neutral-400">{format!("{} bytes", file.size)}</span>
                    <span class="text-xs font-medium text-neutral-400 dark:text-neutral-500 mt-1">
                        {chrono::DateTime::from_timestamp(file.created_at as i64, 0)
                            .map(|dt| dt.format("%d.%m.%Y %H:%M:%S").to_string())
                            .unwrap_or_default()}
                    </span>
                </div>
                <button
                    class="p-2 text-sm font-bold text-white bg-gov-red rounded hover:bg-gov-red-dark transition-colors shadow-sm flex items-center justify-center"
                    on:click=move |_| on_download(f_clone.clone())
                >
                    <span class="material-icons text-[20px]">"download"</span>
                </button>
            </div>
        </div>
    }
}
