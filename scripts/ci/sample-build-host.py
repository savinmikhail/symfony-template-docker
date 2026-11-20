#!/usr/bin/env python3
"""Record Linux host counters while BuildKit is running."""
import json
import os
from pathlib import Path
import shutil
import sys
import time


def read(name):
    return Path('/proc', name).read_text()


with open(sys.argv[1], 'a', buffering=1) as output:
    while True:
        sample = {
            'timestamp_ns': time.time_ns(),
            'cpu': read('stat').splitlines()[0].split()[1:],
            'pressure': {kind: read(f'pressure/{kind}') for kind in ('cpu', 'io', 'memory')},
            'network': read('net/dev').splitlines()[2:],
            'disk_available_bytes': shutil.disk_usage(os.getcwd()).free,
        }
        print(json.dumps(sample), file=output)
        time.sleep(5)
