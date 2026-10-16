# Alert fixes and template main reconciliation

Status: reconciled and verified on 16 October 2026.

Merged origin/main into canonical main without rewriting either history. Newer
remote release supersession, security gates, explicit Compose project arguments,
Scout isolation and image publication remain intact. Local HTTP timeout, JSON
classification, registry credential isolation and alert-title checks are retained.

The full gate exposed two Composer advisories. Updated symfony/http-foundation
and symfony/yaml within 7.4 constraints (plus their allowed polyfill dependency).
Declared psr/log and symfony/http-client-contracts as direct dependencies of the
HTTP decorator. Updated the synthetic contact-point test to match the existing
validated literal chat identifier; bot tokens still use environment references.

Validation: make quality passed, including fresh Composer/npm audits, frontend
checks/build, PHPStan, PHPat, dependency analysis, style, Rector, production DI,
Doctrine migrations/schema and PHPUnit (6 tests / 32 assertions). Registry
isolation (3 tests), Compose networking (6 tests), notification links/templates,
contact-point generation and release scope checks passed. AST graph updated.
The template itself has no production target.

## Published release

Template v0.0.10 (0d5d078c3c57315b54ed9dbd78a20defe8f91cd1) passed
[CI 38858987422](https://github.com/savinmikhail/symfony-template-docker/actions/runs/38858987422)
and [Release 38859431626](https://github.com/savinmikhail/symfony-template-docker/actions/runs/38859431626).
The template production deploy job is intentionally excluded. PHP/nginx images
were independently inspected in GHCR after successful Scout and publication:

- PHP: sha256:8414dc5762b64168dd5df473b3df87a7f633e104ca979ab95cd3e3bb716781ff
- nginx: sha256:f09e413ec157d1ba22611070bba3540f200059644cacbeb76d13d8abb500282e

Actual hosted CI also exposed invalid Buildx names when runner.name contains
spaces and a KICS final-stage USER finding. Builder naming now preserves valid
self-hosted names/caches and hashes normalized hosted identities; six executable
regression cases and a real Buildx create/inspect/remove check passed. The action
fix was mirrored and committed separately in all six products. The nginx final
stage explicitly repeats its inherited USER nginx; KICS passes with no High or
Critical findings. No scanner policy was relaxed.
