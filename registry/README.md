# Registry release metadata

Runtime publishes its component Release Metadata in `registry/releases/`. The current entry is `runtime-1.0.0-rc.1.json`, with source revision `d2acb6f174edf127c3bf59e8e5d4aedcbef0d490`.

- Component identity: `runtime/default`
- Package version: `1.0.0-rc.1` (prerelease)
- Required contract: `org.cdin.runtime-host-api`, constraint `>=1.0.0 <2.0.0`
- Dependencies: none declared at the component level

Backend provides the Runtime Host API contract. The current CDIN Product Definitions temporarily allow prerelease selection because this is the currently integrated Runtime candidate. A stable Runtime release should be published with a new immutable metadata document; CDIN can then disable prerelease selection. Registry is not a Runtime dependency.
