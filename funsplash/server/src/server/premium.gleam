import png/censor
import png/png

@external(erlang, "png", "premium_mask")
pub fn premium_mask(width: Int, height: Int) -> BitArray

pub fn censor(photo: BitArray) -> BitArray {
  let photo = png.parse(photo)
  let mask = premium_mask(photo.meta.width, photo.meta.height)

  png.Photo(
    ..photo,
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
