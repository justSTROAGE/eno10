import gleam/io
import lustre
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html

pub fn regsiter() -> Result(Nil, lustre.Error) {
  let component = lustre.simple(init, update, view)
  lustre.register(component, "component")
}

pub fn element() -> Element(message) {
  element.element("component", [], [])
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model
}

fn init(_) -> Model {
  Model
}

// UPDATE ----------------------------------------------------------------------

type Message

fn update(model: Model, message: Message) -> Model {
  todo
}

// VIEW ------------------------------------------------------------------------
fn view(model: Model) -> Element(Message) {
  todo
}
