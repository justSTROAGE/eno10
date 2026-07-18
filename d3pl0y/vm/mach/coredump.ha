use fmt;
use io;
use os;

export fn dump_task(t: *task) (void | io::error) = {
	const out = os::stderr;
	fmt::fprintln(out, "=== task core dump ===")?;
	fmt::fprintfln(out, "ip       = 0x{:x} ({})", t.ip, t.ip)?;
	fmt::fprintfln(out, "sp       = 0x{:x} ({})", t.sp, t.sp)?;
	fmt::fprintfln(out, "finished = {}", t.finished)?;
	fmt::fprintfln(out, "output   = {}", t.output)?;
	fmt::fprintln(out, "obj      = <object: dump separately>")?;

	fmt::fprintfln(out, "arg ({} bytes):", len(t.arg))?;
	hexdump(out, t.arg)?;

	fmt::fprintfln(out, "mem ({} bytes):", len(t.mem))?;
	hexdump(out, t.mem[..])?;

	fmt::fprintfln(out, "stack ({} u32 words):", len(t.stack))?;
	for (let i = 0z; i < len(t.stack); i += 1) {
		if (i % 8 == 0) {
			if (i > 0) {
				fmt::fprintln(out)?;
			};
			fmt::fprintf(out, "  {:_08x}:", i * 4)?;
		};
		fmt::fprintf(out, " {:_08x}", t.stack[i])?;
	};
	fmt::fprintln(out)?;
	fmt::fprintln(out, "======================")?;
};

fn hexdump(out: io::handle, data: []u8) (void | io::error) = {
	const cols = 16z;
	for (let i = 0z; i < len(data); i += cols) {
		fmt::fprintf(out, "  {:_08x}: ", i)?;

		for (let j = 0z; j < cols; j += 1) {
			if (i + j < len(data)) {
				fmt::fprintf(out, "{:_02x} ", data[i + j])?;
			} else {
				fmt::fprint(out, "   ")?;
			};
		};

		fmt::fprint(out, " |")?;
		for (let j = 0z; j < cols; j += 1) {
			if (i + j < len(data)) {
				const b = data[i + j];
				const c: rune = if (b >= 0x20 && b < 0x7f) {
					yield b: u32: rune;
				} else {
					yield '.';
				};
				fmt::fprintf(out, "{}", c)?;
			} else {
				fmt::fprint(out, " ")?;
			};
		};
		fmt::fprintln(out, "|")?;
	};
};
