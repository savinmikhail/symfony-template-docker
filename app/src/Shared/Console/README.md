# Structured background logs

Worker scripts opt into `APP_LOG_FORMAT=json`. Console stdout is INFO; stderr and nonzero command exits are ERROR. Existing JSON records retain severity and context. Multiline messages are escaped in one record. Manual commands and data exports retain their usual format unless explicitly opted in.

Production Monolog uses its JSON stderr handler without a second console copy. PHP-FPM does not decorate worker output. Overview panels parse JSON and filter `level_name` for ERROR, CRITICAL, ALERT and EMERGENCY. Historical text and infrastructure logs remain accessible in drilldown.

Run `php docker/grafana/tests/structured-logging-test.php` to verify console output, exit codes, exceptions and overview queries.
