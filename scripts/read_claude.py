#!/usr/bin/env python3
"""Supported, project-scoped history APIs; no inference or raw-store access."""
import json, sys
from datetime import datetime, timezone
from claude_agent_sdk import list_sessions, get_session_messages
options = json.load(sys.stdin)
directories = options.get('directories', [])
if not directories or len(directories) > 5 or any(not isinstance(d, str) or not d.startswith('/') for d in directories):
    raise ValueError('Configure 1–5 explicit absolute project paths')
rows = {}
for directory in directories:
    for session in list_sessions(directory=directory, limit=20, include_worktrees=False):
        messages = get_session_messages(session.session_id, directory=directory, limit=20)
        text = ''
        for message in messages:
            if message.type == 'assistant':
                content = message.message.get('content', [])
                if isinstance(content, str):
                    text = content
                elif isinstance(content, list):
                    text = '\n'.join(c.get('text', '') for c in content if isinstance(c, dict) and c.get('type') == 'text')
        rows[session.session_id] = {'id': session.session_id, 'title': session.summary or 'Claude session',
            'cwd': directory, 'status': 'History available · live state unknown',
            'updated_at': datetime.fromtimestamp(session.last_modified / 1000, timezone.utc).isoformat(),
            'evidence': ('Excerpt from the first 20 history messages; not a completion signal:\n' + text[:1600]) if text else 'SDK session metadata; no assistant text in the bounded read.',
            'next_action': 'Find this session in Claude by its title; task completion is unconfirmed',
            'facts': {'archived': None, 'history_read': True, 'agent_finished': None, 'task_completed': None}}
print(json.dumps({'version': 1, 'source': 'claude', 'state': 'unknown', 'complete': False,
    'observed_at': datetime.now(timezone.utc).isoformat(),
    'message': f'Automatic SDK history read: {len(rows)} sessions, latest 20 per configured project. Desktop coverage and live state unconfirmed.',
    'items': list(rows.values())}))
