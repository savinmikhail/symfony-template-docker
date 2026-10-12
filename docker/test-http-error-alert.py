#!/usr/bin/env python3
"""Exercise a provisioned LogQL rule against an EMPTY, isolated Loki (never prod).

Usage: python3 docker/test-http-error-alert.py http://127.0.0.1:31190 rule.yml
"""
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

base, filename = sys.argv[1:3]
outbound = "--outbound" in sys.argv[3:]
if urllib.parse.urlparse(base).hostname not in {"localhost", "127.0.0.1"}:
    raise SystemExit("Only an isolated loopback Loki is allowed")
text = Path(filename).read_text()
expression = next(line.split("expr: ", 1)[1].strip().strip("'")
                  for line in text.splitlines() if "expr: " in line)
assert "for: 0s" in text and "params: [0]" in text
selector = expression.split("{", 1)[1].split("}", 1)[0]
labels = dict(re.findall(r'(\w+)="([^"]+)"', selector))
labels.setdefault("compose_service", "nginx")
labels["fixture"] = str(time.time_ns())
query_selector = "{" + selector + ', fixture="' + labels["fixture"] + '"}'
expression = expression.replace("{" + selector + "}", query_selector)


def push(lines):
    now = time.time_ns()
    body = json.dumps({"streams": [{"stream": labels, "values": [
        [str(now + i), line] for i, line in enumerate(lines)
    ]}]}).encode()
    request = urllib.request.Request(base + "/loki/api/v1/push", data=body,
                                     headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=5) as response:
        assert response.status == 204


def count():
    url = base + "/loki/api/v1/query?" + urllib.parse.urlencode({"query": expression})
    with urllib.request.urlopen(url, timeout=5) as response:
        result = json.load(response)["data"]["result"]
    return sum(float(row["value"][1]) for row in result)


def expect(expected):
    for _ in range(30):
        actual = count()
        if actual == expected:
            return
        time.sleep(0.1)
    raise AssertionError(f"expected {expected} HTTP 5xx events, got {actual}")


push(['{"status":200}', '{"status":"429"}',
      '127.0.0.1 - - [fixture] "POST /auth HTTP/1.1" 429 12'])
expect(0)
if outbound:
    push(['{"message":"outbound_http_failure","context":{"status_code":402}}'])
    expect(1)
    push(['{"message":"outbound_http_failure","context":{"status_code":429}}',
          '{"message":"outbound_http_failure","context":{"failure_kind":"transport"}}'])
    expect(3)
    print(f"PASS {filename}: first outgoing 402, 429 and transport; ignores access logs")
else:
    push(['{"status":500,"request_method":"POST"}'])
    expect(1)  # First event: no previous Prometheus sample required.
    push(['{"status":"502","request_method":"GET"}',
          '127.0.0.1 - - [fixture] "GET / HTTP/1.1" 503 12'])
    expect(3)
    print(f"PASS {filename}: first 500 + JSON 502 + combined 503; ignores 200/429")
