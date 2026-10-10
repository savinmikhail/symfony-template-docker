# Optional independently deployed frontend modules

Use ordinary annotated version tags. The `Deploy-Scope` trailer selects release
composition; the tag name remains `vX.Y.Z`. `scripts/local/deploy-scope.sh` defaults
legacy tags to full and rejects unknown or duplicate trailers. Its fixture test
covers full, web-only, frontend-only and invalid metadata.

When adding an embedded frontend, evaluate scope before any backend job. A
frontend-only release must skip migrations, backend images and backend deploy.
Full/web releases can publish their module after the backend gate succeeds;
worker-only scopes must not publish unrelated frontend changes. Explicit backend
workflow dispatch must reject frontend-only tags too.

`scripts/deploy/publish-static-assets.sh IMAGE SOURCE DESTINATION` retains old
content-addressed resources and publishes manifest/index last. Serialize release
operations, pin image digests and verify source revision. Back up the current
manifest/image setting, restore on smoke failure, and keep rollback artifacts.
Browser smoke should verify guest navigation/login return without production
credentials, OTP or microphone permissions.

Product evaluation: Tasks, Platform, Mock and Interviews are embedded modules.
Auth is a separate identity frontend; BI remains an external application. Their
backend pipelines should not receive module jobs unless their deployment model
changes. Product repositories supply their own domains, ports, images, SDK and
credentials; these are intentionally not embedded in this optional baseline.
