"""Runs every test against the real mod files, and the release checks. Exit code 0 only if all pass.

python tests/run_all.py            all tests
python tests/run_all.py --release  all tests, then the release checks (preflight.py, a report to read)
"""
import subprocess
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
failed = 0
for name in ['sync_test', 'spear_test', 'torch_test', 'weld_test', 'partcount_test', 'parking_test', 'evasion_test', 'unfazed_test']:
    r = subprocess.run([sys.executable, '-I', str(here / f'{name}.py')], capture_output=True, text=True)
    lines = (r.stdout + r.stderr).strip().splitlines()
    print(f'{name:16} {lines[-1] if lines else "(no output)"}')
    if r.returncode != 0:
        failed += 1
        print('\n'.join('    ' + l for l in lines[-12:]))
if '--release' in sys.argv:
    subprocess.run([sys.executable, '-I', str(here / 'preflight.py')])
print('FAILED: %d' % failed if failed else 'all passed')
sys.exit(1 if failed else 0)
