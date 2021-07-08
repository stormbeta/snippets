#!/usr/bin/env bash

# Instructions:
# Place in bashrc - this depends on modifying existing shell, and cannot be used as a child process
# Run `pyw init` to create a sourceable pyw file in the current directory
# Sourcing pyw will create or activate a virtualenv named after the project, complete with installed dependencies
# Running plain `pyw` will let you choose among previously created virtualenvs (assumes you have fzf)

function __list-virtualenvs {
  if [[ -d "$1" ]]; then
    (
      cd "$1"
      for path in $(find . -type d -maxdepth 1 2>/dev/null); do
        if [[ "$path" != '.' ]]; then
          echo "$(readlink -f "$path")"
        fi
      done
    )
  fi
}

function pyw-list-virtualenvs {
  __list-virtualenvs "${HOME}/.virtualenvs"
  if command -v poetry &>/dev/null; then
    __list-virtualenvs "$(poetry config virtualenvs.path || true)"
  fi
}

function pyw {
  local cmd="$1"
  shift 1
  case "$cmd" in
    init)
      # TODO: automatically move to git repo root first?
      curl -sL https://raw.githubusercontent.com/stormbeta/snippets/master/python/pyw/pyw \
        -o "pyw" && chmod +x "pyw" \
        && source pyw
      ;;
    use)
      if [[ -e ./pyw ]]; then
        source pyw
      else
        curl -sL https://raw.githubusercontent.com/stormbeta/snippets/master/python/pyw/pyw \
          -o "pyw" && chmod +x "pyw" \
          && source pyw
      fi
      ;;
    '')
      if command -v fzf &>/dev/null; then
        # TODO: Include "deactivate" option
        local -r venv="$(pyw-list-virtualenvs | fzf -1)"
        if [[ -n "$venv" ]]; then
          source "${venv}/bin/activate"
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
