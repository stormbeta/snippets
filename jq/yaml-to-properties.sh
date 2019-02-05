#!/usr/bin/env bash

yq . "$1" | \
  jq '. as $orig |
    def idx(pth):
      $orig | recurse(.[pth]? // empty) |
      select(type | . != "object" and . != "array");
    $orig | path(.. | select(type | . != "object" and . != "array")) |
    (. | join(".")) + "=" + (. as $p | idx($p[]) | tostring)' -r
