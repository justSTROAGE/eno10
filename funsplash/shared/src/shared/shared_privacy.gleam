import gleam/dynamic/decode
import gleam/json

pub type Privacy {
  Private
  Premium
  Public
}

pub fn to_list() -> List(Privacy) {
  [Private, Premium, Public]
}

pub fn from_string(privacy: String) -> Privacy {
  case privacy {
    "premium" -> Premium
    "private" -> Private
    "public" | _ -> Public
  }
}

pub fn to_string(privacy: Privacy) -> String {
  case privacy {
    Public -> "public"
    Premium -> "premium"
    Private -> "private"
  }
}

pub fn privacy_decoder() -> decode.Decoder(Privacy) {
  use variant <- decode.then(decode.string)
  case variant {
    "private" -> decode.success(Private)
    "premium" -> decode.success(Premium)
    "public" -> decode.success(Public)
    _ -> decode.failure(Private, "privacy")
  }
}

pub fn privacy_to_json(privacy: Privacy) -> json.Json {
  case privacy {
    Private -> json.string("private")
    Premium -> json.string("premium")
    Public -> json.string("public")
  }
}
