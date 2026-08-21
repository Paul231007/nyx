//! ramfs — an in-memory filesystem backed by a fixed array of 64 entries.
//!
//! Paths are stored with a leading '/' (e.g. "/hello.txt", "/etc", "/etc/motd").
//! The root directory entry always lives at index 0 with path "/".


