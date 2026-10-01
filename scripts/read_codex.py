#!/usr/bin/env python3
"""Short-lived supported app-server reader. No turns, login, config writes or inference."""
import json, sys, subprocess, select, time
from datetime import datetime, timezone
options = json.load(sys.stdin)
directories = options.get('directories', [])
if not directories or len(directories) > 5 or any(not isinstance(d, str) or not d.startswith('/') for d in directories):
    raise ValueError('Configure 1–5 explicit project paths')
transport = options.get('transport', 'stdio')
if transport not in ('stdio', 'proxy'): raise ValueError('Unsupported transport')
command = [options['binary'], 'app-server', 'proxy'] if transport == 'proxy' else [options['binary'], 'app-server', '--listen', 'stdio://']
process = subprocess.Popen(command, stdin=subprocess.PIPE,
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
sequence = 0
def call(method, params):
    global sequence
    sequence += 1
    process.stdin.write(json.dumps({'id': sequence, 'method': method, 'params': params}) + '\n')
    process.stdin.flush()
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if select.select([process.stdout], [], [], 0.2)[0]:
            line = process.stdout.readline()
            if not line: raise RuntimeError('App-server closed; existing runtime state may require write permission')
            result = json.loads(line)
            if result.get('id') == sequence:
                if 'error' in result: raise RuntimeError('Supported read-only method failed: ' + str(result['error'].get('code')))
                return result['result']
    raise TimeoutError('Codex read timeout')
rows = {}
try:
    call('initialize', {'clientInfo': {'name': 'sidecar', 'title': 'Sidecar', 'version': '0.1.0'}})
    process.stdin.write('{"method":"initialized"}\n'); process.stdin.flush()
    for directory in directories:
        for archived in [False, True]:
            result = call('thread/list', {'cwd': directory, 'limit': 20, 'sortKey': 'updated_at',
                'sortDirection': 'desc', 'sourceKinds': [], 'archived': archived, 'useStateDbOnly': True})
            for entry in result['data']:
                thread = call('thread/read', {'threadId': entry['id'], 'includeTurns': False})['thread']
                rows[thread['id']] = {'id': thread['id'], 'title': thread.get('name') or thread.get('preview') or 'Codex thread',
                    'cwd': directory, 'url': 'codex://threads/' + thread['id'],
                    'updated_at': datetime.fromtimestamp(thread['updatedAt'], timezone.utc).isoformat(),
                    'status': 'History available · live state unknown',
                    'evidence': (thread.get('preview') or 'Thread metadata from supported app-server API')[:1600],
                    'facts': {'archived': archived, 'agent_finished': None, 'task_completed': None, 'history_read': True}}
                if transport == 'proxy':
                    status = thread.get('status', {})
                    kind, flags = status.get('type'), status.get('activeFlags', [])
                    state = ('waiting_approval' if 'waitingOnApproval' in flags else 'waiting_input' if 'waitingOnUserInput' in flags else 'working') if kind == 'active' else {'idle':'idle', 'systemError':'blocked'}.get(kind)
                    if state:
                        rows[thread['id']]['facts']['runtime_signal'] = {'origin':'codex_live_server', 'state':state, 'observed_at':datetime.now(timezone.utc).isoformat(), 'event':'thread/read status', 'evidence':f'Existing server runtime status: {kind}; flags: {flags}'}
    print(json.dumps({'version': 1, 'source': 'codex', 'state': 'unknown', 'complete': False,
        'observed_at': datetime.now(timezone.utc).isoformat(),
        'message': f'Automatic app-server metadata read: {len(rows)} threads; latest 20 active and 20 archived per configured project; archived rows hidden. Separate-runtime coverage and live state unconfirmed.',
        'items': list(rows.values())}))
finally:
    process.terminate()
    try: process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill(); process.wait()
