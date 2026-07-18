use db;
use fmt;
use fs;
use io;
use os;
use path;
use strings;
use encoding::utf8;

export def MEM_SIZE: size = 1024;
export def STACK_SIZE: size = 256;
def OBJ_PATH: str = "data/objects";

export type task = struct {
	mem: [MEM_SIZE]u8,
	stack: [STACK_SIZE]u32,
	ip: size,
	sp: size,
	finished: bool,
	obj: db::object,
	arg: []u8,
	output: str,
	owner: str,
};

export fn pr_err(msg: str) never = fmt::fatal("vm error:", msg);

export fn push(t: *task, v: u32) void = {
	if (t.sp >= STACK_SIZE) pr_err("stack overflow");
	t.stack[t.sp] = v;
	t.sp += 1;
};

export fn pop(t: *task) u32 = {
	if (t.sp == 0) pr_err("stack underflow");
	t.sp -= 1;
	return t.stack[t.sp];
};

export fn stack_get_buf(t: *task) []u8 = {
	const buf_ptr = pop(t): size;
	const buf_len = pop(t): size;
	if (buf_len > MEM_SIZE || buf_ptr > MEM_SIZE
			|| buf_ptr + buf_len > MEM_SIZE) {
		pr_err("stack_get_buf out of bounds");
	};
	return t.mem[buf_ptr..buf_ptr+buf_len];
};

export fn stack_get_str(t: *task) (str | utf8::invalid) = {
	const buf = stack_get_buf(t);
	return strings::fromutf8(buf);
};

export fn get_ticks() *u32 = {
	static let ticks: u32 = 0;
	return &ticks;
};

export fn newtask(objectname: str, arg: []u8, caller: str) (task | fs::error | io::error) = {
	const (owner, objname) = db::get_owner_objname(objectname);
	let obj = db::get_object_metadata(owner, objname);
	const data_dir = db::get_data_dir();
	const p = path::string(&path::init(data_dir, "objects", obj.uuid)!);
	const file = os::open(p)?;
	defer io::close(file)!;

	let t = task {
		obj = obj,
		arg = arg,
		owner = caller,
		...
	};

	let buf = t.mem[..];
	for (len(buf) > 0) {
		match (io::read(file, buf)?) {
		case let n: size =>
			buf = buf[n..];
		case io::EOF =>
			break;
		};
	};
	return t;
};
