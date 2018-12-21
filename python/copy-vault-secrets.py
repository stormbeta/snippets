#!/usr/bin/env python3
import hvac
import os
from hvac.exceptions import Forbidden
import re
import sys


def copy_secrets(vault: hvac.Client, old_path: str, new_path: str, kv_base: str = 'secret/'):
    def recursive_read(path: str):
        list_path = kv_base + 'metadata/' + path
        data_path = kv_base + 'data/' + path
        try:
            data = vault.read(data_path)
            if data is not None:
                yield path, data['data']['data']
            children_resp = vault.list(list_path)
            if children_resp is None:
                return
            children = children_resp.get('data', {}).get('keys', {})
            if children != {}:
                for child in children:
                    yield from recursive_read(path + child)
        except Forbidden:
            print(f"Path {path} is forbidden!")
            return

    for subpath, secrets in recursive_read(old_path):
        new_data_path: str = kv_base + 'data/' + re.sub('^' + old_path, new_path, subpath)
        print(new_data_path)
        result = vault.write(new_data_path, data=secrets)


vault: hvac.Client = hvac.Client(url=os.getenv("VAULT_ADDR"), token=os.getenv("VAULT_TOKEN"))
if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} OLD_PATH NEW_PATH")
    exit(1)

old_path: str = sys.argv[1]
new_path: str = sys.argv[2]
copy_secrets(vault, old_path=old_path, new_path=new_path)
