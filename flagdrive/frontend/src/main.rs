use leptos::prelude::*;

pub mod app;
pub mod components;
pub mod pages;

use app::App;

fn main() {
    mount_to_body(|| {
        view! {
            <App />
        }
    })
}
