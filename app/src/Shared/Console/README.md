# Structured background logs

Worker scripts opt into `APP_LOG_FORMAT=json`. Plain console output is INFO on both stdout and stderr: the stream does not determine severity. Nonzero command exits and rendered exceptions emit explicit ERROR records. Existing JSON records retain severity and context. Multiline messages are escaped in one record. Manual commands and data exports retain their usual format unless explicitly opted in.

Production Monolog uses its JSON stderr handler without a second console copy. PHP-FPM does not decorate worker output. Overview panels parse JSON and filter `level_name` for ERROR, CRITICAL, ALERT and EMERGENCY. Historical text and infrastructure logs remain accessible in drilldown.

Run `php docker/grafana/tests/structured-logging-test.php` to verify console output, exit codes, exceptions and overview queries.
