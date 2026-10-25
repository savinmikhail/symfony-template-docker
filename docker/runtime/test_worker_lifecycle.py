"""Portable TERM contract for the shared polling-loop policy (no Docker/DB)."""
import os
import sys
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest


@unittest.skipUnless(sys.platform == "linux", "Run this Linux container lifecycle contract inside a runtime image")
class WorkerLifecycleTest(unittest.TestCase):
    def test_startup_idle_and_active_shutdown(self):
        helper=Path(__file__).with_name('worker-lifecycle.sh')
        for phase in ['startup','idle','active']:
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as folder:
                state=Path(folder)/'state'
                script='''. "$LIFECYCLE"
if [ "$PHASE" = startup ]; then echo ready > "$STATE"; worker_sleep 300; fi
while [ "$worker_shutdown" -eq 0 ]; do
  worker_run sh -c 'echo started >> "$STATE"; sleep .25; echo finished >> "$STATE"'
  worker_run sh -c 'echo next >> "$STATE"'
  worker_sleep 300
done
exit 0
'''
                process=subprocess.Popen(['sh','-c',script],env={**os.environ,'LIFECYCLE':str(helper),'PHASE':phase,'STATE':str(state)},start_new_session=True)
                try:
                    expected={'startup':'ready','idle':'next','active':'started'}[phase]
                    deadline=time.monotonic()+2
                    while not state.exists() or expected not in state.read_text():
                        if time.monotonic()>deadline: self.fail('worker did not reach '+phase)
                        time.sleep(.005)
                    process.send_signal(signal.SIGTERM)
                    self.assertEqual(0,process.wait(timeout=2))
                    text=state.read_text()
                    if phase=='active':
                        self.assertIn('finished',text)
                        self.assertNotIn('next',text)
                finally:
                    if process.poll() is None: os.killpg(process.pid,signal.SIGKILL)
                    process.wait()

    def test_command_failure_status_survives_wait(self):
        helper=Path(__file__).with_name('worker-lifecycle.sh')
        result=subprocess.run(['sh','-c','. "$LIFECYCLE"; worker_run sh -c "exit 7"'],env={**os.environ,'LIFECYCLE':str(helper)})
        self.assertEqual(7,result.returncode)

    def test_shutdown_blocks_next_business_command(self):
        helper=Path(__file__).with_name('worker-lifecycle.sh')
        with tempfile.TemporaryDirectory() as folder:
            marker=Path(folder)/'unexpected'
            subprocess.run(['sh','-c','. "$LIFECYCLE"; worker_request_shutdown; worker_run touch "$MARKER"'],check=True,env={**os.environ,'LIFECYCLE':str(helper),'MARKER':str(marker)})
            self.assertFalse(marker.exists())

    def test_timer_signal_before_exec_cannot_be_swallowed(self):
        script = '''. "$LIFECYCLE"
WORKER_PID=$$
sleep() {
  kill -TERM "$WORKER_PID"
  command sleep .05
  command sleep "$1"
}
worker_sleep 300
[ "$worker_shutdown" -eq 1 ]
'''
        helper=Path(__file__).with_name('worker-lifecycle.sh')
        process=subprocess.Popen(['sh','-c',script],env={**os.environ,'LIFECYCLE':str(helper)},start_new_session=True)
        try:
            self.assertEqual(0,process.wait(timeout=1))
        finally:
            if process.poll() is None: os.killpg(process.pid,signal.SIGKILL)
            process.wait()


if __name__=='__main__': unittest.main()
