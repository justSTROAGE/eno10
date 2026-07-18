use sqlite;
use path;
use strings;
use fmt;
use regex;
use os;
use io;
use fs;
use crypto::random;
use encoding::hex;
use uuid;


export type object = struct {
	owner: str,
	name: str,
	uuid: str,
};

export fn get_owner_objname(full_name: str) (str, str) = {
	const full_objname_re = regex::compile("^[A-Za-z0-9_-]{1,32}/[A-Za-z0-9_.-/]{1,64}$")!;
	defer regex::finish(&full_objname_re);
	assert(regex::test(&full_objname_re, full_name)!, full_name);
	const tokens = strings::split(full_name, "/")!;
	defer free(tokens);
	const username = tokens[0];
	const objname = strings::join("/", tokens[1..]...)!;
	defer free(objname);
	return (strings::dup(username)!, strings::dup(objname)!);
};

fn get_object_permission_uncached(owner: str, obj: str, requester: str, permission: str) bool = {
	const data_dir = get_data_dir();
	const pathbuf = path::init(data_dir, "meta.db")!;
	const handle = match(sqlite::open(&pathbuf)) {
	case let h: sqlite::handle =>
		yield h;
	case let err: sqlite::error =>
		fmt::fatalf("open failed: {}", sqlite::strerror(err));
	};
	defer sqlite::close(handle)!;
	sqlite::exec(handle, "PRAGMA busy_timeout = 3000")!;

	const stmt = match(sqlite::prepare(handle,
		"
		WITH matched AS (
			SELECT effect, length(prefix) AS plen
			FROM shares
			WHERE (receiver = :requester OR receiver = '*public')
			AND owner = :owner
			AND permission = :permission
			AND scope = 'exact'
			AND prefix = :objectname

			UNION ALL

			SELECT effect, length(prefix) AS plen
			FROM shares
			WHERE (receiver = :requester OR receiver = '*public')
			AND owner = :owner
			AND permission = :permission
			AND scope = 'prefix'
			AND :objectname GLOB prefix || '*'
		) SELECT effect FROM matched ORDER BY plen DESC,
			CASE effect WHEN 'deny' THEN 0 ELSE 1 END
		LIMIT 1;
		",
		)) {
	case let s: sqlite::statement =>
		yield s;
	case let err: sqlite::error =>
		fmt::fatalf("prepare failed: {}", sqlite::strerror(err));
	};
	defer sqlite::finalize(stmt)!;
	sqlite::bind_str(stmt, 1, requester)!;
	sqlite::bind_str(stmt, 2, owner)!;
	sqlite::bind_str(stmt, 3, permission)!;
	sqlite::bind_str(stmt, 4, obj)!;
	match (sqlite::step(stmt)) {
	case void =>
		return sqlite::column_str(stmt, 0) == "allow";
	case done =>
		return false;
	case let err: sqlite::error =>
		fmt::fatalf("step failed: {}", sqlite::strerror(err));
	};
};

fn get_object_metadata_uncached(owner: str, obj: str) object = {
	const data_dir = get_data_dir();
	const pathbuf = path::init(data_dir, "meta.db")!;
	const handle = match(sqlite::open(&pathbuf)) {
	case let h: sqlite::handle =>
		yield h;
	case let err: sqlite::error =>
		fmt::fatalf("open failed: {}", sqlite::strerror(err));
	};
	defer sqlite::close(handle)!;
	sqlite::exec(handle, "PRAGMA busy_timeout = 3000")!;
	const stmt = match(sqlite::prepare(handle,
		"SELECT uuid FROM objects WHERE username = ? AND name = ?")) {
	case let s: sqlite::statement =>
		yield s;
	case let err: sqlite::error =>
		fmt::fatalf("prepare failed: {}", sqlite::strerror(err));
	};
	defer sqlite::finalize(stmt)!;
	sqlite::bind_str(stmt, 1, owner)!;
	sqlite::bind_str(stmt, 2, obj)!;
	match (sqlite::step(stmt)) {
	case void =>
		return object {
			owner = strings::dup(owner)!,
			name = strings::dup(obj)!,
			uuid = strings::dup(sqlite::column_str(stmt, 0))!,
		};
	case done =>
		fmt::fatalf("no result found for {}", obj);
	case let err: sqlite::error =>
		fmt::fatalf("step failed: {}", sqlite::strerror(err));
	};
};

type meta_entry = struct {
	owner: str,
	obj: str,
	result: object,
};

type perm_entry = struct {
	owner: str,
	obj: str,
	requester: str,
	permission: str,
	result: bool,
};

type cache = struct {
	meta: []meta_entry,
	perm: []perm_entry,
};

fn get_cache() *cache = {
	static let c: cache = cache {
		meta = [],
		perm = [],
	};
	return &c;
};

export fn get_object_metadata(owner: str, obj: str) object = {
	const c = get_cache();
	for (let i = 0z; i < len(c.meta); i += 1) {
		if (c.meta[i].owner == owner && c.meta[i].obj == obj) {
			return c.meta[i].result;
		};
	};
	const result = get_object_metadata_uncached(owner, obj);
	append(c.meta, meta_entry {
		owner = strings::dup(owner)!,
		obj = strings::dup(obj)!,
		result = result,
	})!;
	return result;
};

