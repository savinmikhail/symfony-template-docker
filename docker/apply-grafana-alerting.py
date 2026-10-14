#!/usr/bin/env python3
"""Apply only versioned alert files to an existing local Grafana, with rollback."""
import argparse, base64, json, os, re, shutil, subprocess, tempfile, urllib.request
from datetime import datetime, timezone
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--container', required=True, help='Existing Grafana container; applications are never restarted')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
container = json.loads(subprocess.check_output(['docker', 'inspect', args.container]))[0]
assert Path(container['Config']['Labels']['com.docker.compose.project.working_dir']).resolve() == root, 'Wrong product container'
env = dict(v.split('=', 1) for v in container['Config']['Env'] if '=' in v)
assert env.get('APP_GRAFANA_TELEGRAM_BOT_TOKEN') and env.get('APP_GRAFANA_TELEGRAM_CHAT_ID'), 'Grafana needs Telegram environment; refresh only Grafana with its data preserved first'
mounts = {m['Destination']: Path(m['Source']) for m in container['Mounts']}
runtime = mounts.get('/etc/grafana/provisioning/alerting')
if runtime is None:
    runtime = mounts['/etc/grafana/provisioning'] / 'alerting'
assert runtime.is_dir(), 'Provisioning directory missing'
ip = next(n['IPAddress'] for n in container['NetworkSettings']['Networks'].values() if n['IPAddress'])
credentials = env.get('GF_SECURITY_ADMIN_USER', 'admin') + ':' + env['GF_SECURITY_ADMIN_PASSWORD']
headers = {'Authorization': 'Basic ' + base64.b64encode(credentials.encode()).decode()}

def api(path, method='GET'):
    request = urllib.request.Request('http://' + ip + ':3000' + path, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read()
            return json.loads(data) if data else None
    except urllib.error.HTTPError as error:
        detail = json.loads(error.read())
        raise RuntimeError("Grafana API " + path + ": " + str(detail.get("message", "request failed"))) from None

before = {r['uid'] for r in api('/api/v1/provisioning/alert-rules')}
backup = Path('/var/backups/mentoring-alerting') / root.name / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
backup.mkdir(parents=True, mode=0o700)
for parent in (backup.parent, backup.parent.parent):
    parent.chmod(0o700)
shutil.copytree(runtime, backup / 'alerting')
try:
    # Write files in place: replacing a bind-mounted directory leaves Grafana on an old inode.
    for source in (root / 'docker/grafana/provisioning/alerting').glob('*.yml'):
        if source.name != 'contactpoints.yml' and source.resolve() != (runtime / source.name).resolve():
            shutil.copyfile(source, runtime / source.name)
    contacts = runtime / ('contactpoints.yml' if (runtime / 'contactpoints.yml').exists() else 'contactpoints.generated.yml')
    with tempfile.NamedTemporaryFile() as generated:
        subprocess.run(['sh', str(root / 'docker/generate-grafana-alerting.sh'), generated.name], env={**os.environ, **env, 'APP_GRAFANA_TELEGRAM_ENABLED': '1'}, check=True)
        if contacts.is_relative_to(root / "docker"):
            # Static provisioning remains safe to commit: Grafana expands the env reference.
            text = Path(generated.name).read_text()
            contacts.write_text(re.sub(r'chatid: "[^"\n]*"', 'chatid: "$APP_GRAFANA_TELEGRAM_CHAT_ID"', text))
        else:
            shutil.copyfile(generated.name, contacts)
    api('/api/admin/provisioning/alerting/reload', 'POST')
    after = api('/api/v1/provisioning/alert-rules')
    assert before <= {r['uid'] for r in after}, 'Existing rules disappeared'
    points = api('/api/v1/provisioning/contact-points')
    by_name = {p['name']: p for p in points}
    policy = api('/api/v1/provisioning/policies')
    base = by_name[policy['receiver']]
    assert not base.get('disableResolveMessage', False), 'State recovery was disabled'
    route = next(r for r in policy['routes'] if any(m[0] == 'notification_class' and m[1] == '=~' and 'application_error' in m[2] for m in r.get('object_matchers', [])))
    assert by_name[route['receiver']]['disableResolveMessage'], 'Log events still send recovery'
    # API readback proves rules were imported, rather than merely copied to disk.
    for kind in ('application_error', 'outbound_http', 'http_5xx'):
        rule = next(r for r in after if r.get('labels', {}).get('notification_class') == kind)
        assert rule['annotations'].get('logs_query'), 'Incident link missing'
        assert '%!q' not in rule['annotations']['logs_query'], 'Invalid log filter'
        if kind in ('application_error', 'outbound_http'):
            assert 'default .compose_service' in rule['data'][0]['model']['expr'], 'Compose service label missing'
    templates = api('/api/v1/provisioning/templates')
    assert 'Что делать:' not in json.dumps(templates, ensure_ascii=False), 'Old notification template is active'
    print(json.dumps({'product': root.name, 'status': 'applied', 'rules_before': len(before), 'rules_after': len(after), 'true_recovery': True, 'event_recovery': False, 'backup': str(backup)}, ensure_ascii=False))
except Exception:
    for path in runtime.glob('*.yml'):
        if not (backup / 'alerting' / path.name).exists():
            path.unlink()
    for source in (backup / 'alerting').glob('*.yml'):
        shutil.copyfile(source, runtime / source.name)
    api('/api/admin/provisioning/alerting/reload', 'POST')
    print('Alerting apply failed; previous runtime files restored. Backup:', backup)
    raise
