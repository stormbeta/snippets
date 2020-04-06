#!/usr/bin/env bash

# Example of how to run things in a loop in parallel, and then wait for them to complete

function do-thing {
  echo "Did thing $1"
}

for i in {1..5}; do
  do-thing $i &
done

for pid in $(jobs -p); do
  wait -nf "$pid"
done
