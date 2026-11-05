"""Run the actual shell supervisor with synthetic child paths in a private directory."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

base = Path(__file__).resolve().parents[1]
source = (base / 'root/usr/libexec/minieap-sysu-run').read_text()
with tempfile.TemporaryDirectory(prefix='minieap-runner-') as directory:
    root = Path(directory)
    (root / 'carrier').write_text('1\n')
    fake_auth = root / 'auth'
    fake_auth.write_text('#!/bin/sh\necho $$ > "' + str(root / 'child.pid') + '"\necho "synthetic authentication event"\nwhile :; do sleep 1; done\n')
    fake_auth.chmod(0o755)
    fake_monitor = root / 'monitor'
    fake_monitor.write_text('#!/bin/sh\necho $$ > "' + str(root / 'monitor.pid') + '"\nexec cat\n')
    fake_monitor.chmod(0o755)
    conf = root / 'conf'
    conf.write_text('nic=eth0\n')
    script = source.replace('/sys/class/net/$NIC/carrier', str(root / 'carrier'))
    script = script.replace('/etc/minieap-sysu.conf', str(conf))
    script = script.replace('/usr/sbin/minieap-sysu', str(fake_auth))
    script = script.replace('lua /usr/libexec/minieap-sysu-monitor.lua', str(fake_monitor))
    script = script.replace('/tmp/minieap-sysu-live-', str(root / 'live-'))
    runner = root / 'runner'
    runner.write_text(script)
    proc = subprocess.Popen(['/bin/sh', str(runner)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, start_new_session=True)
    try:
        deadline = time.monotonic() + 5
        while not (root / 'child.pid').exists() or not (root / 'monitor.pid').exists():
            if time.monotonic() > deadline:
                raise AssertionError('Children did not start')
            time.sleep(.05)
        child = int((root / 'child.pid').read_text())
        monitor = int((root / 'monitor.pid').read_text())
        proc.terminate()
        output, errors = proc.communicate(timeout=5)
        assert 'synthetic authentication event' in output
        assert not Path('/proc/' + str(child)).exists(), 'Authentication child left running'
        assert not Path('/proc/' + str(monitor)).exists(), 'Monitor left running'
        assert not list(root.glob('live-*')), 'Session directory was not cleaned'
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
print('PASS: real shell FIFO forwarding, TERM cleanup, no auth/monitor orphan or stale session.')
