# Tag deployment on recovered installations

The normal Git/monitoring release route stays the default. Set repository variable
`DEPLOY_RECOVERY_MODE=1` only for a recovered Compose installation without `.git`;
`DEPLOY_COMPOSE_PROJECT` must match the running project's existing label.

The existing verified CI tag and SHA-labelled GHCR images are still required.
Deployment ships `git archive` of that exact tag into a private immutable release
directory, preserves root/app `.env.local` and the operator's recovery Compose
override, verifies image revisions, runs additive database migrations, switches
only selected application containers, and checks HTTP from inside nginx.
Databases are never stopped or replaced. Previous configuration and immutable
image IDs remain available for rollback; database migrations are not undone.

The deploy step uses the existing repository SSH credentials and temporary GHCR
credentials; it creates no SSH key or persistent registry login. Production
credentials must be explicitly configured by an authorized operator.

Three fixture tests exercise revision validation, environment preservation,
migration ordering, and application rollback without touching the database.
The generic helper is mirrored into symfony-template-docker. Other product
services retain the normal deployment path until explicitly migrated.
