use endian;
use mach;

fn op_push(op: []u8, t: *mach::task) void = {
	const f = flags(op);
	const arg = operand(op);
	switch (f) {
	case 0 =>
		mach::push(t, arg: u32);
	case 1 =>
		const addr = arg: size;
		if (addr + 4 > mach::MEM_SIZE) mach::pr_err("push: oob memory read");
		mach::push(t, endian::little.getu32(t.mem[addr..addr + 4]));
	case =>
		mach::pr_err("push: bad flags");
	};
};

fn op_pop(op: []u8, t: *mach::task) void = {
	mach::pop(t);
};

fn op_dup(op: []u8, t: *mach::task) void = {
	const a = mach::pop(t);
	mach::push(t, a);
	mach::push(t, a);
};

fn op_swap(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	mach::push(t, b);
	mach::push(t, a);
};

fn op_over(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	mach::push(t, a);
	mach::push(t, b);
	mach::push(t, a);
};
