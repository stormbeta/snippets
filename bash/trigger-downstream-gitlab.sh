#!/usr/bin/env bash

# Triggers downstream gitlab projects (master branch)

if [[ -z "$CI_JOB_TOKEN" ]]; then
  echo "This script can only be ran from inside of a gitlab job because gitlab is special" 1>&2
  exit 1
fi

for project in $*; do
  project_slug="${project//\//%2F}"
  gitlab_uri="${CI_API_V4_URL}/projects/${project_slug}/trigger/pipeline"
  echo "Triggering downstream ${project} via 'POST ${gitlab_uri}"
  curl -X POST --form "token=${CI_JOB_TOKEN}" --form ref=master "${gitlab_uri}"
done

