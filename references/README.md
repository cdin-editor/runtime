# Reference snapshots

`spec/` and `kernel/` contain read-only source snapshots copied from the supplied Spec and Kernel trees so this initial extraction can be reviewed without switching archives. They are **not** submodules or the canonical repositories. Update the corresponding upstream repository first and refresh the snapshot explicitly when needed.

The Kernel header at `kernel/include/cdin/kernel.h` is for contract inspection only. Runtime source and build scripts must not include or compile against it directly.
