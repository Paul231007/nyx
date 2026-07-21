//! paging — 32-bit x86, no-PAE, 4 KiB pages. Builds a page directory + page
//! tables, identity-maps low physical RAM 1:1, then enables CR0.PG. After
//! init() the kernel runs in virtual memory (identity-mapped, so addresses are
//! unchanged). `map()` installs a single 4 KiB page (used later by the heap).

const pmm = @import("pmm.zig");

const PAGE_SIZE: usize = 4096;
const ENTRIES: usize = 1024; // entries per directory / table
const PAGE_4MIB: usize = ENTRIES * PAGE_SIZE; // 4 MiB covered by one page table


