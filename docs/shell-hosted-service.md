# Shell-hosted services

The default nginx target prod retains the template's standalone frontend. Services whose UI is independently published to a shared shell should select nginx target api-only and provide API/static-resource routes without an index.html fallback. Do not remove standalone from a service before its shell module release path exists.

Build backend and module artifacts independently from the same commit SHA, behind their required quality/security gates. A release may switch backend only after both required artifact branches pass, then publish the matching module digest after backend smoke. Never rebuild the module after backend deployment. Persist module SHA and immutable image digests as a CI artifact; validate them against the successful release revision before publishing.

Backend-only releases must not rebuild/switch modules. Frontend-only releases must not migrate or restart backend. Maintain backward-compatible API contracts during the switching window; use expand/contract for breaking changes. Keep all production deploys tag-gated and non-cancellable once started.