export fn get_object_permission(owner: str, obj: str, requester: str, permission: str) bool = {
	const c = get_cache();
	for (let i = 0z; i < len(c.perm); i += 1) {
		if (c.perm[i].owner == owner && c.perm[i].obj == obj
				&& c.perm[i].requester == requester
				&& c.perm[i].permission == permission) {
			return c.perm[i].result;
		};
	};
	const result = get_object_permission_uncached(owner, obj, requester, permission);
	append(c.perm, perm_entry {
		owner = strings::dup(owner)!,
		obj = strings::dup(obj)!,
		requester = strings::dup(requester)!,
		permission = strings::dup(permission)!,
		result = result,
	})!;
	return result;
};

export fn get_data_dir() str = {
	match (os::getenv("DATA_DIR")) {
	case let s: str =>
		return s;
	case void =>
		return "/data";
	};
};

fn meta_handle() sqlite::handle = {
	const pathbuf = path::init(get_data_dir(), "meta.db")!;
	const handle = match (sqlite::open(&pathbuf)) {
	case let h: sqlite::handle =>
		yield h;
	case let err: sqlite::error =>
		fmt::fatalf("open failed: {}", sqlite::strerror(err));
	};
	sqlite::exec(handle, "PRAGMA busy_timeout = 3000")!;
	return handle;
};

export fn put_object_data(owner: str, objname: str, data: []u8) void = {
	const data_dir = get_data_dir();
	const new_uuid = hex::encodestr(uuid::generate())!;

	const newpathbuf = path::init(data_dir, "objects", new_uuid)!;
	const new_path = path::string(&newpathbuf);
	const newf = os::create(new_path, 0o644, fs::flag::WRONLY | fs::flag::EXCL)!;
	io::writeall(newf, data)!;
	io::close(newf)!;

	const handle = meta_handle();
	defer sqlite::close(handle)!;

	const ins = match (sqlite::prepare(handle,
		"INSERT INTO objects (username, name, uuid) VALUES (?, ?, ?) ON CONFLICT(username, name) DO NOTHING")) {
	case let s: sqlite::statement =>
		yield s;
	case let err: sqlite::error =>
		fmt::fatalf("prepare failed: {}", sqlite::strerror(err));
	};
	sqlite::bind_str(ins, 1, owner)!;
	sqlite::bind_str(ins, 2, objname)!;
	sqlite::bind_str(ins, 3, new_uuid)!;
	match (sqlite::step(ins)) {
	case void => void;
	case done => void;
	case let err: sqlite::error =>
		fmt::fatalf("insert failed: {}", sqlite::strerror(err));
	};
	sqlite::finalize(ins)!;

	const sel = match (sqlite::prepare(handle,
		"SELECT uuid FROM objects WHERE username = ? AND name = ?")) {
	case let s: sqlite::statement =>
		yield s;
	case let err: sqlite::error =>
		fmt::fatalf("prepare failed: {}", sqlite::strerror(err));
	};
	sqlite::bind_str(sel, 1, owner)!;
	sqlite::bind_str(sel, 2, objname)!;
	const obj_uuid = match (sqlite::step(sel)) {
	case void =>
		yield strings::dup(sqlite::column_str(sel, 0))!;
	case done =>
		fmt::fatalf("no result found for {}", objname);
	case let err: sqlite::error =>
		fmt::fatalf("step failed: {}", sqlite::strerror(err));
	};
	sqlite::finalize(sel)!;

	if (obj_uuid != new_uuid) {
		const dstbuf = path::init(data_dir, "objects", obj_uuid)!;
		os::rename(new_path, path::string(&dstbuf))!;
	};
};

export fn set_share(owner: str, prefix: str, scope: str, receiver: str,
		permission: str, effect: str) void = {
	const handle = meta_handle();
	defer sqlite::close(handle)!;
	const stmt = match (sqlite::prepare(handle,
		"INSERT INTO shares (owner, prefix, scope, receiver, permission, effect) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(owner, prefix, scope, receiver, permission, effect) DO NOTHING")) {
	case let s: sqlite::statement =>
		yield s;
	case let err: sqlite::error =>
		fmt::fatalf("prepare failed: {}", sqlite::strerror(err));
	};
	defer sqlite::finalize(stmt)!;
	sqlite::bind_str(stmt, 1, owner)!;
	sqlite::bind_str(stmt, 2, prefix)!;
	sqlite::bind_str(stmt, 3, scope)!;
	sqlite::bind_str(stmt, 4, receiver)!;
	sqlite::bind_str(stmt, 5, permission)!;
	sqlite::bind_str(stmt, 6, effect)!;
	match (sqlite::step(stmt)) {
	case void => void;
	case done => void;
	case let err: sqlite::error =>
		fmt::fatalf("share insert failed: {}", sqlite::strerror(err));
	};
};
