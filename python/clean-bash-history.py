#!/usr/bin/env python3

# De-duplicate bash history
# NOTE: creates new file in current directory, does not copy over existing history file itself

import os
existing = list()
unique = 0
dupe = 0
with open(f"{os.getenv('HOME')}/.bash_history", 'r') as hist:
    with open('bash_history', 'wb') as filtered:
        for line in hist.readlines():
            if line not in existing:
                existing.append(line)
                unique += 1
            else:
                dupe += 1
            if(unique % 1000 == 0):
                print(f"Unique so far: {unique}")
        print(f"U: {unique}, D: {dupe}")
        filtered.write("".join(existing).encode('utf-8'))
print(f"unique: {unique}, duplicates: {dupe}")
