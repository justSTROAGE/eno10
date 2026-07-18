import auth.{type Auth}
import components/navbar
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html.{div, footer, main, p, text}

pub fn page_layout(
  auth: Auth,
  navbar_msg: fn(navbar.Message) -> msg,
  content: List(Element(msg)),
) -> Element(msg) {
  div([class("min-h-screen flex flex-col bg-white")], [
    navbar.navbar(auth) |> element.map(navbar_msg),
    main([class("flex-1")], content),
    footer([class("border-t border-gray-200 py-6 text-center")], [
      p([class("text-xs text-gray-400")], [text("funsplash")]),
    ]),
  ])
}
