#!/usr/bin/env python3
"""Check generated contact points without using real credentials."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

for generator in sys.argv[1:]:
    with tempfile.TemporaryDirectory(prefix="contactpoint-test-") as directory:
        target = Path(directory) / "contactpoints.yml"
        env = dict(os.environ, APP_GRAFANA_TELEGRAM_ENABLED="1",
                   APP_GRAFANA_TELEGRAM_BOT_TOKEN="fixture-secret-token",
                   APP_GRAFANA_TELEGRAM_CHAT_ID="@fixture_channel")
        subprocess.run(["sh", generator, str(target)], env=env, check=True)
        text = target.read_text()
        assert "fixture-secret-token" not in text
        assert 'chatid: "@fixture_channel"' in text
        assert "type: email" not in text
        assert "type: telegram" in text
        assert "$APP_GRAFANA_TELEGRAM_BOT_TOKEN" in text
        print(f"PASS {generator}: Telegram only; no email contact point or rendered credentials")
