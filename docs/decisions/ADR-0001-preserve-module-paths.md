# ADR-0001: Preserve `core.*` module paths during the first extraction

- **Status:** Accepted for bootstrap extraction
- **Context:** Existing modules use `require "core.*"`, and plugins may depend on those paths.
- **Decision:** Copy the current source into `data/core/` without a mass path rename. Introduce new seams in small, independently tested modules.
- **Consequences:** Extraction diff is inspectable and regressions are easier to bisect. The tree may retain legacy coupling until staged migrations remove it.
