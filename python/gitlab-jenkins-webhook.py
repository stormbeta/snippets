#!/usr/bin/env python3

import requests
import json
import os
import subprocess
import re
from requests import HTTPError
import sys


"""
Infers gitlab project from current directory's git
Enables jenkins webhook for project
"""


jenkins_uri = 'JENKINS_URI'
gitlab_uri = 'GITLAB_URI'

gitlab_token: str = input("Gitlab API Token: ")

class GitLabClient:
    def __init__(self, base_uri: str, token: str):
        self.session = requests.session()
        self.session.params["private_token"] = token
        self.base_uri = base_uri

    def request(self, method, path, *args, **kwargs):
        return self.session.request(method, self.base_uri + "/api/v4" + path, *args, **kwargs)

    # Returns generator for all objects even if the API endpoint was paginated
    def get_all(self, path: str, **kwargs):
        response: requests.Response = self.get(path, **kwargs)
        yield from self.__lift(response.content)
        while response.headers.get("X-Next-Page", "") != "":
            params = kwargs.get("params", {})
            params["page"] = response.headers["X-Next-Page"]
            kwargs["params"] = params
            response = self.get(path, **kwargs)
            yield from self.__lift(response.content)

    def __lift(self, response_content: str) -> list:
        try:
            data = json.loads(response_content)
            if isinstance(data, list):
                return data
            else:
                return [data]
        except json.decoder.JSONDecodeError as err:
            print(response_content)
            raise err

    def get(self, path, **kwargs):
        try:
            response = self.session.get(self.base_uri + '/api/v4' + path, **kwargs)
            response.raise_for_status()
            return response
        except HTTPError as err:
            print(err)
            raise err


client = GitLabClient(gitlab_uri, gitlab_token)


def set_jenkins_webhook(**params):
    git_uri = bytes.decode(subprocess.check_output(['git', 'config', 'remote.origin.url'])).rstrip()
    project = re.sub('\.git$', '', re.sub('^[^:]+:', '', git_uri))
    print("Project: " + project)
    create_or_update_hook(project, f"{jenkins_uri}/git/notifyCommit?url={git_uri}", **params)


def create_or_update_hook(project: str, url: str, **params):
    encoded = re.sub('/', '%2F', project)
    for hook in client.get_all(f"/projects/{encoded}/hooks"):
        if hook['url'] == url:
            print(f"Updating existing hook id {hook['id']}")
            return client.request('put', f"/projects/{encoded}/hooks/{hook['id']}", {'url': url, **params})
    print("Adding as new hook - note that this won't work unless your Jenkins project has checked out git at least once")
    return client.request('post', f"/projects/{encoded}/hooks", {'url': url, **params})


resp = set_jenkins_webhook(push_events=True)
print(resp)
