#!/usr/bin/env python3

from git import Repo, Commit
from subprocess import Popen, PIPE
import json


# Print commits from head back to base
def track_base(repo: Repo, base: Commit, head: Commit):
    sha: Commit
    for sha in head.parents:
        if(head != base and repo.is_ancestor(base, sha)):
            print(sha)
            track_base(base, sha)


# jq wrapper
def jq(data, *args) -> dict:
    p = Popen(['jq', *args], stdin=PIPE, stdout=PIPE)
    result = p.communicate(input=bytes(json.dumps(data), 'utf-8'))
    return json.loads(result[0])
