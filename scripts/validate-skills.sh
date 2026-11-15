#!/usr/bin/env bash
# Runs `skill-validator check` on each skill under a directory, one skill at a
# time, so releases that only take a single skill directory work too.
#
# Usage: validate-skills.sh <skills-path> [strict: true|false] [allow-dirs]
set -euo pipefail

skills_path=${1:?usage: validate-skills.sh <skills-path> [strict] [allow-dirs]}
strict=${2:-true}
allow_dirs=${3:-}

[ -d "$skills_path" ] || {
  echo "::error title=skill-validator::$skills_path is not a directory" >&2
  exit 1
}

args=(check --emit-annotations -o markdown)
[ "$strict" = true ] && args+=(--strict)
[ -n "$allow_dirs" ] && args+=("--allow-dirs=$allow_dirs")

# A SKILL.md below another skill (an example, a template) is part of that
# skill, not a skill of its own.
skills=()
while IFS= read -r -d '' file; do
  dir=$(dirname "$file")
  nested=false
  for skill in ${skills[@]+"${skills[@]}"}; do
    case "$dir/" in "$skill"/*) nested=true ;; esac
  done
  [ "$nested" = true ] || skills+=("$dir")
done < <(find "$skills_path" -mindepth 1 -type d -name '.*' -prune -o -name SKILL.md -print0 | sort -z)

[ "${#skills[@]}" -gt 0 ] || {
  echo "::error title=skill-validator::no SKILL.md under $skills_path" >&2
  exit 1
}

report=$(mktemp)
trap 'rm -rf "$report"' EXIT

failed=0
for skill in "${skills[@]}"; do
  echo "::group::$skill"
  status=0
  skill-validator "${args[@]}" "$skill" >"$report" || status=$?
  cat "$report"
  echo "::endgroup::"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    grep -v '^::' "$report" >>"$GITHUB_STEP_SUMMARY" || true
  fi
  # Exit code 2 is warnings only; --strict already turns those into 1.
  if [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then
    failed=$((failed + 1))
  fi
done

echo "${#skills[@]} skill(s) checked, $failed failed."
[ "$failed" -eq 0 ]
