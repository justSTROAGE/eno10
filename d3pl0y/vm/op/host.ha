use db;
use encoding::utf8;
use encoding::hex;
use fmt;
use io;
use mach;
use os;
use path;
use strings;
use fs;
use time;
use uuid;

fn has_permission(requester: str, owner: str, objectname: str, action: str) bool = {
	return (requester == owner)
		|| db::get_object_permission(owner, objectname, requester, action);
};

fn op_return(op: []u8, t: *mach::task) void = {
	t.output = strings::dup(mach::stack_get_str(t)!)!;
	t.finished = true;
};

fn op_coredump(op: []u8, t: *mach::task) void = {
	mach::dump_task(t)!;
};

fn op_gettick(op: []u8, t: *mach::task) void = {
	mach::push(t, *mach::get_ticks());
};

fn op_sleep(op: []u8, t: *mach::task) void = {
	const secs = mach::pop(t);
	if (secs < 10) {
		mach::push(t, -1);
		return;
	};
	time::sleep((secs: i64) * time::SECOND);
	mach::push(t, 0);
	return;
};

fn op_getarg(op: []u8, t: *mach::task) void = {
	const ret_buf = mach::stack_get_buf(t);
	const length = if (len(ret_buf) < len(t.arg)) {
		yield len(ret_buf);
	} else {
		yield len(t.arg);
	};
	ret_buf[..length] = t.arg[..length];
	mach::push(t, length: u32);
};

fn op_getobj(op: []u8, t: *mach::task) void = {
	const name = mach::stack_get_str(t);
	const target = mach::stack_get_buf(t);
	const name = match (name) {
	case let s: str => yield s;
	case utf8::invalid =>
		fmt::fprintln(os::stderr, "op_getobj failed, invalid object name")!;
		mach::push(t, 0);
		return;
	};
	const (owner, objname) = db::get_owner_objname(name);
	if (!has_permission(t.owner, owner, objname, "r")) {
		fmt::fprintln(os::stderr, "op_getobj failed, insufficient permissions")!;
		mach::push(t, 0);
		return;
	};
	let obj = db::get_object_metadata(owner, objname);
	const data_dir = db::get_data_dir();
	const p = path::string(&path::init(data_dir, "objects", obj.uuid)!);
	const file = os::open(p)!;
	defer io::close(file)!;
	const read = 0z;
	for (read < len(target)) {
		match (io::read(file, target[read..])!) {
		case let n: size =>
			read += n;
		case io::EOF =>
			break;
		};
	};
	mach::push(t, read: u32);
};

fn op_putobj(op: []u8, t: *mach::task) void = {
	const name = mach::stack_get_str(t);
	const data = mach::stack_get_buf(t);
	const name = match (name) {
	case let s: str => yield s;
	case utf8::invalid =>
		fmt::fprintln(os::stderr, "op_putobj failed, invalid object name")!;
		mach::push(t, 0);
		return;
	};
	const (owner, objname) = db::get_owner_objname(name);
	if (!has_permission(t.owner, owner, objname, "w")) {
		fmt::fprintln(os::stderr, "op_putobj failed, insufficient permissions")!;
		mach::push(t, 0);
		return;
	};
	db::put_object_data(owner, objname, data);
	mach::push(t, len(data): u32);
};

