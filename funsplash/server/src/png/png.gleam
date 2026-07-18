import gleam/bit_array
import gleam/bytes_tree.{type BytesTree}
import gleam/int

pub type ZStream

pub type CompressedPayload

pub type Compressed

pub type Uncompressed

pub type Bytes =
  Int

pub type Meta {
  Meta(width: Int, height: Int, bit_depth: Int, color_type: Int)
}

pub type Photo(idat_type, compression) {
  Photo(
    meta: Meta,
    header_envelope: BitArray,
    idat: idat_type,
    footer_envelope: BitArray,
  )
}

fn calculate_bpp(color_type: Int, bit_depth: Int) -> Int {
  let channels = case color_type {
    0 -> 1
    2 -> 3
    3 -> 1
    4 -> 2
    6 -> 4
    _ -> 1
  }

  int.max(1, { channels * bit_depth } / 8)
}

pub fn parse(photo: BitArray) -> Photo(BitArray, Uncompressed) {
  let #(
    #(width, height, bit_depth, color_type),
    header_envelope,
    idat,
    footer_envelope,
  ) = parse_png(photo)

  let bpp = calculate_bpp(color_type, bit_depth)

  let defiltered_idat = defilter_image(idat, width, bit_depth, color_type, bpp)

  Photo(
    Meta(width:, height:, bit_depth:, color_type:),
    header_envelope:,
    idat: defiltered_idat,
    footer_envelope:,
  )
}

pub fn size(photo: Photo(BytesTree, Compressed)) -> Bytes {
  bit_array.byte_size(photo.header_envelope)
  + bytes_tree.byte_size(photo.idat)
  + bit_array.byte_size(photo.footer_envelope)
}

pub fn pack(photo: Photo(BytesTree, Compressed)) -> BitArray {
  bytes_tree.from_bit_array(photo.header_envelope)
  |> bytes_tree.append_tree(photo.idat)
  |> bytes_tree.append(photo.footer_envelope)
  |> smuggle_tree
}

@external(erlang, "erlang", "iolist_to_binary")
fn smuggle_tree(tree: BytesTree) -> BitArray

@external(erlang, "png", "build_idat")
pub fn build_idat(compressed_data: CompressedPayload) -> BytesTree

@external(erlang, "png", "parse_png")
fn parse_png(
  raw: BitArray,
) -> #(#(Int, Int, Int, Int), BitArray, BitArray, BitArray)

@external(erlang, "compression", "init_compressor")
pub fn init_compressor() -> ZStream

@external(erlang, "compression", "compress_stream")
pub fn compress_stream(z: ZStream, data: BytesTree) -> CompressedPayload

@external(erlang, "compression", "close_compressor")
pub fn close_compressor(z: ZStream) -> Nil

@external(erlang, "compression", "compress")
pub fn compress(data: BytesTree) -> CompressedPayload

@external(erlang, "png", "defilter_image")
fn defilter_image(
  photo_pixels: BitArray,
  width: Int,
  bit_depth: Int,
  color_type: Int,
  bpp: Int,
) -> BitArray
