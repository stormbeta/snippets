#!/usr/bin/env bash

# homebrew makes it a huge pain to pin a specific version if you don't already have it installed

set -eo pipefail

formula="$1"
shift 1

while getopts ":cvh" opt; do
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

function find-commit {
  local formula="$1"
  local version="$2"
  pushd "$(brew --prefix)/Homebrew/Library/Taps/homebrew/homebrew-core"
  formula_path="Formula/${formula}.rb"
  result="$(git log --pretty=format:%H  --grep "${version}" -- "$formula_path" | head -n 1)"
  git checkout "$result" -- "$formula_path"
  popd
}

function version-override {
  local formula="$1"
  local commit="$2"
  pushd "$(brew --prefix)/Homebrew/Library/Taps/homebrew/homebrew-core"
  formula_path="Formula/${formula}.rb"
  wget "https://raw.githubusercontent.com/Homebrew/homebrew-core/${commit}/Formula/kubernetes-cli.rb" -O "$formula_path"
  brew uninstall "$formula" --ignore-dependencies
  brew install "$formula"
  brew link "$formula"
  brew pin "$formula"
  git checkout -- "$formula_path"
  popd
}

if brew list --versions "$formula" | grep "$version" &>/dev/null; then
  echo "Version ${version} already installed"
  brew switch "$formula" "$version"
else
  if [[ -z "$commit" ]]; then
    commit="$(find-commit "$formula" "$commit")"
  fi
  version-override "$formula" "$commit"
fi
