use mach;

fn op_and(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	mach::push(t, a & b);
};

fn op_or(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	mach::push(t, a | b);
};

fn op_xor(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	mach::push(t, a ^ b);
};

fn op_not(op: []u8, t: *mach::task) void = {
	const a = mach::pop(t);
	mach::push(t, ~a);
};

fn op_shl(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	if (b >= 32) {
		mach::push(t, 0);
		return;
	};
	mach::push(t, a << b);
};

fn op_shr(op: []u8, t: *mach::task) void = {
	const b = mach::pop(t);
	const a = mach::pop(t);
	if (b >= 32) {
		mach::push(t, 0);
		return;
	};
	mach::push(t, a >> b);
};
