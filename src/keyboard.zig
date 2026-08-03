//! PS/2 keyboard driver, scancode set 1 (QEMU default).
//!
//! On IRQ1 we read one scancode from port 0x60. Break codes (bit 7 set) are
//! ignored except for shift release. Make codes are mapped to ASCII via a
//! US-QWERTY table (shifted variant when shift is held) and pushed into the
//! shared input ring. Extended (0xE0) sequences are skipped.

const io = @import("io.zig");
const input = @import("input.zig");

const DATA_PORT: u16 = 0x60;

// Make codes
const SC_LSHIFT: u8 = 0x2A;
const SC_RSHIFT: u8 = 0x36;
const SC_CAPSLOCK: u8 = 0x3A;
const SC_LCTRL: u8 = 0x1D;
const SC_LALT: u8 = 0x38;
const SC_EXTENDED: u8 = 0xE0;
const SC_F1: u8 = 0x3B;
const SC_F2: u8 = 0x3C;
const SC_F3: u8 = 0x3D;
const SC_F4: u8 = 0x3E;
const SC_F5: u8 = 0x3F;
const SC_F6: u8 = 0x40;
const SC_F7: u8 = 0x41;
const SC_F8: u8 = 0x42;
const SC_F9: u8 = 0x43;
const SC_F10: u8 = 0x44;
const SC_F11: u8 = 0x57;
const SC_F12: u8 = 0x58;
const SC_HOME: u8 = 0x47;
const SC_UP: u8 = 0x48;
const SC_PGUP: u8 = 0x49;
const SC_LEFT: u8 = 0x4B;
const SC_RIGHT: u8 = 0x4D;
const SC_END: u8 = 0x4F;
const SC_DOWN: u8 = 0x50;
const SC_PGDN: u8 = 0x51;
const SC_INS: u8 = 0x52;
const SC_DEL: u8 = 0x53;

var shift: bool = false;
var caps: bool = false;
var ctrl: bool = false;
var alt: bool = false;
var expect_extended: bool = false;

/// Unshifted US-QWERTY scancode -> ASCII, set 1, codes 0x00..0x58.
const map = [_]u8{
    0, 0x1B, '1', '2', '3', '4', '5', '6', // 0x00
    '7', '8', '9', '0', '-', '=', 0x08, '\t', // 0x08
    'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', // 0x10
    'o', 'p', '[', ']', '\n', 0, 'a', 's', // 0x18
    'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', // 0x20
    '\'', '`', 0, '\\', 'z', 'x', 'c', 'v', // 0x28
    'b', 'n', 'm', ',', '.', '/', 0, '*', // 0x30
    0, ' ', 0, 0, 0, 0, 0, 0, // 0x38
    0, 0, 0, 0, 0, 0, 0, '7', // 0x40
    '8', '9', '-', '4', '5', '6', '+', '1', // 0x48
    '2', '3', '0', '.', 0, 0, 0, 0, // 0x50
    0, // 0x58
};

/// Shifted variant of the table above.
const map_shift = [_]u8{
    0, 0x1B, '!', '@', '#', '$', '%', '^', // 0x00
    '&', '*', '(', ')', '_', '+', 0x08, '\t', // 0x08
    'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', // 0x10
    'O', 'P', '{', '}', '\n', 0, 'A', 'S', // 0x18
    'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', // 0x20
    '"', '~', 0, '|', 'Z', 'X', 'C', 'V', // 0x28
    'B', 'N', 'M', '<', '>', '?', 0, '*', // 0x30
    0, ' ', 0, 0, 0, 0, 0, 0, // 0x38
    0, 0, 0, 0, 0, 0, 0, '7', // 0x40
    '8', '9', '-', '4', '5', '6', '+', '1', // 0x48
    '2', '3', '0', '.', 0, 0, 0, 0, // 0x50
    0, // 0x58
};

pub fn handleIrq() void {
    const sc = io.inb(DATA_PORT);

    if (sc == SC_EXTENDED) {
        expect_extended = true;
        return;
    }
    if (expect_extended) {
        // Skip the byte following an 0xE0 prefix.
        expect_extended = false;
        return;
    }

    if (sc & 0x80 != 0) {
        // Break code — update modifier state on release.
        const make = sc & 0x7F;
        if (make == SC_LSHIFT or make == SC_RSHIFT) shift = false;
        if (make == SC_LCTRL) ctrl = false;
        if (make == SC_LALT) alt = false;
        return;
    }

    // Make code — update modifiers.
    if (sc == SC_LSHIFT or sc == SC_RSHIFT) { shift = true; return; }
    if (sc == SC_LCTRL) { ctrl = true; return; }
    if (sc == SC_LALT) { alt = true; return; }
    if (sc == SC_CAPSLOCK) { caps = !caps; return; } // toggle on press

    if (sc < map.len) {
        const ch = translate(sc, shift, caps);
        if (ch != 0) input.push(ch);
    }
}

/// Translate a raw make scancode to an ASCII character.
/// `s` = shift held, `c` = CapsLock active.
/// Returns 0 for non-printable or unknown scancodes.
pub fn translate(sc: u8, s: bool, c: bool) u8 {
    if (sc >= map.len) return 0;
    const base = map[sc];
    const shifted = map_shift[sc];
    // For letter keys: CapsLock flips the case; shift can further invert it.
    // For non-letter keys: CapsLock has no effect; only shift applies.
    const is_letter = (base >= 'a' and base <= 'z');
    if (is_letter) {
        // caps XOR shift determines the final case
        const upper_wanted = c != s; // XOR
        return if (upper_wanted) shifted else base;
    }
    return if (s) shifted else base;
}

/// Return a printable name for special (non-ASCII-producing) scancodes.
/// For ordinary printable scancodes, returns "".
pub fn name(sc: u8) []const u8 {
    return switch (sc) {
        SC_F1      => "F1",
        SC_F2      => "F2",
        SC_F3      => "F3",
        SC_F4      => "F4",
        SC_F5      => "F5",
        SC_F6      => "F6",
        SC_F7      => "F7",
        SC_F8      => "F8",
        SC_F9      => "F9",
        SC_F10     => "F10",
        SC_F11     => "F11",
        SC_F12     => "F12",
        SC_HOME    => "Home",
        SC_UP      => "Up",
        SC_PGUP    => "PgUp",
        SC_LEFT    => "Left",
        SC_RIGHT   => "Right",
        SC_END     => "End",
        SC_DOWN    => "Down",
        SC_PGDN    => "PgDn",
        SC_INS     => "Ins",
        SC_DEL     => "Del",
        SC_LSHIFT  => "LShift",
        SC_RSHIFT  => "RShift",
        SC_LCTRL   => "LCtrl",
        SC_LALT    => "LAlt",
        SC_CAPSLOCK => "CapsLock",
        else       => "",
    };
}

/// Return true when the Ctrl modifier is currently held.
pub fn isCtrl() bool { return ctrl; }

/// Return true when the Alt modifier is currently held.
pub fn isAlt() bool { return alt; }

/// Return true when CapsLock is active.
pub fn isCaps() bool { return caps; }
