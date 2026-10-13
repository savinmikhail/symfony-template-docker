# Persistent self-hosted BuildKit cache

The setup-ci-builder composite action keeps separate bounded state per repository, runner and PR/trusted boundary. BuildKit GC targets 8 GB maximum, 1 GB reserved and 15 GB host free space. Retain registry caches as fallback; these GC targets are not filesystem quotas.

On dedicated CI hosts only, install scripts/ci/runner-maintenance.sh as /usr/local/sbin/mentoring-ci-maintenance and schedule daily. It skips active Runner.Worker processes, removes unused images older than 72 hours and disposable UUID builders older than 48 hours. Named ci-* builders are preserved. Never install this on production hosts.

Rollout: Interviews adopts this pattern first. Mock, Platform, Tech Tasks, Mentoring BI and Auth still require repository-specific validation before switching their workflows; do not change their release/deploy boundaries automatically.
