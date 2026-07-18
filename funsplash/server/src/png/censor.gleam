import gleam/bytes_tree.{type BytesTree}
import png/png.{type Compressed, type Uncompressed}

@external(erlang, "censor", "apply_mask")
pub fn apply_mask(
  target: BitArray,
  mask: BitArray,
  width: Int,
  bit_depth: Int,
  color_type: Int,
) -> BytesTree

pub fn censor_raw(
  photo: png.Photo(BitArray, Uncompressed),
  mask: BitArray,
  zstream: png.ZStream,
) -> Result(png.Photo(BytesTree, Compressed), String) {
  // TODO: do size check etc. instead of just crashing
  let censored =
    apply_mask(
      photo.idat,
      mask,
      photo.meta.width,
      photo.meta.bit_depth,
      photo.meta.color_type,
    )
    |> png.compress_stream(zstream, _)
    |> png.build_idat

  Ok(png.Photo(..photo, idat: censored))
}
