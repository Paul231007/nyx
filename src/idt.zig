//! 256-entry Interrupt Descriptor Table.
//! Gates are filled in by callers (e.g. the exception layer) via `setGate`,
//! then committed to the CPU with `load`.

