import gleam/erlang/process
import gleam/http/request
import gleam/option.{None}
import mist
import pog
import server/censor
import server/config.{type Config}
import server/id_server
import server/router
import server/state
import server/web
import server/web/auth
import simplifile
import wisp
import wisp/wisp_mist

fn server(db: pog.Connection, bg_db: pog.Connection, config: Config) -> Nil {
  wisp.configure_logger()

  let _ = simplifile.create_directory_all(config.data_dir <> "/photos")
  let _ = simplifile.create_directory_all(config.data_dir <> "/photos_premium")
  let _ = simplifile.create_directory_all(config.data_dir <> "/tmp")

  let assert Ok(priv_dir) = wisp.priv_directory("server")
  let static_dir = priv_dir <> "/static"
  let id_server_name = id_server.start()

  let state = state.init(config.data_dir, static_dir, db, id_server_name)
  state.start_ttl_sweeper(state, 60_000, 720_000)

  let handle_request = fn(request: wisp.Request) -> wisp.Response {
    let request = request |> wisp.set_max_body_size(1000)
    use user <- auth.get_user_from_session(request, state)
    let context = web.Context(user:, state:)
    router.handle_request(request, context)
  }

  let wisp_app = wisp_mist.handler(handle_request, config.server_secret)

  let mist_handler = fn(request: request.Request(mist.Connection)) {
    let context = web.Context(user: None, state:)
    case request.path_segments(request) {
      ["napi", "censor", photo_id] ->
        censor.upgrade(request, photo_id, context, bg_db)
      _ -> wisp_app(request)
    }
  }

  let assert Ok(_) =
    mist_handler
    |> mist.new
    |> mist.port(config.server_port)
    |> mist.bind(config.server_host)
    |> mist.start

  process.sleep_forever()
}

fn db(config: Config) {
  let db_proc = process.new_name("db")

  let assert Ok(_) =
    db_proc
    |> pog.default_config()
    |> pog.user(config.db_user)
    |> pog.password(option.Some(config.db_password))
    |> pog.host(config.db_host)
    |> pog.port(config.db_port)
    |> pog.database(config.db_database)
    |> pog.pool_size(100)
    |> pog.start

  pog.named_connection(db_proc)
}

fn bg_db(config: Config) {
  let db_proc = process.new_name("db_bg")

  let assert Ok(_) =
    db_proc
    |> pog.default_config()
    |> pog.user(config.db_user)
    |> pog.password(option.Some(config.db_password))
    |> pog.host(config.db_host)
    |> pog.port(config.db_port)
    |> pog.database(config.db_database)
    |> pog.pool_size(80)
    |> pog.start

  pog.named_connection(db_proc)
}

pub fn main() -> Nil {
  let config = config.config()
  let db_proc = db(config)
  let bg_db_proc = bg_db(config)
  server(db_proc, bg_db_proc, config)
}
