use mach;

fn boolu32(b: bool) u32 = {
	if (b) return 1;
	return 0;
};

fn op_eq(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	mach::push(t, boolu32(a == b));
};

fn op_ne(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	mach::push(t, boolu32(a != b));
};

fn op_lt(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	mach::push(t, boolu32(a < b));
};

fn op_le(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	mach::push(t, boolu32(a <= b));
};

fn op_gt(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	mach::push(t, boolu32(a > b));
};

fn op_ge(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	mach::push(t, boolu32(a >= b));
};

fn op_lnot(op: []u8, t: *mach::task) void = {
	const a = mach::pop(t);
	mach::push(t, boolu32(a == 0));
};
