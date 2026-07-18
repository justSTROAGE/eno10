use crate::components::navbar::Navbar;
use leptos::prelude::*;

#[component]
pub fn Landing() -> impl IntoView {
    view! {
        <div class="flex flex-col min-h-screen">
            <Navbar />

            <div class="flex-1 flex flex-col items-center justify-center relative px-4 py-16 sm:px-6 lg:px-8">

                <div class="relative z-10 text-center max-w-4xl mx-auto">
                    <h1 class="text-4xl md:text-6xl font-extrabold tracking-tight mb-6 text-neutral-900 dark:text-white">
                        "Secure File Sharing for " <br class="hidden md:block"/>
                        <span class="text-gov-red">"Government and Citizens"</span>
                    </h1>

                    <p class="text-lg md:text-xl text-neutral-600 dark:text-neutral-400 mb-10 max-w-2xl mx-auto leading-relaxed">
                        "Welcome to FlagDrive, the official federal cloud platform. Store, share, and collaborate on documents securely across all public sector departments and with citizens."
                    </p>
                </div>

                <div class="mt-24 grid grid-cols-1 md:grid-cols-3 gap-8 max-w-5xl mx-auto w-full px-4">
                    <div class="bg-white dark:bg-gov-surface-dark p-6 rounded-xl shadow-sm border border-neutral-200 dark:border-neutral-700">
                        <div class="flex items-center mb-4">
                            <span class="material-icons text-gov-red mr-3 text-3xl">"security"</span>
                            <h3 class="text-xl font-bold text-neutral-900 dark:text-white">"Data Encryption"</h3>
                        </div>
                        <p class="text-neutral-600 dark:text-neutral-400">"All files are securely encrypted on the server, complying with strict federal data protection regulations."</p>
                    </div>
                    <div class="bg-white dark:bg-gov-surface-dark p-6 rounded-xl shadow-sm border border-neutral-200 dark:border-neutral-700">
                        <div class="flex items-center mb-4">
                            <span class="material-icons text-gov-red mr-3 text-3xl">"folder_shared"</span>
                            <h3 class="text-xl font-bold text-neutral-900 dark:text-white">"Seamless Sharing"</h3>
                        </div>
                        <p class="text-neutral-600 dark:text-neutral-400">"Share documents securely with specific departments, public citizens, or restrict access completely."</p>
                    </div>
                    <div class="bg-white dark:bg-gov-surface-dark p-6 rounded-xl shadow-sm border border-neutral-200 dark:border-neutral-700">
                        <div class="flex items-center mb-4">
                            <span class="material-icons text-gov-red mr-3 text-3xl">"devices"</span>
                            <h3 class="text-xl font-bold text-neutral-900 dark:text-white">"Cross-Platform"</h3>
                        </div>
                        <p class="text-neutral-600 dark:text-neutral-400">"Access your documents from any authorized device, anywhere in the union."</p>
                    </div>
                </div>
            </div>
        </div>
    }
}
