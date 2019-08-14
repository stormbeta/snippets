#/usr/local/bin/bash

# Prompt to remove each Deployment in default namespace of local cluster

deploys="$(kubectl --context docker-for-desktop get deployments --namespace default -ojson | jq '.items[].metadata | .name' -r)"
for deploy in $deploys; do
  read -p "Delete ${deploy}? [Y/n]" -n 1 -r prompt
  echo
  if [[ ! $prompt =~ ^[Yy]$ ]]; then echo "Aborting!" 1>&2; exit 2; fi
  kubectl --context docker-for-desktop --namespace default delete "$deploy"
done
