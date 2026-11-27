#!/bin/bash
#
# Copyright (C) 2026 ns8-theme contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# class-coverage.sh MODULE_ID
#
# Compare the class names used by the module's dark stylesheet with those in
# the live, stock core.css. The dark stylesheet is generated from a fixed
# ns8-core release; when a core UI release renames classes, more of ours
# stop matching anything. Prints "MISSING TOTAL" on the first line, then the
# missing class names.

set -e
module_id=$1
dark=/home/${module_id}/.config/theme/dark.css
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -sk -b ns8_theme=light https://127.0.0.1/cluster-admin/css/core.css \
    | grep -oE '\.[a-zA-Z][a-zA-Z0-9_-]+' | sort -u > "$tmp/core"
grep -oE '\.[a-zA-Z][a-zA-Z0-9_-]+' "$dark" | sort -u > "$tmp/dark"

echo "$(comm -23 "$tmp/dark" "$tmp/core" | wc -l) $(wc -l < "$tmp/dark")"
comm -23 "$tmp/dark" "$tmp/core"
