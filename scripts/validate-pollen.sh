#!/usr/bin/env bash
# Runs `pollen validate` on every skill under a directory, as a consumer's
# pollen.yaml selecting that directory would see them.
#
# Usage: validate-pollen.sh <skills-path>
set -euo pipefail

skills_path=${1:?usage: validate-pollen.sh <skills-path>}
skills_path=${skills_path%/}

case "$skills_path" in
  /* | .. | ../* | */.. | */../*)
    echo "::error title=pollen validate::skills-path must be relative and stay inside the working directory: $skills_path" >&2
    exit 1
    ;;
esac

# `repo: local` resolves against the config file's directory, so the config
# has to sit in the working directory, next to the skills it points at.
config=.skill-action-pollen.yaml
[ ! -e "$config" ] || {
  echo "::error title=pollen validate::$config already exists; refusing to overwrite it" >&2
  exit 1
}
trap 'rm -f "$config"' EXIT

quoted=${skills_path//\'/\'\'}
cat >"$config" <<EOF
repos:
  - repo: local
    paths:
      - path: '$quoted'
        recurse: true
EOF

pollen validate --config "$config"
