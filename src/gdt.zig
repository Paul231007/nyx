//! Flat (segmentation-disabled) GDT for protected mode.
//! Three descriptors: null, ring-0 code, ring-0 data — all base 0, 4 GiB limit.
//! After loading we reload the segment registers so the new descriptors take
//! effect (CS via a far jump, the rest via plain moves).


