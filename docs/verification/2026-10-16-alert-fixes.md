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
