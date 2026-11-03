import json,os,subprocess,tarfile,tempfile,unittest
from pathlib import Path
SCRIPT=Path(__file__).with_name('deploy-snapshot.sh')
SHA='a'*40
class DeploySnapshotTest(unittest.TestCase):
 def test_rejects_unverified_revision(self):
  r=subprocess.run(['bash',str(SCRIPT),'/tmp/unused','v1.2.3','main','unused','app','{}','php'],capture_output=True)
  self.assertEqual(r.returncode,64)
 def run_deploy(self,fail=False,public_env=True,with_previous=False):
  temp=tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup); root=Path(temp.name); runtime=root/'runtime'; runtime.mkdir(); (runtime/'app').mkdir(); (runtime/'app/.env.local').write_text('PRIVATE=preserved\n'); (runtime/'.env.local').write_text('POSTGRES_PASSWORD=synthetic\n')
  source=root/'source'; source.mkdir(); (source/'docker-compose.yml').write_text('services:\n  php:\n    image: example\n  nginx:\n    image: example\n')
  if public_env:(source/'.env').write_text('APP_ENV=prod\n')
  if with_previous:
   with (source/'docker-compose.yml').open('a') as out:out.write('  notification-outbox-worker:\n    image: example\n')
   previous=root/'previous';(previous/'scripts').mkdir(parents=True)
   (previous/'scripts/snapshot-restart.sh').write_text('#!/bin/sh\ndocker recovered-previous-apps\n')
   (runtime/'.current-release').symlink_to(previous)
  archive=root/'source.tar.gz'
  with tarfile.open(archive,'w:gz') as out:
   for path in source.iterdir():out.add(path,arcname=path.name)
  binary=root/'bin';binary.mkdir(); log=root/'docker.jsonl'; docker=binary/'docker'
  docker.write_text('''#!/usr/bin/env python3
import os,sys,json
with open(os.environ['DOCKER_LOG'],'a') as f:f.write(json.dumps(sys.argv[1:])+'\\n')
a=sys.argv[1:]
if a[:2]==['image','inspect']:print('a'*40)
elif a[0]=='ps': print('old-container')
elif a[0]=='inspect':print('sha256:old-image')
if os.environ.get('FAIL_MIGRATE')=='1' and 'run' in a:sys.exit(1)
''');docker.chmod(0o755)
  env={**os.environ,'PATH':str(binary)+':'+os.environ['PATH'],'DOCKER_LOG':str(log),'FAIL_MIGRATE':'1' if fail else '0'}
  result=subprocess.run(['bash',str(SCRIPT),str(runtime),'v1.2.3',SHA,str(archive),'app',json.dumps({'php':'example/php:'+SHA,'nginx':'example/nginx:'+SHA,'notification-outbox-worker':'example/php:'+SHA}),'php','nginx']+(['notification-outbox-worker'] if with_previous else []),env=env,capture_output=True,text=True,timeout=30)
  return runtime,log,result
 def test_preserves_env_and_migrates_before_switching(self):
  root,log,result=self.run_deploy();self.assertEqual(result.returncode,0,result.stderr)
  stage=root/'.releases'/SHA;self.assertEqual((stage/'app/.env.local').read_text(),'PRIVATE=preserved\n');self.assertEqual((root/'.current-release').resolve(),stage.resolve())
  calls=[json.loads(line) for line in log.read_text().splitlines()];migration=next(i for i,x in enumerate(calls) if 'doctrine:migrations:migrate' in x);switch=next(i for i,x in enumerate(calls) if 'up' in x);self.assertLess(migration,switch)
  config=json.loads((stage/'docker-compose.tag.json').read_text());self.assertNotIn('notification-outbox-worker',config['services'])
 def test_failed_migration_rolls_back_application_images_without_touching_database(self):
  root,log,result=self.run_deploy(True);self.assertNotEqual(result.returncode,0);self.assertFalse((root/'.current-release').exists());calls=[json.loads(line) for line in log.read_text().splitlines()];self.assertTrue(any('rollback-images.json' in ' '.join(x) for x in calls));self.assertFalse(any('db' in x and ('stop' in x or 'down' in x) for x in calls))
 def test_deploys_with_private_environment_without_public_root_dotenv(self):
  root,log,result=self.run_deploy(public_env=False)
  self.assertEqual(result.returncode,0,result.stderr)
  calls=[json.loads(line) for line in log.read_text().splitlines()]
  for call in calls:
   for index,value in enumerate(call[:-1]):
    if value=='--env-file':self.assertTrue(Path(call[index+1]).is_file(),call[index+1])
 def test_rollback_stops_added_workers_before_restoring_previous_release(self):
  root,log,result=self.run_deploy(fail=True,with_previous=True)
  self.assertNotEqual(result.returncode,0)
  calls=[json.loads(line) for line in log.read_text().splitlines()]
  stops=[i for i,call in enumerate(calls) if 'stop' in call and 'notification-outbox-worker' in call]
  self.assertTrue(stops,'Added workers must not survive restoration of an older service set')
  restored=next(i for i,call in enumerate(calls) if call==['recovered-previous-apps'])
  self.assertLess(stops[-1],restored)
if __name__=='__main__':unittest.main()
