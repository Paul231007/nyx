# Memory subsystem

nyx has four cooperating memory components: the physical frame allocator (PMM),
the paging layer, the kernel heap, and the block cache. They are initialised in
this order during boot and each depends on the ones before it.

