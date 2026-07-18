use endian;
use mach;

fn op_store(op: []u8, t: *mach::task) void = {
	const f = flags(op);
	switch (f) {
	case 0 =>
		const addr = operand(op): size;
		if (addr + 4 > mach::MEM_SIZE) mach::pr_err("store: oob memory write");
		const v = mach::pop(t);
		endian::little.putu32(t.mem[addr..addr + 4], v);
	case 1 =>
		const addr = mach::pop(t): size;
		if (addr + 4 > mach::MEM_SIZE) mach::pr_err("store: oob memory write");
		const v = mach::pop(t);
		endian::little.putu32(t.mem[addr..addr + 4], v);
	case =>
		mach::pr_err("store: bad flags");
	};
};
