use fmt;
use fs;
use io;
use mach;
use op;
use os;
use strings;

export fn main() void = {
	let t = match (mach::newtask(os::args[1], strings::toutf8(os::args[2]), os::args[3])) {
		case let t: mach::task => yield t;
		case let e: fs::error => fmt::fatal("open:", fs::strerror(e));
		case let e: io::error => fmt::fatal("read:", io::strerror(e));
	};
	op::run(&t);
	fmt::println(t.output)!;
};
