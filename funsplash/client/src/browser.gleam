@external(javascript, "./browser_ffi.js", "window_location_origin")
pub fn window_location_origin() -> String

@external(javascript, "./browser_ffi.js", "history_back")
pub fn history_back() -> Nil

@external(javascript, "./browser_ffi.js", "reload_page")
pub fn reload_page() -> Nil

@external(javascript, "./browser_ffi.js", "add_body_class")
pub fn add_body_class(class_name: String) -> Nil

@external(javascript, "./browser_ffi.js", "navigate_to")
pub fn navigate_to(url: String) -> Nil

import lustre/effect.{type Effect}

@external(javascript, "./browser_ffi.js", "submit_form")
pub fn submit_form(id: String) -> Nil

pub fn submit_form_effect(id: String) -> Effect(msg) {
  effect.from(fn(_dispatch) { submit_form(id) })
}

import gleam/dynamic

@external(javascript, "./browser_ffi.js", "get_file_size_from_submit_event")
pub fn get_file_size(event: dynamic.Dynamic) -> Int
