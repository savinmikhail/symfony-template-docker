# Persistent self-hosted BuildKit cache

The setup-ci-builder composite action keeps separate bounded state per repository, runner and PR/trusted boundary. BuildKit GC targets 8 GB maximum, 1 GB reserved and 15 GB host free space. Retain registry caches as fallback; these GC targets are not filesystem quotas.

On dedicated CI hosts only, install scripts/ci/runner-maintenance.sh as /usr/local/sbin/mentoring-ci-maintenance and schedule daily. It skips active Runner.Worker processes, removes unused images older than 72 hours and disposable UUID builders older than 48 hours. Named ci-* builders are preserved. Never install this on production hosts.

Rollout: the five sibling product repositories receive repository-specific workflow adaptations alongside this template. Their existing deployment scopes and production boundaries remain owned by each product. No release/deploy is required to validate this source-only rollout.

## Execution order and security

CI PHP image -> all independent dev gates -> production build once -> fresh Scout -> push the checked local image -> deployment. Backend quality uses one matrix job per existing Make target with fail-fast disabled; PHPUnit retains its separate database lifecycle and runs alongside those checks. Compose project names include run, attempt and matrix index so this workflow also remains isolated when moved to shared self-hosted runners.

Scout requires DOCKERHUB_USERNAME and DOCKERHUB_TOKEN secrets. It fails on fixable High/Critical findings and preserves SARIF reports. Its SBOM cache and its separate fanal index cache have independent per-job directories, including XDG_CACHE_HOME. No vulnerability verdict is reused. This adds a production-image security gate to the template, whose previous CI had no Scout gate; existing base-image pins may require their own security refresh before a future publish passes. This task does not alter those pins or waive findings.

PR jobs can read trusted registry caches but do not export to them. Persistent builders retain local state; registry cache export remains enabled for trusted tag builds. Hosted ubuntu-latest remains the portable template default; it has no cross-machine local persistence. Products using self-hosted runners obtain the persistent-state benefit without copying product-specific runner labels into the template.

The template itself has no production target. Its conditional reusable deployment remains behind every gate, and no release/module workflow is copied from a product. Product final notifications remain after their complete deployment graph; this template does not introduce Telegram credentials into projects that do not configure notifications.
