import json,os,subprocess,tarfile,tempfile,unittest
from pathlib import Path
SCRIPT=Path(__file__).with_name('deploy-snapshot.sh')
SHA='a'*40
class DeploySnapshotTest(unittest.TestCase):
 def test_rejects_unverified_revision(self):
  r=subprocess.run(['bash',str(SCRIPT),'/tmp/unused','v1.2.3','main','unused','app','{}','php'],capture_output=True)
  self.assertEqual(r.returncode,64)
 def run_deploy(self,fail=False):
  temp=tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup); root=Path(temp.name); runtime=root/'runtime'; runtime.mkdir(); (runtime/'app').mkdir(); (runtime/'app/.env.local').write_text('PRIVATE=preserved\n'); (runtime/'.env.local').write_text('POSTGRES_PASSWORD=synthetic\n')
  source=root/'source'; source.mkdir(); (source/'.env').write_text('APP_ENV=prod\n'); (source/'docker-compose.yml').write_text('services:\n  php:\n    image: example\n  nginx:\n    image: example\n')
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
  result=subprocess.run(['bash',str(SCRIPT),str(runtime),'v1.2.3',SHA,str(archive),'app',json.dumps({'php':'example/php:'+SHA,'nginx':'example/nginx:'+SHA,'notification-outbox-worker':'example/php:'+SHA}),'php','nginx'],env=env,capture_output=True,text=True)
  return runtime,log,result
 def test_preserves_env_and_migrates_before_switching(self):
  root,log,result=self.run_deploy();self.assertEqual(result.returncode,0,result.stderr)
  stage=root/'.releases'/SHA;self.assertEqual((stage/'app/.env.local').read_text(),'PRIVATE=preserved\n');self.assertEqual((root/'.current-release').resolve(),stage.resolve())
  calls=[json.loads(line) for line in log.read_text().splitlines()];migration=next(i for i,x in enumerate(calls) if 'doctrine:migrations:migrate' in x);switch=next(i for i,x in enumerate(calls) if 'up' in x);self.assertLess(migration,switch)
  config=json.loads((stage/'docker-compose.tag.json').read_text());self.assertNotIn('notification-outbox-worker',config['services'])
 def test_failed_migration_rolls_back_application_images_without_touching_database(self):
  root,log,result=self.run_deploy(True);self.assertNotEqual(result.returncode,0);self.assertFalse((root/'.current-release').exists());calls=[json.loads(line) for line in log.read_text().splitlines()];self.assertTrue(any('rollback-images.json' in ' '.join(x) for x in calls));self.assertFalse(any('db' in x and ('stop' in x or 'down' in x) for x in calls))
if __name__=='__main__':unittest.main()
