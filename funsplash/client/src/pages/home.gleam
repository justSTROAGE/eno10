import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element, text}
import lustre/element/html.{div, h1, p}

// MODEL -----------------------------------------------------------------------

pub type Model {
  Model
}

pub fn init() -> #(Model, Effect(Message)) {
  #(Model, effect.none())
}

// UPDATE ----------------------------------------------------------------------

pub type Message

pub fn update(model: Model, _message: Message) -> #(Model, Effect(Message)) {
  #(model, effect.none())
}

// VIEW ------------------------------------------------------------------------

pub fn view(_model: Model) -> Element(Message) {
  div([], [
    // Hero section
    div(
      [
        class(
          "relative flex flex-col items-center justify-center text-center py-24 px-4 bg-gradient-to-br from-gray-900 to-gray-700 text-white",
        ),
      ],
      [
        h1([class("text-4xl md:text-5xl font-bold mb-3")], [text("funsplash")]),
        p([class("text-lg text-gray-300 max-w-md")], [
          text("The internet's source of freely-usable images."),
        ]),
      ],
    ),
    // Placeholder content
    div([class("max-w-5xl mx-auto py-12 px-4")], [
      p([class("text-center text-gray-400 text-sm")], [
        text("Photos will appear here. Upload some to get started!"),
      ]),
    ]),
  ])
}
