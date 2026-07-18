import gleam/bit_array
import gleam/result
import png/censor
import png/png

@external(erlang, "png", "premium_mask")
pub fn premium_mask(width: Int, height: Int) -> BitArray

// The blurred premium preview is served to non-owners. The original censor
// preserved ancillary PNG chunks (e.g. tEXt) from the header envelope, so a
// flag embedded in a tEXt chunk survived the blur and leaked through
// /images/premium_photo-<asset>. Drop everything after the PNG signature and
// IHDR (the first 33 bytes: 8-byte signature + 25-byte IHDR chunk) so the
// preview contains only the (blurred) image data.
fn sanitize_header(header_envelope: BitArray) -> BitArray {
  case bit_array.byte_size(header_envelope) >= 33 {
    True -> bit_array.slice(header_envelope, 0, 33) |> result.unwrap(header_envelope)
    False -> header_envelope
  }
}

pub fn censor(photo: BitArray) -> BitArray {
  let photo = png.parse(photo)
  let mask = premium_mask(photo.meta.width, photo.meta.height)

  png.Photo(
    ..photo,
    header_envelope: sanitize_header(photo.header_envelope),
    idat: censor.apply_mask(
        photo.idat,
        mask,
        photo.meta.width,
        photo.meta.bit_depth,
        photo.meta.color_type,
      )
      |> png.compress
      |> png.build_idat,
  )
  |> png.pack
}
