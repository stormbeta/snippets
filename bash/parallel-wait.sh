#!/usr/bin/env bash

# Example of how to run things in a loop in parallel, and then wait for them to complete

function do-thing {
  echo "Did thing $1"
}

export MAX_JOBS=4

for i in {1..20}; do
  while (( $(jobs | wc -l) > $MAX_JOBS )); do
    sleep 1
  done
  do-thing $i &
done

for pid in $(jobs -p); do
  wait -nf "$pid"
done
