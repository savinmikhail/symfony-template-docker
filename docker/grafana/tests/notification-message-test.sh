#!/bin/sh
set -eu
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
APP_GRAFANA_TELEGRAM_ENABLED=1 APP_GRAFANA_TELEGRAM_CHAT_ID=123 APP_GRAFANA_TELEGRAM_BOT_TOKEN=test-token sh docker/generate-grafana-alerting.sh "$work/contactpoints.yml"
ruby -ryaml -rjson - "$work/contactpoints.yml" > "$work/manifest.json" <<'RUBY'
config = YAML.load_file(ARGV[0])
policy = config.fetch('policies').first
%w[application_error outbound_http http_5xx].each do |kind|
 route = policy.fetch('routes').find { |r| r.fetch('object_matchers', []).any? { |key, op, val| key == 'notification_class' && (op == '=' ? val == kind : Regexp.new(val).match?(kind)) } }
 raise "Missing event route: #{kind}" unless route
 contact = config.fetch('contactPoints').find { |c| c.fetch('name') == route.fetch('receiver') }
 raise 'False recovery enabled' unless contact.fetch('receivers').all? { |r| r.fetch('disableResolveMessage') }
end
contact = config.fetch('contactPoints').find { |c| c.fetch('name') == policy.fetch('receiver') }
raise 'True recovery disabled' unless contact.fetch('receivers').all? { |r| !r.fetch('disableResolveMessage') }
rules = Dir['docker/grafana/provisioning/alerting/*.yml'].flat_map { |p| YAML.load_file(p).fetch('groups', []).flat_map { |g| g.fetch('rules') } }
puts JSON.generate({'Template'=>config.fetch('templates').first.fetch('template'), 'Rules'=>rules})
RUBY
GOCACHE=${GOCACHE:-/tmp/mentoring-alert-go-cache} go run docker/grafana/tests/notification-message-test.go "$work/manifest.json"
