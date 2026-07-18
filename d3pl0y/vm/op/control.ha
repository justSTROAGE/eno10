use mach;

fn op_halt(op: []u8, t: *mach::task) void = {
	t.finished = true;
};

fn op_jmp(op: []u8, t: *mach::task) void = {
	const f = flags(op);
	let target = 0z;
	switch (f) {
	case 0 =>
		target = operand(op): size;
	case 1 =>
		target = mach::pop(t): size;
	case =>
		mach::pr_err("jmp: bad flags");
	};
	if (target + 4 > mach::MEM_SIZE) mach::pr_err("jmp: oob jump target");
	t.ip = target;
};

fn op_jz(op: []u8, t: *mach::task) void = {
	const c = mach::pop(t);
	if (c == 0) {
		const target = operand(op): size;
		if (target + 4 > mach::MEM_SIZE) mach::pr_err("jz: oob jump target");
		t.ip = target;
	};
};

fn op_jnz(op: []u8, t: *mach::task) void = {
	const c = mach::pop(t);
	if (c != 0) {
		const target = operand(op): size;
		if (target + 4 > mach::MEM_SIZE) mach::pr_err("jnz: oob jump target");
		t.ip = target;
	};
};
