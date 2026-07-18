use endian;
use mach;

fn flags(op: []u8) u8 = {
	return op[1];
};

fn operand(op: []u8) u16 = {
	return endian::little.getu16(op[2..4]);
};

fn dispatch(t: *mach::task) void = {
	const op = t.mem[t.ip..t.ip+4];
	t.ip += 4;
	switch (op[0]) {
	case 0x00 => op_halt(op, t);
	case 0x01 => op_push(op, t);
	case 0x02 => op_pop(op, t);
	case 0x03 => op_add(op, t);
	case 0x04 => op_return(op, t);
	case 0x05 => op_getarg(op, t);
	case 0x06 => op_getobj(op, t);
	case 0x07 => op_sub(op, t);
	case 0x08 => op_mul(op, t);
	case 0x09 => op_div(op, t);
	case 0x0a => op_mod(op, t);
	case 0x0b => op_neg(op, t);
	case 0x0c => op_and(op, t);
	case 0x0d => op_or(op, t);
	case 0x0e => op_xor(op, t);
	case 0x0f => op_not(op, t);
	case 0x10 => op_shl(op, t);
	case 0x11 => op_shr(op, t);
	case 0x12 => op_eq(op, t);
	case 0x13 => op_ne(op, t);
	case 0x14 => op_lt(op, t);
	case 0x15 => op_le(op, t);
	case 0x16 => op_gt(op, t);
	case 0x17 => op_ge(op, t);
	case 0x18 => op_lnot(op, t);
	case 0x19 => op_dup(op, t);
	case 0x1a => op_swap(op, t);
	case 0x1b => op_over(op, t);
	case 0x1c => op_store(op, t);
	case 0x1d => op_jmp(op, t);
	case 0x1e => op_jz(op, t);
	case 0x1f => op_jnz(op, t);
	case 0x20 => op_callobj(op, t);
	case 0x21 => op_gettick(op, t);
	case 0x22 => op_sleep(op, t);
	case 0x23 => op_callobj_suid(op, t);
	case 0x24 => op_putobj(op, t);
	case 0x25 => op_setperm(op, t);
	case 0x26 => op_getuuid(op, t);
	case => mach::pr_err("invalid opcode");
	};
};

export fn run(t: *mach::task) void = {
	for (!t.finished) {
		*mach::get_ticks() += 1;
		dispatch(t);
	};
};
