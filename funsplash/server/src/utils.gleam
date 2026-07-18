import bravo/uset.{type USet}
import gleam/erlang/process
import gleam/list
import gleam/result
import pog
import server/id_server
import server/state

pub fn defer(defer: fn() -> a, first: fn() -> b) -> b {
  let res = first()
  defer()
  res
}

pub fn generate_id(state: state.State) -> String {
  process.named_subject(state.id_server)
  |> process.call(1000, id_server.GenerateId)
}

pub fn extend_cache_l2(cache: USet(k, List(v)), key: k, value: v) -> Nil {
  case uset.lookup(cache, key) {
    Ok(values) -> {
      let _ = uset.insert(cache, key, [value, ..values])
      Nil
    }
    Error(_) -> Nil
  }
}

pub fn remove_cache_l2(cache: USet(k, List(v)), key: k, value: v) -> Nil {
  case uset.lookup(cache, key) {
    Ok(values) -> {
      let _ = uset.insert(cache, key, list.filter(values, fn(v) { v != value }))
      Nil
    }
    Error(_) -> Nil
  }
}

pub fn update_cache_l0(
  sql: Result(pog.Returned(d), pe),
  cache: USet(l0k, b),
  l0_key_extract: fn(b) -> l0k,
  mapper: fn(d) -> b,
  err: e,
) -> Result(b, e) {
  use row <- db_limit_try(sql |> result.replace_error(err), err)
  let value = row |> mapper
  let key = value |> l0_key_extract
  let _ = uset.insert(cache, key, value)
  Ok(value)
}

pub fn get_cache_l0(
  cache: USet(a, b),
  key: a,
  sql: fn(a) -> Result(pog.Returned(d), pe),
  mapper: fn(d) -> b,
  err: e,
) -> Result(b, e) {
  case uset.lookup(cache, key) {
    Ok(val) -> Ok(val)
    Error(_) -> {
      use row <- db_limit_try(sql(key) |> result.replace_error(err), err)
      let value = row |> mapper
      let _ = uset.insert(cache, key, value)
      Ok(value)
    }
  }
}

pub fn get_cache_l1(
  l1: USet(k, l0k),
  l0: USet(l0k, c),
  key: k,
  sql: fn(k) -> Result(pog.Returned(d), pe),
  l0_key_extract: fn(c) -> l0k,
  mapper: fn(d) -> c,
  err: e,
) -> Result(c, e) {
  let fetch_from_db = fn() {
    use row <- db_limit_try(sql(key) |> result.replace_error(err), err)
    let val = row |> mapper
    let l0_key = val |> l0_key_extract
    let _ = uset.insert(l0, l0_key, val)
    let _ = uset.insert(l1, key, l0_key)
    Ok(val)
  }

  case uset.lookup(l1, key) {
    Ok(val) -> {
      case uset.lookup(l0, val) {
        Ok(val) -> Ok(val)
        Error(_) -> {
          fetch_from_db()
        }
      }
    }
    Error(_) -> {
      fetch_from_db()
    }
  }
}

pub fn get_cache_l2(
  l2: USet(k, List(l0k)),
  l0: USet(l0k, c),
  key: k,
  sql: fn(k) -> Result(pog.Returned(d), pe),
  l0_key_extract: fn(c) -> l0k,
  mapper: fn(d) -> c,
  err: e,
) -> Result(List(c), e) {
  let fetch_from_db = fn() {
    use rows <- result.try(sql(key) |> result.replace_error(err))
    let #(vals, l0_keys) =
      rows.rows
      |> list.map(fn(row) {
        let val = row |> mapper
        let l0k = val |> l0_key_extract
        let _ = uset.insert(l0, l0k, val)
        #(val, l0k)
      })
      |> list.unzip
    let _ = uset.insert(l2, key, l0_keys)
    Ok(vals)
  }

  case uset.lookup(l2, key) {
    Ok(l0_keys) -> {
      case l0_keys |> list.try_map(fn(l0k) { uset.lookup(l0, l0k) }) {
        Ok(vals) -> Ok(vals)
        Error(_) -> fetch_from_db()
      }
    }
    Error(_) -> {
      fetch_from_db()
    }
  }
}

pub fn db_limit(
  res: Result(pog.Returned(a), pog.QueryError),
) -> Result(a, pog.QueryError) {
  case res {
    Ok(ok) -> {
      case
        ok.rows
        |> list.first
        |> result.replace_error(pog.PostgresqlError(
          "P0002",
          "no_data_found",
          "no_data_found",
        ))
      {
        Ok(row) -> Ok(row)
        Error(err) -> Error(err)
      }
    }
    Error(err) -> Error(err)
  }
}

pub fn db_limit_try(
  res: Result(pog.Returned(a), pe),
  err: e,
  next: fn(a) -> Result(b, e),
) -> Result(b, e) {
  case res {
    Ok(ok) ->
      case ok.rows |> list.first |> result.replace_error(err) {
        Ok(ok) -> next(ok)
        Error(e) -> Error(e)
      }
    Error(_) -> Error(err)
  }
}

pub fn result_guard(
  when requirement: Result(a, b),
  return consequence: c,
  otherwise alternative: fn(a) -> c,
) -> c {
  case requirement {
    Error(_) -> consequence
    Ok(ok) -> alternative(ok)
  }
}
