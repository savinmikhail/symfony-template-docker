#!/usr/bin/env bash
set -euo pipefail
parser=$(cd "$(dirname "$0")" && pwd)/deploy-scope.sh
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cd "$fixture"
git init -q
git -c user.name=Fixture -c user.email=fixture@localhost commit --allow-empty -qm fixture
tag() { git -c user.name=Fixture -c user.email=fixture@localhost -c tag.gpgSign=false tag -a "$1" -m "$2"; }
git tag v0.0.1
[[ $(bash "$parser" v0.0.1) == full ]]
tag v0.0.2 $'Release\n\nDeploy-Scope: frontend-only'
[[ $(bash "$parser" v0.0.2) == frontend-only ]]
tag v0.0.3 $'Release\n\nDeploy-Scope: web-only'
[[ $(bash "$parser" v0.0.3) == web-only ]]
tag v0.0.4 $'Release\n\nDeploy-Scope: unknown'
if bash "$parser" v0.0.4 >/dev/null 2>&1; then exit 1; fi
tag v0.0.5 $'Release\n\nDeploy-Scope: full\nDeploy-Scope: frontend-only'
if bash "$parser" v0.0.5 >/dev/null 2>&1; then exit 1; fi
printf 'Release scope tests passed\n'
