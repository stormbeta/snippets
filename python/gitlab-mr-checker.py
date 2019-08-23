#!/usr/bin/env python3

from gitlab_client import GitLabClient
import json
from typing import Set, Optional
from git import Commit, InvalidGitRepositoryError, Repo, NoSuchPathError
import coloredlogs
import os
import logging
from datetime import datetime
from dateutil.relativedelta import relativedelta
import argparse
import sys
import requests
from requests.exceptions import HTTPError


"""Rough script to track down pipelines in gitlab triggered by people pushing straight to master instead of using merge requests"""


parser = argparse.ArgumentParser()
parser.add_argument('project', metavar="PROJECT", help='project path in gitlab')
parser.add_argument('months', metavar="N", help="only check N months back, defaults to 3", default=3, nargs='?')
args = vars(parser.parse_args(sys.argv[1:]))
project = args['project']
date = datetime.now() - relativedelta(months=args['months'])


gitlab_host = 'gitlab.example.com'
gitlab = GitLabClient(f"https://{gitlab_host}", '<YOUR TOKEN>')
class GitLabClient:
    def __init__(self, base_uri: str, token: str):
        self.session = requests.session()
        self.session.params["private_token"] = token
        self.base_uri = base_uri

    def get(self, path, **kwargs):
        try:
            response = self.session.get(self.base_uri + '/api/v4' + path, **kwargs)
            response.raise_for_status()
            return response
        except HTTPError as err:
            print(err)
            raise err

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


coloredlogs.install(level=os.getenv('LOGLEVEL', 'INFO'),
                    fmt='%(levelname)s [%(name)s]:\n%(message)s')
log = logging.getLogger(project)
encoded_path = project.replace('/', '%2F')
def clone_or_update(project: str) -> Repo:
    try:
        repo = Repo(project)
        print(repo.git.pull())
    except (InvalidGitRepositoryError, NoSuchPathError) as e:
        repo = Repo.clone_from(f"git@{gitlab_host}:{project}.git", project)
    return repo


log.info(f"Cloning / Pulling {project}")
repo = clone_or_update(project)
mr_heads: dict = {}


log.info("Collecting MRs since " + date.ctime())
# Collect known direct or indirect merge commits
for mr in gitlab.get_all(f"/projects/{encoded_path}/merge_requests?created_after={date.strftime('%Y%m%d')}&view=simple"):
    mr_data = json.loads(gitlab.get(f"/projects/{encoded_path}/merge_requests/{mr['iid']}").text)
    mr_heads[mr_data['diff_refs']['head_sha']] = mr_data['iid']
    if mr_data['state'] == 'merged':
        mr_heads[mr_data['merge_commit_sha']] = mr_data['iid']


def check_mr_heads(commit: Commit) -> Optional:
    if str(commit) in mr_heads:
        return mr_heads[str(commit)]
    elif len(commit.parents) > 1:
        for parent in commit.parents:
            if str(parent) in mr_heads:
                return mr_heads[str(parent)]
        return None
    else:
        return None


for pipeline in gitlab.get_all(f"/projects/{encoded_path}/pipelines?ref=master"):
    pipeline_commit = repo.commit(pipeline['sha'])
    mr_iid = check_mr_heads(pipeline_commit)
    if mr_iid is not None:
        log.info(f"FOUND IN MR {mr_iid} - pipeline status is {pipeline['status']} for {str(pipeline_commit)[0:8]}\n" +
                 f"https://{gitlab_host}/{project}/merge_requests/{mr_iid}")
    else:
        if pipeline["status"] == 'success':
            log.error(f"{str(pipeline_commit)[0:8]} [{pipeline_commit.author}]: {pipeline_commit.summary}\n" +
                      f"NO MR, pipeline completed!")
        else:
            log.warning(f"No MR, but pipeline didn't complete: {pipeline['status']} - {str(pipeline_commit)[0:8]}")
    print(pipeline['web_url'] + "\n")
    if pipeline_commit.committed_datetime.timestamp() < date.timestamp():
        break
