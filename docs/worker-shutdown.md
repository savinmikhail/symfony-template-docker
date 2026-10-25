# Polling worker shutdown

PHP-FPM images use SIGQUIT for FPM. A CLI polling worker must explicitly set
`stop_signal: SIGTERM` in its Compose service; keep FPM on its existing signal.

The runtime includes `/usr/local/bin/worker-lifecycle.sh`. Source it from a
polling shell, run commands via `worker_run`, interval/startup sleeps via
`worker_sleep`, and loop while `worker_shutdown` is zero. This finishes the
active command, interrupts idle sleeps and skips subsequent work after TERM/INT.
The Docker stop timeout remains the upper bound for a command that is stuck.

Do not add `init: true` blindly: PID-1 health checks may depend on the application
being PID 1. A Python HTTP service must install a TERM handler and close its
server while joining in-flight requests; the default TERM disposition is not a
reliable container PID-1 shutdown policy.

Verified rollout candidates: Interviews media/outbox/legacy/OCR, Mock
outbox/provider-jobs and Platform GCal/Notion/deadline loops. Other product repositories have no matching polling-shell
pattern in their docker worker scripts at the time of the audit. The Debian
mirror probe from Interviews requires an existing Python runtime; it is not
copied into this PHP-only baseline as a new runtime dependency.

Run `python3 docker/runtime/test_worker_lifecycle.py` in Linux CI or inside a
Linux runtime container for the lifecycle contract. Product changes also need real Docker PID-1 tests for their launchers.
