//! paging — 32-bit x86, no-PAE, 4 KiB pages. Builds a page directory + page
//! tables, identity-maps low physical RAM 1:1, then enables CR0.PG. After
//! init() the kernel runs in virtual memory (identity-mapped, so addresses are
//! unchanged). `map()` installs a single 4 KiB page (used later by the heap).

