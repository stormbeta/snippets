# pyw

Wrapper for setting up the local developer environment for python projects

## Behavior

* Intended to be sourced, e.g. `source pyw`
* Uses system python version by default (prioritizes python3)
* If the wrapper ends in a version, e.g. `pyw3`, it will attempt to use that version if present on the system
* Creates or activates a virtualenv with the same name as the project dir
* Detects and installs dependencies in order of precedence:
  1. **uv** — if `uv.lock` + `pyproject.toml` are present, runs `uv sync`
  2. **poetry** — if `poetry.lock` + `pyproject.toml` are present, runs `poetry install`
  3. **pipenv** — if `Pipfile` is present, runs `pipenv install` (including dev packages)
     * NOTE: pipenv will be coerced to use the created virtualenv, as by default pipenv
             tries to create a mangled virtualenv which complicates integration with other tools
     * NOTE: this script is designed to be sourced. You won't need to use pipenv's wonky
             subshell command, which breaks in many cases due to not being a login shell
  4. **requirements.txt** — plain pip install fallback

## pyw.bashrc

Include this in your bashrc to get an interactive virtualenv switcher when running `pyw`
(not the script, it's a bash function)
