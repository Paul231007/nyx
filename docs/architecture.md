# nyx — Architecture

nyx is a monolithic, single-address-space x86 kernel. There is no user/kernel
privilege split, no paging protection between subsystems, and no SMP. Every piece
of code runs in ring-0 protected mode. The design is intentionally layered: each
milestone depends only on the ones below it, so the bring-up sequence also doubles
as an integration test.

