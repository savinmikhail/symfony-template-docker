# Official PHP runtime bases (2026-10-22)

Runtime PHP now comes directly from Docker Official Images (`library/php`).
The temporary PHP source rebuild for CVE-2026-109618/CVE-2026-109619 has been
removed. Both linux/amd64 and linux/arm64 manifests and actual PHP versions are
checked before release. Keep exact patch tags and immutable index digests.

- `php:8.4.27-fpm-trixie@sha256:e2d8e787dc775bdbd9d7e0c5e8f2f9ddb41ce5977c8bbaf99a2ba2e7d90fd8ae`

Independent security fixes for system libraries and extension downloads remain.
Run the normal full quality, fresh image security and release gates for changes.

Debian package downloads use the official HTTPS CDN at `deb.debian.org`;
APT signature verification, failure checks and bounded retries remain enabled.
