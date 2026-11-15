#!/usr/bin/env bash
# Installs one release of skill-validator or pollen from its GitHub Release,
# refusing any archive whose SHA-256 does not match every reference available.
#
# Usage: install.sh <skill-validator|pollen> [version|latest] [sha256] [bin-dir]
set -euo pipefail

die() {
  echo "::error title=install ${tool:-}::$*" >&2
  exit 1
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

tool=${1:?usage: install.sh <skill-validator|pollen> [version] [sha256] [bin-dir]}
version=${2:-latest}
expected=$(printf '%s' "${3:-}" | tr '[:upper:]' '[:lower:]')
bin_dir=${4:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/skill-action/bin}

case "$tool" in
  skill-validator) repo=agent-ecosystem/skill-validator ;;
  pollen) repo=groupbees/pollen ;;
  *) die "unknown tool '$tool'" ;;
esac

if [ -n "$expected" ] && ! [[ "$expected" =~ ^[0-9a-f]{64}$ ]]; then
  die "the expected SHA-256 must be 64 hexadecimal digits"
fi

if [ "$version" = latest ]; then
  tag=$(gh release view --repo "$repo" --json tagName --jq .tagName)
else
  tag="v${version#v}"
fi
# The tag ends up in file names and in a jq filter below: accept a SemVer tag only.
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || die "'$tag' is not a vX.Y.Z release tag"

os=$(uname -s)
arch=$(uname -m)
case "$arch" in
  x86_64 | amd64) go_arch=amd64 rust_arch=x86_64 ;;
  aarch64 | arm64) go_arch=arm64 rust_arch=aarch64 ;;
  *) die "unsupported architecture '$arch'" ;;
esac
case "$os" in
  Linux) go_os=linux rust_os=unknown-linux-musl ;;
  Darwin) go_os=darwin rust_os=apple-darwin ;;
  *) die "unsupported OS '$os': only Linux and macOS runners are supported" ;;
esac

case "$tool" in
  skill-validator)
    asset="skill-validator_${tag#v}_${go_os}_${go_arch}.tar.gz"
    checksums="skill-validator_${tag#v}_checksums.txt"
    binary_path=skill-validator
    ;;
  pollen)
    target="${rust_arch}-${rust_os}"
    asset="pollen-${target}-${tag}.tar.gz"
    checksums=SHA256SUMS
    binary_path="pollen-${target}-${tag}/pollen"
    ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "Downloading $repo $tag ($asset)"
gh release download "$tag" --repo "$repo" --dir "$work" \
  --pattern "$asset" --pattern "$checksums"

actual=$(sha256_of "$work/$asset")

# Lines are "<sha>  <name>" or "<sha> *<name>" (binary mode).
listed=$(awk -v f="$asset" '$2 == f || $2 == "*" f { print tolower($1) }' "$work/$checksums")
entries=$(printf '%s' "$listed" | grep -c . || true)
[ "$entries" -eq 1 ] || die "$checksums lists $asset $entries times, expected once"
[ "$listed" = "$actual" ] || die "$asset does not match $checksums: got $actual, listed $listed"

# GitHub computes this digest when the asset is uploaded, independently of
# the checksums file the release author publishes next to it.
digest=$(gh api "repos/$repo/releases/tags/$tag" \
  --jq ".assets[] | select(.name == \"$asset\") | .digest // \"\"")
if [ -n "$digest" ]; then
  [ "$digest" = "sha256:$actual" ] || die "$asset does not match GitHub's asset digest: got sha256:$actual, GitHub has $digest"
elif [ -z "$expected" ]; then
  die "GitHub publishes no digest for $asset; pin its SHA-256 ($actual) to install this release"
fi

if [ -n "$expected" ]; then
  [ "$expected" = "$actual" ] || die "$asset does not match the pinned SHA-256: got $actual, expected $expected"
  echo "$asset matches the pinned SHA-256"
elif [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "::notice title=$tool $tag::archive SHA-256 is $actual; pin it with the ${tool}-sha256 input"
fi
echo "$asset verified: sha256 $actual"

mkdir -p "$work/extract" "$bin_dir"
tar -xzf "$work/$asset" -C "$work/extract" --no-same-owner
[ -f "$work/extract/$binary_path" ] || die "$asset holds no $binary_path"
install -m 0755 "$work/extract/$binary_path" "$bin_dir/$tool"

"$bin_dir/$tool" --version

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$bin_dir" >>"$GITHUB_PATH"
fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=$tag"
    echo "sha256=$actual"
  } >>"$GITHUB_OUTPUT"
fi
