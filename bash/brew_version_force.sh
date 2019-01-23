#!/usr/bin/env bash

set -eo pipefail

function usage {
  echo "Usage: ${0} [-v VERSION|-c COMMIT] NAME"
  exit 0
}

if [[ "$#" -lt 2 ]]; then
  usage
  exit 0
fi

while getopts "cv:h" opt; do
  case ${opt} in
    h)
      usage
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

function list-commits {
  local formula="$1"
  pushd "$(brew --prefix)/Homebrew/Library/Taps/homebrew/homebrew-core" &>/dev/null
  formula_path="Formula/${formula}.rb"
  git log --oneline -- "$formula_path" | head -n 10
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
  brew pin "$formula"
else
  if [[ -z "$commit" ]]; then
    echo "Searching for commit that contains version..."
    commit="$(find-commit "$formula" "$version")"
    if [[ -z "$commit" ]]; then
      echo "Commit not found!"
      list-commits "$formula"
      exit 3
    fi
    echo "Found ${commit}"
  fi
  version-override "$formula" "$commit"
fi
