#!/usr/bin/env python3

import re
import subprocess
import sys
import threading
from datetime import datetime, timezone
from queue import Queue

# Required due to Python's standard library lacking any canonical way to refer to timezones directly besides UTC
import pytz

"""
Parse out player login/logout and death/respawn from valheim server logs into something more human-readable
Uses tail -F to track log output, e.g. put this in a tmux session or something
./parse-log.py LOG_FILE
"""

# ZDOID => PlayerName
players = dict()

# PlayerName => boolean: is dead?
death_states = dict()

tailq = Queue(maxsize=10)
def tail():
    # TODO: Default to vhserver location
    logtail = subprocess.Popen(['tail', '-F', '-n', '+250', sys.argv[1]],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    while True:
        line: str = logtail.stdout.readline().decode('utf8')
        tailq.put(line)
        if not line:
            break


def convert_timezone(valheim_date_string: str):
    return datetime.strptime(valheim_date_string, '%m/%d/%Y %H:%M:%S').replace(tzinfo=timezone.utc).astimezone(pytz.timezone('America/Denver'))


threading.Thread(target=tail).start()
while True:
    line: str = tailq.get()
    matcher = re.match(r'(?P<timestamp>.*?): Got character ZDOID from (?P<name>[\w ]+) : (?P<zdoid>-?\d+)', line)
    if matcher is not None:
        m = matcher.groupdict()
        if m['zdoid'] == '0':
            print(f"{convert_timezone(m['timestamp'])}: {m['name']} has died!")
            death_states[m['name']] = True
        else:
            if death_states.get(m['name'], False):
                print(f"{convert_timezone(m['timestamp'])}: {m['name']} respawned")
                death_states[m['name']] = False
            else:
                print(f"{convert_timezone(m['timestamp'])}: {m['name']} LOGIN")
            players[m['zdoid']] = m['name']
    else:
        matcher = re.match(r'(?P<timestamp>.*?): Destroying abandoned non persistent zdo (?P<zdoid>-?\d+)', line)
        if matcher is not None:
            m = matcher.groupdict()
            if m['zdoid'] in players and players[m['zdoid']] is not None:
                print(f"{convert_timezone(m['timestamp'])}: {players[m['zdoid']]} LOG OUT")
            players[m['zdoid']] = None
