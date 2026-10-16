# Alpine package mirror

The PostgreSQL backup image accepts `ALPINE_MIRROR` (default:
`https://dl-4.alpinelinux.org/alpine`). This official alternate mirror avoids
production build failures where the CDN endpoint has TLS/connectivity problems.
Only the repository origin changes: Alpine branch paths, HTTPS, package signatures
and package versions remain controlled by the selected base image and APK.

Check reachability from the actual build host and rebuild the backup image before
adopting another mirror. Do not disable certificate or package signature checks.

Rollout assessment: Mock, Platform, Tasks, Interviews and Auth have comparable
APK-based backup images and can adopt this argument at their next infrastructure
change. BI has no matching `docker/postgres-backup/Dockerfile`. No product service
restart or release is required solely to update the reusable template.
