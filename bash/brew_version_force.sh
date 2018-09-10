#!/usr/bin/env bash

# homebrew makes it a huge pain to pin a specific version if you don't already have it installed

set -eo pipefail

while getopts "cv:h" opt; do
  case ${opt} in
    h)
      echo "Usage: ./${0} NAME [-v VERSION|-c COMMIT]"
      exit 0
      ;;
    v)
      version="$OPTARG"
      ;;
    c)
      commit="$OPTARG"
      ;;
    *)
      echo "either -c COMMIT or -v VERSION is required" 1>&2
      exit 2
      ;;
  esac
done
shift $((OPTIND -1))
formula="$1"

function find-commit {
  local formula="$1"
  local version="$2"
  pushd "$(brew --prefix)/Homebrew/Library/Taps/homebrew/homebrew-core" &>/dev/null
  formula_path="Formula/${formula}.rb"
  git log --pretty=format:%H  --grep "${version}" -- "$formula_path" | head -n 1
  popd &>/dev/null
}

function version-override {
  local formula="$1"
  local commit="$2"
  echo "Forcing formula ${formula} to ${commit}"
  pushd "$(brew --prefix)/Homebrew/Library/Taps/homebrew/homebrew-core"
  formula_path="Formula/${formula}.rb"
  git checkout "$commit" -- "$formula_path"
  wget "https://raw.githubusercontent.com/Homebrew/homebrew-core/${commit}/Formula/${formula}.rb" -O "$formula_path"
  brew uninstall "$formula" --ignore-dependencies
  brew install "$formula"
  brew pin "$formula"
  git checkout -- "$formula_path"
  popd
}

if [[ -n "$version" ]] && brew list --versions "$formula" | grep "$version" &>/dev/null; then
  echo "Version ${version} already installed"
  brew switch "$formula" "$version"
else
  if [[ -z "$commit" ]]; then
    echo "Searching for commit that contains version..."
    commit="$(find-commit "$formula" "$version")"
    echo "Found ${commit}"
  fi
  version-override "$formula" "$commit"
fi