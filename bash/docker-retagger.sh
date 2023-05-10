#!/usr/bin/env bash

# Docker retagging script compatible with multiarch images
# NOTE: Assumes registry and tag are specified!

set -eo pipefail

function log {
  echo "$*" 1>&2
}

if [[ $# -lt 2 ]]; then
  log "Usage: ${0} OLD_IMAGE NEW_IMAGE"
  exit 1
fi

old_image="$1"
export old_registry="${old_image%%/*}"
nametag="${old_image#*/}"
export old_name="${nametag%%:*}"
export old_tag="${nametag##*:}"

new_image="$2"
export new_registry="${new_image%%/*}"
nametag="${new_image#*/}"
export new_name="${nametag%%:*}"
export new_tag="${nametag##*:}"

log "Retagging ${old_name}:${old_tag} => ${new_name}:${new_tag}"

export old_ref="${old_registry}/${old_name}"
manifests="$(docker manifest inspect "${old_ref}:${old_tag}")"
mediaType="$(echo "$manifests" | jq -r .mediaType)"

if [[ "$mediaType" == "application/vnd.docker.distribution.manifest.list.v2+json" ]]; then
  arch_tags=''
  if [[ "$old_registry" == "$new_registry" ]]; then
    log "Multi-arch image found: target is in same registry, creating manifest directly"
    arch_tags="$(echo "$manifests" | jq -r \
      '.manifests | map("--amend " + env.old_ref + "@" + .digest) | join(" ")')"
  else
    log "Multi-arch image found with new registry destination, performing manifest dance"
    for manifest in $(echo "$manifests" | jq -c '.manifests[]'); do
      arch_name="$(echo "$manifest"   | jq -r .platform.architecture)"
      arch_digest="$(echo "$manifest" | jq -r .digest)"

      # Pull existing platform-specific image by sha256
      docker pull "${old_ref}@${arch_digest}"

      # Retag/push to new repo using platform-specific placeholder tags
      arch_image="${new_registry}/${new_name}:${new_tag}-${arch_name}"
      log "Mapping ${arch_name} => new ${arch_image}"
      docker tag "${old_registry}/${old_name}@${arch_digest}" "$arch_image"
      docker push "$arch_image"

      # Retrieve sha256 of images in new repo
      new_arch_digest="$(docker inspect "$arch_image" \
        | jq -r '.[0].RepoDigests[]|select(.|startswith(env.new_registry))' \
        | grep -Eo 'sha256:[0-9a-f]+')"
      arch_tags+=" --amend ${new_registry}/${new_name}@${new_arch_digest}"
    done
  fi
  docker manifest create "${new_registry}/${new_name}:${new_tag}" ${arch_tags}
  docker manifest push "${new_registry}/${new_name}:${new_tag}"

else
  log "Non-multiarch image, using simple retag"
  docker pull "${old_registry}/${old_name}:${old_tag}"
  docker tag  "${old_registry}/${old_name}:${old_tag}" \
              "${new_registry}/${new_name}:${new_tag}"
  docker push "${new_registry}/${new_name}:${new_tag}"
fi
