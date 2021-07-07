#!/usr/bin/env bash

# Instructions:
# Place in bashrc or in PATH as "pyw"
# Run `pyw init` to create a sourceable pyw3 file in the current directory
# Sourcing pyw3 will create or activate a virtualenv named after the project, complete with installed dependencies
# Running plain `pyw` will let you choose among previously created virtualenvs (assumes you have fzf)

function list-virtualenvs {
  (
    cd "${HOME}/.virtualenvs"
    for path in $(find . -type d -maxdepth 1); do
      if [[ "$path" != '.' ]]; then
        basename "$path"
      fi
    done
  )
}

function pyw {
  #local python="${VIRTUAL_ENV##*/}"
  local cmd="$1"
  shift 1
  case "$cmd" in
    init)
      # TODO: automatically move to git repo root first?
      curl -sL https://raw.githubusercontent.com/stormbeta/snippets/master/python/pyw/pyw \
        -o "pyw3" && chmod +x "pyw3" \
        && source pyw3
      ;;
    '')
      if command -v fzf &>/dev/null; then
        # TODO: Include "deactivate" option
        local -r venv="$(list-virtualenvs | fzf -1)"
        if [[ -n "$venv" ]]; then
          source "${HOME}/.virtualenvs/${venv}/bin/activate"
        else
          echo "No virtualenv selected" 1>&2
        fi
      else
        echo "fzf not installed, interactive mode disabled" 1>&2
        exit 1
      fi
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  pyw "$@"
fi
