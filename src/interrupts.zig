//! CPU exception (ISR) layer: 32 assembly stubs for vectors 0..31 funnel into
//! one common stub that saves a uniform register frame and calls `isrHandler`.
//!
//! Stack frame, from low address (where the Frame pointer points) upward:
//!   ds, edi, esi, ebp, esp_dummy, ebx, edx, ecx, eax  (from `push %ds` + pusha)
//!   int_no, err_code                                   (pushed by the stubs)
//!   eip, cs, eflags[, useresp, ss]                     (pushed by the CPU)

