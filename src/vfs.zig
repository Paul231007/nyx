//! VFS — a filesystem-agnostic virtual file system layer.
//!
//! Any concrete filesystem registers itself via `mount`. Callers interact with
//! files through integer file descriptors (Fd). The implementation keeps a
//! fixed-size fd table (16 slots); each slot tracks the open Node and the
//! current read/write offset.


