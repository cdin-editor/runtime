# Security policy

The Runtime executes extension code and treats extensions as untrusted policy
code, not as Backend code.

- Do not expose `io`, `os`, `debug`, `package`, native loaders, C pointers or
  Kernel/Backend handles through extension environments.
- Filesystem, process, clipboard and other operating-system effects require
  explicit Backend capabilities and a documented authorization policy.
- Validate all data received over Host or extension boundaries. Prefer stable
  error codes and fail closed on incompatible Host descriptors.
- The Lua sandbox is not an OS security boundary. Run hostile extensions in a
  separate process if isolation is required.
- Report potential vulnerabilities privately to the project maintainer before
  public disclosure.
