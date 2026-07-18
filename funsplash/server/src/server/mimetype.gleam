import file_streams/file_stream
import gleam/result
import mimetype
import server/sql
import shared/shared_upload

pub fn detect(path: String) -> Result(shared_upload.MimeType, Nil) {
  use stream <- result.try(
    file_stream.open_read(path) |> result.replace_error(Nil),
  )
  use top <- result.try(
    file_stream.read_bytes(stream, 32) |> result.replace_error(Nil),
  )
  mimetype.detect(top)
  |> to_shared
  |> Ok()
}

// mappers

pub fn sql_to_shared(mimetype: sql.Mimetype) -> shared_upload.MimeType {
  case mimetype {
    sql.Other -> shared_upload.Other
    sql.Webp -> shared_upload.Webp
    sql.Jpg -> shared_upload.Jpg
    sql.Png -> shared_upload.Png
  }
}

pub fn shared_to_sql(mimetype: shared_upload.MimeType) -> sql.Mimetype {
  case mimetype {
    shared_upload.Png -> sql.Png
    shared_upload.Jpg -> sql.Jpg
    shared_upload.Webp -> sql.Webp
    shared_upload.Other -> sql.Other
  }
}

fn to_shared(mimetype: mimetype.MimeType) -> shared_upload.MimeType {
  case mimetype.to_string(mimetype) {
    "image/png" -> shared_upload.Png
    "image/jpeg" -> shared_upload.Jpg
    "image/webp" -> shared_upload.Webp
    _ -> shared_upload.Other
  }
}
