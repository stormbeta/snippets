#!/usr/bin/env bash

# Used once to move an end cap / credit image to the end of a comic file

filename="end.jpg"

for cbz in *.cbz; do
  printf "@ end.jpg\\n@=zz_end.jpg\\n" | zipnote -w "$cbz"
done
