#!/usr/bin/env bash

# Used to merge unmerged changes from a production/main/release branch back into a test/develop branch
# Provides nice oneline summaries of unmerged commits being added in the MR

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 MAIN_BRANCH_NAME TEST_BRANCH_NAME"
  exit 1
fi

export MAIN_BRANCH="${1:-main}"
export TEST_BRANCH="${2:-test}"

# Required in some CI contexts like Jenkins
git fetch origin "+refs/heads/${MAIN_BRANCH}:refs/remotes/origin/${MAIN_BRANCH}"
git fetch origin "+refs/heads/${TEST_BRANCH}:refs/remotes/origin/${TEST_BRANCH}"

UNMERGED="$(git log origin/${MAIN_BRANCH} ^origin/${TEST_BRANCH} --oneline --no-merges)"

# Use remote references only, shouldn't care about local index in CI context and it avoids mixups
if [[ -n "$UNMERGED" ]]; then
  echo "Unmerged commits in ${MAIN_BRANCH}, merging back to ${TEST_BRANCH}..."
  echo -e "$UNMERGED"
  git checkout origin/"${TEST_BRANCH}"
  # NOTE: git doesn't evaluate \n in commit messages
  git merge origin/${MAIN_BRANCH} -F /dev/stdin <<EOF
Automated merge-back of ${MAIN_BRANCH} => ${TEST_BRANCH}

$UNMERGED
EOF
  git push origin "HEAD:${TEST_BRANCH}"
else
  echo "No unmerged commits in ${MAIN_BRANCH}, skipping merge-back"
fi
