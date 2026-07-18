use mach;

fn op_add(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	mach::push(t, a + b);
};

fn op_sub(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	mach::push(t, a - b);
};

fn op_mul(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	mach::push(t, a * b);
};

fn op_div(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	if (b == 0) mach::pr_err("div: division by zero");
	mach::push(t, a / b);
};

fn op_mod(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	if (b == 0) mach::pr_err("mod: division by zero");
	mach::push(t, a % b);
};

fn op_neg(op: []u8, t: *mach::task) void = {
	const a = mach::pop(t);
	mach::push(t, 0 - a);
};
