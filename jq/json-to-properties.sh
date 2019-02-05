#!/usr/bin/env bash

jq_cmd='. as $orig |
    def idx(pth):
      $orig | recurse(.[pth]? // empty) |
      select(type | . != "object" and . != "array");
    $orig | path(.. | select(type | . != "object" and . != "array")) |
    (. | join(".")) + "=" + (. as $p | idx($p[]) | tostring)'

if command -v yq &>/dev/null; then
  # Go-based yq is completely different from the python version
  if yq --version 2>&1 | grep -q 'yq version' >/dev/null; then
    yq r -j "$1" | jq "$jq_cmd" -r
  else
    yq . "$1" | jq "$jq_cmd" -r
  fi
else
  jq "$jq_cmd" -r "$1"
fi
