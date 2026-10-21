# PHP emergency source rebuild (2026-10-21)

PHP 8.5.12 / 8.4.27 / 8.3.36 fix CVE-2026-109618 and CVE-2026-109619.
Docker Official Images had empty manifests for these patch tags at preparation.
The temporary security stage rebuilds the official PHP release on the existing
pinned official base, retaining its configure options and extension ABI.
It verifies the source SHA256, runtime version, extension path and module set.
Application extensions are compiled after this stage as before.

Source checksums come from docker-library/php commit
`e3eaff845f7a9f7259c31da54dce0320b47a3bbd`:
https://github.com/docker-library/php/commit/e3eaff845f7a9f7259c31da54dce0320b47a3bbd

When official patched images are available for every required architecture,
replace this stage with the matching exact PHP patch tag and immutable digest,
then remove the helper and rerun the normal image/security/release gates.
Do not restore an unpatched base without this rebuild stage.
