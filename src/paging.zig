//! paging — 32-bit x86, no-PAE, 4 KiB pages. Builds a page directory + page
//! tables, identity-maps low physical RAM 1:1, then enables CR0.PG. After
//! init() the kernel runs in virtual memory (identity-mapped, so addresses are
//! unchanged). `map()` installs a single 4 KiB page (used later by the heap).

const pmm = @import("pmm.zig");

const PAGE_SIZE: usize = 4096;
const ENTRIES: usize = 1024; // entries per directory / table
const PAGE_4MIB: usize = ENTRIES * PAGE_SIZE; // 4 MiB covered by one page table

// Identity-map [0, MAP_LIMIT). 64 MiB covers the whole `-m 64` RAM: kernel
// image, stack, pmm bitmap, the page tables themselves, and VGA at 0xB8000.
const MAP_LIMIT: usize = 0x4000000; // 64 MiB → 16 page tables

// PDE/PTE flag bits.
const PRESENT: u32 = 0x1;
const RW: u32 = 0x2;
const USER: u32 = 0x4;

// Physical address of the page directory (CR3 value).
var page_directory: usize = 0;

inline fn dirPtr() [*]volatile u32 {
    return @ptrFromInt(page_directory);
}

pub fn init() void {
    // (a) Allocate + zero the page directory.
    page_directory = pmm.allocFrame().?;
    const pd = dirPtr();
    var i: usize = 0;
    while (i < ENTRIES) : (i += 1) pd[i] = 0;

    // (b) Identity-map [0, MAP_LIMIT) with present+rw pages.
    var virt: usize = 0;
    while (virt < MAP_LIMIT) : (virt += PAGE_4MIB) {
        // One page table covers 4 MiB.
        const pt_phys = pmm.allocFrame().?;
        const pt: [*]volatile u32 = @ptrFromInt(pt_phys);
        var j: usize = 0;
        while (j < ENTRIES) : (j += 1) {
            const phys = virt + j * PAGE_SIZE;
            pt[j] = @as(u32, @intCast(phys)) | PRESENT | RW;
        }
        const pde_idx = virt >> 22;
        pd[pde_idx] = @as(u32, @intCast(pt_phys)) | PRESENT | RW;
    }

    // (c) Load CR3, then flip CR0.PG.
    asm volatile ("mov %[pd], %%cr3"
        :
        : [pd] "r" (page_directory),
        : .{ .memory = true });
    asm volatile (
        \\mov %%cr0, %%eax
        \\or  $0x80000000, %%eax
        \\mov %%eax, %%cr0
        ::: .{ .eax = true, .memory = true });
}

/// Map a single 4 KiB page: virt → phys with the given flags (present + rw etc).
pub fn map(virt: usize, phys: usize, flags: u32) void {
    const pd = dirPtr();
    const pde_idx = virt >> 22;
    const pte_idx = (virt >> 12) & 0x3FF;

    var pde = pd[pde_idx];
    if ((pde & PRESENT) == 0) {
        // Allocate a fresh page table, zero it, install it.
        const pt_phys = pmm.allocFrame().?;
        const pt: [*]volatile u32 = @ptrFromInt(pt_phys);
        var k: usize = 0;
        while (k < ENTRIES) : (k += 1) pt[k] = 0;
        var pde_flags: u32 = PRESENT | RW;
        if ((flags & USER) != 0) pde_flags |= USER;
        pde = @as(u32, @intCast(pt_phys)) | pde_flags;
        pd[pde_idx] = pde;
    }

