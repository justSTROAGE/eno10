import lustre/attribute.{class, href}
import lustre/element.{type Element, text}
import lustre/element/html.{a, div, h1, p}

pub fn view() -> Element(msg) {
  div(
    [
      class(
        "flex flex-col items-center justify-center min-h-[60vh] text-center px-4",
      ),
    ],
    [
      h1([class("text-6xl font-bold text-gray-200 mb-4")], [text("404")]),
      p([class("text-gray-500 mb-6")], [text("Page not found.")]),
      a([href("/"), class("text-sm text-black underline hover:no-underline")], [
        text("Go home"),
      ]),
    ],
  )
}
