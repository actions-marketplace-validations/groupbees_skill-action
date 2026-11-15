#!/usr/bin/env bash
# Test suite for the action's scripts. Downloads real releases, so it needs
# network access and `gh` authenticated (or GH_TOKEN set).
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bin="$work/bin"
export PATH="$bin:$PATH"
unset GITHUB_PATH GITHUB_STEP_SUMMARY

passed=0
failed=0

check() {
  local expect=$1 label=$2
  shift 2
  local status=0
  "$@" >"$work/out" 2>&1 || status=$?
  if { [ "$expect" = pass ] && [ "$status" -eq 0 ]; } || { [ "$expect" = fail ] && [ "$status" -ne 0 ]; }; then
    echo "ok   - $label"
    passed=$((passed + 1))
  else
    echo "FAIL - $label (exit $status)"
    sed 's/^/       /' "$work/out"
    failed=$((failed + 1))
  fi
}

installed_sha() {
  local tool=$1 version=$2
  GITHUB_OUTPUT="$work/output" "$root/scripts/install.sh" "$tool" "$version" "" "$work/probe" >/dev/null 2>&1
  sed -n 's/^sha256=//p' "$work/output" | tail -n 1
}

for tool in skill-validator pollen; do
  check pass "$tool: latest installs" "$root/scripts/install.sh" "$tool" latest "" "$bin"
  check fail "$tool: unknown version is refused" "$root/scripts/install.sh" "$tool" 0.0.0 "" "$work/nope"
  check fail "$tool: malformed version is refused" "$root/scripts/install.sh" "$tool" '1.0.0/../x' "" "$work/nope"
  check fail "$tool: malformed SHA-256 is refused" "$root/scripts/install.sh" "$tool" latest not-a-sha "$work/nope"
  check fail "$tool: wrong SHA-256 is refused" "$root/scripts/install.sh" "$tool" latest "$(printf '0%.0s' {1..64})" "$work/nope"
  sha=$(installed_sha "$tool" latest)
  check pass "$tool: matching SHA-256 installs" "$root/scripts/install.sh" "$tool" latest "$sha" "$work/pinned"
  upper=$(printf '%s' "$sha" | tr '[:lower:]' '[:upper:]')
  check pass "$tool: SHA-256 is case-insensitive" "$root/scripts/install.sh" "$tool" latest "$upper" "$work/pinned"
done
check pass "skill-validator: explicit version without v installs" "$root/scripts/install.sh" skill-validator 1.6.2 "" "$work/older"
check pass "pollen: explicit version with v installs" "$root/scripts/install.sh" pollen v0.4.0 "" "$work/older"
check fail "unknown tool is refused" "$root/scripts/install.sh" curl latest "" "$work/nope"
[ ! -e "$work/nope" ] || {
  echo "FAIL - a refused install left files behind"
  failed=$((failed + 1))
}

cd "$root/tests/fixtures" || exit 1
check pass "skill-validator: valid skills pass" "$root/scripts/validate-skills.sh" valid/skills
check fail "skill-validator: invalid skills fail" "$root/scripts/validate-skills.sh" invalid/skills
check fail "skill-validator: missing directory fails" "$root/scripts/validate-skills.sh" missing
check pass "pollen: valid skills pass" "$root/scripts/validate-pollen.sh" valid/skills
check fail "pollen: invalid skills fail" "$root/scripts/validate-pollen.sh" invalid/skills
check fail "pollen: absolute path is refused" "$root/scripts/validate-pollen.sh" "$root/tests/fixtures/valid/skills"
check fail "pollen: path escaping the directory is refused" "$root/scripts/validate-pollen.sh" ../fixtures/valid/skills
[ ! -e .skill-action-pollen.yaml ] || {
  echo "FAIL - validate-pollen.sh left its config behind"
  failed=$((failed + 1))
}

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
