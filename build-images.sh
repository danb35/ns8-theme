#!/bin/bash

#
# Copyright (C) 2023 Nethesis S.r.l.
# Copyright (C) 2026 ns8-theme contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Terminate on error
set -e

# Prepare variables for later use
images=()
# The image will be pushed to GitHub container registry
repobase="${REPOBASE:-ghcr.io/danb35}"
# Configure the image name
reponame="theme"
# Node.js 25+ no longer ships Corepack, install it from npm
# renovate: datasource=npm packageName=corepack
corepack_version=0.36.0

# renovate: datasource=docker depName=docker.io/nginxinc/nginx-unprivileged
nginx_tag=1.31.7-alpine

# Create a new empty container image
container=$(buildah from scratch)

# Reuse existing nodebuilder-theme container, to speed up builds
if ! buildah containers --format "{{.ContainerName}}" | grep -q nodebuilder-theme; then
    echo "Pulling NodeJS runtime..."
    buildah from --name nodebuilder-theme -v "${PWD}:/usr/src:Z" docker.io/library/node:26.13.1-slim
    buildah run nodebuilder-theme sh -c "npm install -g corepack@${corepack_version} && corepack enable"
fi

echo "Build static UI files with node..."
buildah run \
    --workingdir=/usr/src/ui \
    --env="NODE_OPTIONS=--openssl-legacy-provider" \
    nodebuilder-theme \
    sh -c "yarn install && yarn build"

# Generate the dark override stylesheets from the core UI and ns8-ui-lib
# sources (see theme/build.mjs and DESIGN.md section 5)
# renovate: datasource=github-tags depName=NethServer/ns8-core
ns8_core_ref=3.25.1
echo "Build theme stylesheets with node..."
buildah run \
    --workingdir=/usr/src/theme \
    --env="NS8_CORE_REF=${ns8_core_ref}" \
    nodebuilder-theme \
    sh -c "npm ci --no-audit --no-fund && npm run build"

# Add imageroot directory to the container image
buildah add "${container}" imageroot /imageroot
buildah add "${container}" ui/dist /ui
# Theme files: nginx appends them (imageroot/theme); the shell loads dark.css
# from the module's UI directory, which core serves under /cluster-admin/apps/
buildah add "${container}" theme/dist /imageroot/theme
buildah add "${container}" theme/dist/dark.css /ui/theme/dark.css
# Setup the entrypoint, ask to reserve one TCP port with the label and set a rootless container
buildah config --entrypoint=/ \
    --label="org.nethserver.authorizations=traefik@node:routeadm" \
    --label="org.nethserver.tcp-ports-demand=1" \
    --label="org.nethserver.rootfull=0" \
    --label="org.nethserver.max-per-node=1" \
    --label="org.nethserver.flags=no_data_backup" \
    --label="org.nethserver.images=docker.io/nginxinc/nginx-unprivileged:${nginx_tag}" \
    "${container}"
# Commit the image
buildah commit "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

#
# NOTICE:
#
# It is possible to build and publish multiple images.
#
# 1. create another buildah container
# 2. add things to it and commit it
# 3. append the image url to the images array
#

#
# Setup CI when pushing to Github. 
# Warning! docker::// protocol expects lowercase letters (,,)
if [[ -n "${CI}" ]]; then
    # Set output value for Github Actions
    printf "images=%s\n" "${images[*],,}" >> "${GITHUB_OUTPUT}"
else
    # Just print info for manual push
    printf "Publish the images with:\n\n"
    for image in "${images[@],,}"; do printf "  buildah push %s docker://%s:%s\n" "${image}" "${image}" "${IMAGETAG:-latest}" ; done
    printf "\n"
fi