fn op_setperm(op: []u8, t: *mach::task) void = {
	const name = mach::stack_get_str(t);
	const recv = mach::stack_get_str(t);
	const perm = mach::pop(t);
	const effect = mach::pop(t);
	const name = match (name) {
	case let s: str => yield s;
	case utf8::invalid =>
		fmt::fprintln(os::stderr, "op_setperm failed, invalid object name")!;
		mach::push(t, 0);
		return;
	};
	const (owner, objname) = db::get_owner_objname(name);
	const scope = if (strings::hassuffix(objname, "/")) "prefix" else "exact";
	const recv = match (recv) {
	case let s: str => yield s;
	case utf8::invalid =>
		fmt::fprintln(os::stderr, "op_setperm failed, invalid receiver")!;
		mach::push(t, 0);
		return;
	};
	let pbuf: [1]u8 = [(perm: u8)];
	const permstr = match (strings::fromutf8(pbuf[..])) {
	case let s: str => yield s;
	case utf8::invalid =>
		fmt::fprintln(os::stderr, "op_setperm failed, invalid permission")!;
		mach::push(t, 0);
		return;
	};
	if (permstr != "r" && permstr != "w" && permstr != "x" && permstr != "s") {
		fmt::fprintln(os::stderr, "op_setperm failed, unknown permission")!;
		mach::push(t, 0);
		return;
	};
	const effectstr = if (effect == 0) "allow" else "deny";
	if (t.owner != owner) {
		fmt::fprintln(os::stderr, "op_setperm failed, insufficient permissions")!;
		mach::push(t, 0);
		return;
	};
	if (recv == owner) {
		fmt::fprintln(os::stderr, "op_setperm failed, cannot share with yourself")!;
		mach::push(t, 0);
		return;
	};
	// Validate objname/prefix: reject GLOB metacharacters and other invalid
	// characters, mirroring the HTTP set_share OBJECTNAME_RE constraint.
	const objbytes = strings::toutf8(objname);
	if (len(objbytes) == 0 || len(objbytes) > 64) {
		fmt::fprintln(os::stderr, "op_setperm failed, invalid prefix length")!;
		mach::push(t, 0);
		return;
	};
	for (let i = 0z; i < len(objbytes); i += 1) {
		const c = objbytes[i]: u32;
		const ok = (c >= 'A' && c <= 'Z')
			|| (c >= 'a' && c <= 'z')
			|| (c >= '0' && c <= '9')
			|| c == '_' || c == '.' || c == '-' || c == '/';
		if (!ok) {
			fmt::fprintln(os::stderr, "op_setperm failed, invalid prefix")!;
			mach::push(t, 0);
			return;
		};
	};
	// Validate receiver: must be a valid username or '*public'.
	if (recv != "*public") {
		const recvbytes = strings::toutf8(recv);
		if (len(recvbytes) == 0 || len(recvbytes) > 32) {
			fmt::fprintln(os::stderr, "op_setperm failed, invalid receiver")!;
			mach::push(t, 0);
			return;
		};
		for (let i = 0z; i < len(recvbytes); i += 1) {
			const c = recvbytes[i]: u32;
			const ok = (c >= 'A' && c <= 'Z')
				|| (c >= 'a' && c <= 'z')
				|| (c >= '0' && c <= '9')
				|| c == '_' || c == '-';
			if (!ok) {
				fmt::fprintln(os::stderr, "op_setperm failed, invalid receiver")!;
				mach::push(t, 0);
				return;
			};
		};
	};
	db::set_share(owner, objname, scope, recv, permstr, effectstr);
	mach::push(t, 1);
};

fn op_getuuid(op: []u8, t: *mach::task) void = {
	const ptr = mach::pop(t): size;
	if (ptr + 32 > mach::MEM_SIZE) {
		fmt::fprintln(os::stderr, "op_getuuid failed, out of bounds")!;
		mach::push(t, 0);
		return;
	};
	t.mem[ptr..ptr+32] = strings::toutf8(hex::encodestr(uuid::generate())!);
};

fn op_callobj(op: []u8, t: *mach::task) void = {
	callobj_intern(t, false);
};

fn op_callobj_suid(op: []u8, t: *mach::task) void = {
	callobj_intern(t, true);
};

fn callobj_intern(t: *mach::task, suid: bool) void = {
	const name = mach::stack_get_str(t);
	const arg = mach::stack_get_buf(t);
	const ret_buf = mach::stack_get_buf(t);
	const name = match(name) {
	case let s: str => yield s;
	case utf8::invalid =>
		fmt::fprintln(os::stderr, "op_callobj failed, invalid object name")!;
		mach::push(t, -1);
		return;
	};
	const (owner, objname) = db::get_owner_objname(name);
	const perm = if (suid) "s" else "x";
	if (!has_permission(t.owner, owner, objname, perm)) {
		fmt::fprintln(os::stderr, "op_callobj failed, insufficient permissions")!;
		mach::push(t, -1);
		return;
	};
	const caller = if (suid) owner else t.owner;
	let subtask = match (mach::newtask(name, arg, caller)) {
	case let t: mach::task =>
		yield t;
	case let e: fs::error =>
		fmt::fatal("open:", fs::strerror(e));
	case let e: io::error =>
		fmt::fatal("read:", io::strerror(e));
	};
	run(&subtask);
	const output_encoded = strings::toutf8(subtask.output);
	const length = if (len(ret_buf) < len(output_encoded)) {
		yield len(ret_buf);
	} else {
		yield len(output_encoded);
	};
	ret_buf[..length] = output_encoded[..length];
	mach::push(t, length: u32);
	return;
};
