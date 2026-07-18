import api/api_photo
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg
import lustre/event
import rsvp
import shared/shared_photo.{type Photo}

@external(javascript, "../browser_ffi.js", "init_censor_ws")
pub fn init_censor_ws(photo_id: String, img_w: Int, img_h: Int) -> Nil

@external(javascript, "../browser_ffi.js", "close_censor_ws")
pub fn close_censor_ws() -> Nil

@external(javascript, "../browser_ffi.js", "draw_and_send_censor_mask")
pub fn draw_and_send_censor_mask(x: Int, y: Int, radius: Int) -> Nil

pub type Model {
  Loading(id: String)
  Loaded(photo: Photo, img_w: Int, img_h: Int, mouse_down: Bool)
  Failed
}

pub fn init(id: String) -> #(Model, Effect(Message)) {
  #(Loading(id), api_photo.fetch(id, ApiReturnedPhoto))
}

pub type Message {
  ApiReturnedPhoto(Result(Photo, rsvp.Error(String)))
  ImageLoaded(w: Int, h: Int)
  UserMovedMouse(x: Int, y: Int)
  UserPressedMouse(down: Bool)
  LeavePage
}

pub fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    ApiReturnedPhoto(Ok(photo)) -> {
      #(Loaded(photo, 0, 0, False), effect.none())
    }
    ApiReturnedPhoto(Error(_)) -> #(Failed, effect.none())
    ImageLoaded(w, h) -> {
      case model {
        Loaded(photo, _, _, _) -> {
          let _ = init_censor_ws(photo.thumbnail.public_id, w, h)
          #(Loaded(photo, w, h, False), effect.none())
        }
        _ -> #(model, effect.none())
      }
    }
    UserMovedMouse(x, y) -> {
      case model {
        Loaded(photo, w, h, True) if w > 0 -> {
          let radius = int.max(w / 100, 1)
          let _ = draw_and_send_censor_mask(x, y, radius)
          #(model, effect.none())
        }
        _ -> #(model, effect.none())
      }
    }
    UserPressedMouse(down) -> {
      case model {
        Loaded(photo, w, h, _) -> {
          #(Loaded(photo, w, h, down), effect.none())
        }
        _ -> #(model, effect.none())
      }
    }
    LeavePage -> {
      let _ = close_censor_ws()
      #(model, effect.none())
    }
  }
}

pub fn view(model: Model) -> Element(Message) {
  html.div([class("max-w-5xl mx-auto py-8 px-4")], [
    html.div([class("flex items-center justify-between mb-4")], [
      html.h1([class("text-2xl font-bold")], [html.text("Censor Photo")]),
      html.a(
        [
          event.on_click(LeavePage),
          attribute.href(case model {
            Loaded(photo, _, _, _) -> "/photos/" <> photo.thumbnail.public_id
            _ -> "/"
          }),
          class(
            "rounded bg-gray-200 px-4 py-2 text-sm font-medium hover:bg-gray-300",
          ),
        ],
        [html.text("Done")],
      ),
    ]),
    html.p([class("text-gray-600 mb-6")], [
      html.text(
        "Drag your mouse over the image to censor parts of it. Changes are collaborative and streamed to the server. (Only PNG supported for now. Don't try other formats)",
      ),
    ]),
    case model {
      Loading(_) -> html.text("Loading photo...")
      Failed -> html.text("Failed to load photo.")
      Loaded(photo, w, h, _) -> {
        let on_mousemove =
          event.on("mousemove", {
            use client_x <- decode.field("offsetX", decode.float)
            use client_y <- decode.field("offsetY", decode.float)
            use client_w <- decode.subfield(
              ["target", "offsetWidth"],
              decode.float,
            )
            use client_h <- decode.subfield(
              ["target", "offsetHeight"],
              decode.float,
            )

            let scaled_x = case client_w >. 0.0 {
              True -> client_x /. client_w *. int.to_float(w)
              False -> 0.0
            }
            let scaled_y = case client_h >. 0.0 {
              True -> client_y /. client_h *. int.to_float(h)
              False -> 0.0
            }

            decode.success(UserMovedMouse(
              float.round(scaled_x),
              float.round(scaled_y),
            ))
          })

        let on_load =
          event.on("load", {
            use nw <- decode.subfield(["target", "naturalWidth"], decode.int)
            use nh <- decode.subfield(["target", "naturalHeight"], decode.int)
            decode.success(ImageLoaded(nw, nh))
          })

        let on_mousedown =
          event.prevent_default(event.on(
            "mousedown",
            decode.success(UserPressedMouse(True)),
          ))
        let on_mouseup =
          event.on("mouseup", decode.success(UserPressedMouse(False)))
        let on_mouseleave =
          event.on("mouseleave", decode.success(UserPressedMouse(False)))

        html.div(
          [
            class(
              "select-none relative block w-full border border-gray-300 rounded shadow overflow-hidden cursor-crosshair",
            ),
          ],
          [
            html.img([
              attribute.src(api_photo.data_url(photo.thumbnail)),
              class("select-none block w-full h-auto"),
              attribute.attribute("draggable", "false"),
              on_load,
              on_mousemove,
              on_mousedown,
              on_mouseup,
              on_mouseleave,
            ]),
            html.canvas([
              attribute.id("censor-canvas"),
              attribute.attribute("width", int.to_string(w)),
              attribute.attribute("height", int.to_string(h)),
              attribute.class(
                "absolute top-0 left-0 w-full h-full pointer-events-none",
              ),
            ]),
          ],
        )
      }
    },
  ])
}
