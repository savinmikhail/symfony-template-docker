# Apply alerting without an application release

`make monitoring-alerts-apply GRAFANA_CONTAINER=<existing-product-grafana>` applies only versioned Grafana alert files and reloads provisioning. Run it on the product host from its checkout after updating the monitoring files. It never rebuilds images or restarts application containers. Do not run it for a product whose monitoring is disabled.

The helper backs up runtime provisioning under `/var/backups/mentoring-alerting`, preserves the mounted directory, and verifies active rules, Telegram routing and templates through Grafana API. Failed verification restores the previous runtime files. Grafana must already have its Telegram environment configured. Before recreating an old Grafana to add that environment, preserve its `/var/lib/grafana` data; Mock, Platform and Auth use `tmp/grafana/data` for persistent storage.

Application errors, outbound HTTP failures, individual HTTP 5xx events and raw failure-log windows use a receiver with recovery messages disabled. State-based infrastructure rules keep their recovery notifications. Docker `compose_service` is normalized into the service label used in messages and incident log links. The generic action paragraph is omitted.

Verify templates and incident links with `sh docker/grafana/tests/notification-message-test.sh`. Set `ALERT_QUERIES_FILE` to export the actual rendered LogQL links for parser validation against the product Loki. Tests do not send Telegram messages.
