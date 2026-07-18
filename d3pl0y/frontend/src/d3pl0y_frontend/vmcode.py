"""Read-only helpers to render an object's bytes for the web UI.

`hexdump` and `disassemble` are *total*: object bytes are arbitrary and
attacker-controlled, so these never raise — anything that doesn't decode is
shown as raw/`??`. The opcode table mirrors documentation/vm.md.
"""

OPS = {
    0x00: "halt", 0x01: "push", 0x02: "pop", 0x03: "add", 0x04: "return",
    0x05: "getarg", 0x06: "getobj", 0x07: "sub", 0x08: "mul", 0x09: "div",
    0x0A: "mod", 0x0B: "neg", 0x0C: "and", 0x0D: "or", 0x0E: "xor", 0x0F: "not",
    0x10: "shl", 0x11: "shr", 0x12: "eq", 0x13: "ne", 0x14: "lt", 0x15: "le",
    0x16: "gt", 0x17: "ge", 0x18: "lnot", 0x19: "dup", 0x1A: "swap", 0x1B: "over",
    0x1C: "store", 0x1D: "jmp", 0x1E: "jz", 0x1F: "jnz", 0x20: "callobj",
    0x21: "gettick", 0x22: "sleep", 0x23: "callobj_suid", 0x24: "putobj",
    0x25: "setperm", 0x26: "getuuid",
}

HEX_LIMIT = 256
DISASM_LIMIT = 80

OP_REFERENCE = [
    (0x00, "halt", "( -- )", "Stop the run."),
    (0x01, "push", "( -- v )", "Push an immediate (flags 0) or mem[operand] (flags 1)."),
    (0x02, "pop", "( v -- )", "Discard the top of the stack."),
    (0x03, "add", "( a b -- a+b )", "Wrapping u32 sum."),
    (0x04, "return", "( len ptr -- )", "output = mem[ptr..ptr+len]; stop."),
    (0x05, "getarg", "( len ptr -- n )", "Copy the argument into memory; push bytes copied."),
    (0x06, "getobj", "( tlen tptr nlen nptr -- n )", "Read another object into memory."),
    (0x07, "sub", "( a b -- a-b )", "Wrapping u32 difference."),
    (0x08, "mul", "( a b -- a*b )", "Wrapping u32 product."),
    (0x09, "div", "( a b -- a/b )", "Unsigned quotient (b==0 crashes)."),
    (0x0A, "mod", "( a b -- a%b )", "Unsigned remainder (b==0 crashes)."),
    (0x0B, "neg", "( a -- -a )", "Two's-complement negation."),
    (0x0C, "and", "( a b -- a&b )", "Bitwise AND."),
    (0x0D, "or", "( a b -- a|b )", "Bitwise OR."),
    (0x0E, "xor", "( a b -- a^b )", "Bitwise XOR."),
    (0x0F, "not", "( a -- ~a )", "Bitwise complement."),
    (0x10, "shl", "( a b -- a<<b )", "Logical left shift (b>=32 -> 0)."),
    (0x11, "shr", "( a b -- a>>b )", "Logical right shift (b>=32 -> 0)."),
    (0x12, "eq", "( a b -- a==b )", "1 if equal else 0."),
    (0x13, "ne", "( a b -- a!=b )", "1 if not equal else 0."),
    (0x14, "lt", "( a b -- a<b )", "Unsigned less-than."),
    (0x15, "le", "( a b -- a<=b )", "Unsigned less-or-equal."),
    (0x16, "gt", "( a b -- a>b )", "Unsigned greater-than."),
    (0x17, "ge", "( a b -- a>=b )", "Unsigned greater-or-equal."),
    (0x18, "lnot", "( a -- !a )", "1 if a==0 else 0."),
    (0x19, "dup", "( a -- a a )", "Duplicate the top."),
    (0x1A, "swap", "( a b -- b a )", "Exchange the top two."),
    (0x1B, "over", "( a b -- a b a )", "Copy the second value to the top."),
    (0x1C, "store", "( v -- ) / ( v addr -- )", "Write a u32 to memory (flags pick the mode)."),
    (0x1D, "jmp", "( -- ) / ( target -- )", "Unconditional jump (flags pick immediate/stack)."),
    (0x1E, "jz", "( c -- )", "Jump to operand if c==0."),
    (0x1F, "jnz", "( c -- )", "Jump to operand if c!=0."),
    (0x20, "callobj", "( rlen rptr alen aptr nlen nptr -- n )", "Run another object as a subtask."),
    (0x21, "gettick", "( -- ticks )", "Push the global instruction tick counter."),
    (0x22, "sleep", "( s -- r )", "Sleep s seconds (0 if s<10 else -1 immediately)."),
    (0x23, "callobj_suid", "( rlen rptr alen aptr nlen nptr -- n )", "Run another object as a subtask, as its owner ('s' grant)."),
    (0x24, "putobj", "( dlen dptr nlen nptr -- n )", "Write bytes to an object you may write; push bytes written."),
    (0x25, "setperm", "( eff perm rlen rptr nlen nptr -- ok )", "Set a sharing rule on an object you own."),
    (0x26, "getuuid", "( ptr -- )", "generate uuid and write to `mem[ptr..ptr+16]`. "),
]


def hexdump_text(data, limit=HEX_LIMIT):
    """Classic `xxd`-style hex dump as ready-to-render text. Returns (text, truncated)."""
    view = data[:limit]
    lines = []
    for off in range(0, len(view), 16):
        chunk = view[off:off + 16]
        left = " ".join("%02x" % b for b in chunk[:8])
        right = " ".join("%02x" % b for b in chunk[8:])
        hexcol = (left + ("  " + right if right else "")).ljust(48)
        ascii_ = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append("%04x  %s |%s|" % (off, hexcol, ascii_))
    return "\n".join(lines), len(data) > limit


def _operand(mnem, flags, operand):
    """Human-readable operand text for one instruction; returns (text, bad)."""
    hexop = "0x%04x" % operand
    if mnem == "push":
        if flags == 0:
            return "%d  (%s)" % (operand, hexop), False
        if flags == 1:
            return "[%s]" % hexop, False
        return "bad flags 0x%02x" % flags, True
    if mnem == "store":
        if flags == 0:
            return "-> [%s]" % hexop, False
        if flags == 1:
            return "-> [stack addr]", False
        return "bad flags 0x%02x" % flags, True
    if mnem == "jmp":
        if flags == 0:
            return hexop, False
        if flags == 1:
            return "(stack target)", False
        return "bad flags 0x%02x" % flags, True
    if mnem in ("jz", "jnz"):
        return hexop, False
    return "", False


def disassemble(data, limit=DISASM_LIMIT):
    """Decode 4-byte instructions. Returns (rows, truncated).

    Each row: {addr, raw, mnem, arg, bad}. Unknown opcodes render as `?? 0xNN`.
    """
    rows = []
    n = len(data)
    off = 0
    while off + 4 <= n and len(rows) < limit:
        b = data[off:off + 4]
        opcode, flags = b[0], b[1]
        operand = b[2] | (b[3] << 8)
        row = {
            "addr": "%04x" % off,
            "raw": "%02x %02x %02x %02x" % (b[0], b[1], b[2], b[3]),
            "bad": False,
            "arg": "",
        }
        mnem = OPS.get(opcode)
        if mnem is None:
            row["mnem"] = "?? 0x%02x" % opcode
            row["bad"] = True
        else:
            row["mnem"] = mnem
            row["arg"], row["bad"] = _operand(mnem, flags, operand)
        rows.append(row)
        off += 4
    truncated = off < n
    return rows, truncated
