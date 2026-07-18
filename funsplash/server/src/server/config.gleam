import envoy
import gleam/int
import gleam/result

pub type Config {
  Config(
    server_secret: String,
    server_host: String,
    server_port: Int,
    data_dir: String,
    db_user: String,
    db_host: String,
    db_password: String,
    db_port: Int,
    db_database: String,
    db_pool_size: Int,
  )
}

pub fn config() -> Config {
  let assert Ok(server_secret) = envoy.get("SERVER_SECRET")
  let assert Ok(server_host) = envoy.get("SERVER_HOST")
  let assert Ok(server_port) =
    result.unwrap(envoy.get("SERVER_PORT"), "a") |> int.parse
  let assert Ok(data_dir) = envoy.get("DATA_DIR")
  let assert Ok(db_user) = envoy.get("PGUSER")
  let assert Ok(db_host) = envoy.get("PGHOST")
  let assert Ok(db_password) = envoy.get("PGPASSWORD")
  let assert Ok(db_port) = result.unwrap(envoy.get("PGPORT"), "a") |> int.parse
  let assert Ok(db_database) = envoy.get("PGDATABASE")
  let assert Ok(db_pool_size) =
    result.unwrap(envoy.get("PGPOOL"), "a") |> int.parse
  Config(
    server_secret:,
    server_host:,
    server_port:,
    data_dir:,
    db_user:,
    db_host:,
    db_password:,
    db_port:,
    db_database:,
    db_pool_size:,
  )
}
