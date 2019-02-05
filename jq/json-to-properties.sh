#!/usr/bin/env bash

jq_cmd='. as $orig |
    def idx(pth):
      $orig | recurse(.[pth]? // empty) |
      select(type | . != "object" and . != "array");
    $orig | path(.. | select(type | . != "object" and . != "array")) |
    (. | join(".")) + "=" + (. as $p | idx($p[]) | tostring)'

if command -v yq &>/dev/null; then
  yq . "$1" | jq "$jq_cmd" -r
else
  jq "$jq_cmd" -r "$1"
fi
