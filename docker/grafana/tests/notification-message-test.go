package main

import (
	"bytes"
	"encoding/json"
	"html"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"text/template"
	"time"
)

type Alert struct {
	Status                 string
	Labels, Annotations    map[string]string
	StartsAt, EndsAt       time.Time
	GeneratorURL, PanelURL string
}
type Notification struct {
	ExternalURL string
	Alerts      []Alert
}
type Rule struct {
	UID         string            `json:"uid"`
	Annotations map[string]string `json:"annotations"`
}

func check(ok bool, reason string) {
	if !ok {
		panic(reason)
	}
}
func main() {
	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}
	var manifest struct {
		Template string
		Rules    []Rule
	}
	if err := json.Unmarshal(data, &manifest); err != nil {
		panic(err)
	}
	funcs := template.FuncMap{"reReplaceAll": func(pattern, replacement, value string) string {
		return regexp.MustCompile(pattern).ReplaceAllString(value, replacement)
	}}
	tmpl, err := template.New("root").Funcs(funcs).Parse(manifest.Template)
	if err != nil {
		panic(err)
	}
	queries := map[string]string{}
	start := time.Date(2026, 10, 13, 12, 0, 0, 0, time.UTC)
	for _, rule := range manifest.Rules {
		labels := map[string]string{"service": "processing-worker", "integration": "example.org", "method": "POST", "status_code": "502", "failure_kind": "http_status", "error_kind": "json", "error_severity": "warning", "channel": "app", "severity": "warning", "message_id": "42", "alertname": "test"}
		annotations := map[string]string{}
		for key, source := range rule.Annotations {
			ann, err := template.New("annotation").Parse("{{ $labels := .Labels }}{{ $values := .Values }}" + source)
			if err != nil {
				panic(err)
			}
			var rendered bytes.Buffer
			err = ann.Execute(&rendered, map[string]any{"Labels": labels, "Values": map[string]any{"A": map[string]any{"Value": 7}}})
			if err != nil {
				panic(err)
			}
			annotations[key] = rendered.String()
		}
		queries[rule.UID] = annotations["logs_query"]
		check(annotations["logs_query"] != "", rule.UID+": no log query")
		if rule.UID == "symfony_template_docker_outbound_http_errors" {
			check(strings.Contains(annotations["logs_query"], "{{ .status_code | default \"none\" }}"), "LogQL template consumed as annotation template")
			check(strings.Contains(annotations["description"], "502"), "status missing")
			check(strings.Contains(annotations["description"], "7"), "count missing")
		}
		for _, status := range []string{"firing", "resolved"} {
			alert := Alert{Status: status, Labels: labels, Annotations: annotations, StartsAt: start, EndsAt: start.Add(5 * time.Minute), GeneratorURL: "https://example.org/grafana/alerting/test?orgId=1&x=2"}
			n := Notification{ExternalURL: "https://example.org/grafana/", Alerts: []Alert{alert}}
			var rendered bytes.Buffer
			err := tmpl.ExecuteTemplate(&rendered, "symfony-template-docker.message", n)
			if err != nil {
				panic(err)
			}
			text := rendered.String()
			check(!strings.Contains(text, "<no value>"), "missing template data")
			links := regexp.MustCompile(`<a href="([^"]+)">Открыть логи ошибки</a>`).FindStringSubmatch(text)
			check(len(links) == 2, "log link missing")
			u, err := url.Parse(html.UnescapeString(links[1]))
			if err != nil {
				panic(err)
			}
			check(u.Path == "/grafana/explore", "Grafana subpath broken")
			var left struct {
				Queries []struct{ Expr string }
				Range   map[string]string
			}
			if err := json.Unmarshal([]byte(u.Query().Get("left")), &left); err != nil {
				panic(err)
			}
			check(left.Queries[0].Expr == annotations["logs_query"], "query corrupted in URL")
			check(left.Range["from"] == strconv.FormatInt(start.Add(-10*time.Minute).UnixMilli(), 10), "start must be ten minutes before incident")
			if status == "resolved" {
				check(left.Range["to"] == strconv.FormatInt(start.Add(10*time.Minute).UnixMilli(), 10), "resolved time range must be fixed")
			} else {
				check(left.Range["to"] == "now", "firing time range")
			}
			check(len(text) < 4096, rule.UID+": Telegram message too long")
			n.Alerts = []Alert{alert, alert, alert, alert}
			rendered.Reset()
			if err := tmpl.ExecuteTemplate(&rendered, "symfony-template-docker.message", n); err != nil {
				panic(err)
			}
			check(len([]rune(rendered.String())) < 4096, rule.UID+": grouped Telegram message too long")

		}
	}
	// Legacy log streams may have no Compose service label. Keep the incident
	// readable and its log link usable instead of filtering by a missing value.
	for _, rule := range manifest.Rules {
		if rule.UID != "symfony_template_docker_application_errors" && rule.UID != "symfony_template_docker_outbound_http_errors" {
			continue
		}
		labels := map[string]string{"method": "POST", "integration": "example.org", "status_code": "502", "failure_kind": "http_status", "error_kind": "json", "error_severity": "warning", "channel": "app"}
		for _, key := range []string{"summary", "description", "logs_query"} {
			ann, err := template.New("missing-service").Parse("{{ $labels := .Labels }}{{ $values := .Values }}" + rule.Annotations[key])
			if err != nil {
				panic(err)
			}
			var rendered bytes.Buffer
			if err := ann.Execute(&rendered, map[string]any{"Labels": labels, "Values": map[string]any{"A": map[string]any{"Value": 1}}}); err != nil {
				panic(err)
			}
			check(!strings.Contains(rendered.String(), "<no value>"), rule.UID+": missing service leaked")
			check(!strings.Contains(rendered.String(), "%!"), rule.UID+": missing service formatted into query")
			if key == "logs_query" {
				check(!strings.Contains(rendered.String(), " | service="), "missing service must not exclude incident logs")
			}
		}
	}
	// No raw exception can introduce HTML into Telegram.
	hostile := Alert{Status: "firing", Labels: map[string]string{"severity": "critical"}, Annotations: map[string]string{"summary": "bad <script>& JSON", "description": "<secret>", "action": "<retry>"}}
	var rendered bytes.Buffer
	if err := tmpl.ExecuteTemplate(&rendered, "symfony-template-docker.message", Notification{Alerts: []Alert{hostile, hostile, hostile, hostile}}); err != nil {
		panic(err)
	}
	check(!strings.Contains(rendered.String(), "<script>"), "HTML not escaped")
	check(!strings.Contains(rendered.String(), "Что делать:"), "Generic action block must not be rendered")
	check(!strings.Contains(rendered.String(), "retry"), "Action annotation must not be rendered")
	check(strings.Contains(rendered.String(), "первые 3 события из 4"), "group output not bounded")
	if path := os.Getenv("ALERT_QUERIES_FILE"); path != "" {
		data, err := json.Marshal(queries)
		if err != nil {
			panic(err)
		}
		if err := os.WriteFile(path, data, 0600); err != nil {
			panic(err)
		}
	}
	println("Notification templates and incident log links passed.")
}
