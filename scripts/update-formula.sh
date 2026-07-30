#!/usr/bin/env bash
# update-formula.sh — point Formula/mcpp-m.rb at an upstream mcpp release.
#
#   ./scripts/update-formula.sh            # latest published release
#   ./scripts/update-formula.sh 2026.7.30.3
#
# Rewrites exactly four things: `version`, and the three url/sha256 pairs
# (macOS arm64, Linux x86_64, Linux aarch64). Everything else in the formula
# is hand-maintained and left untouched.
#
# The sha256 values come from the `.sha256` sidecars upstream publishes next
# to every asset — the same ones install.sh verifies against. We never
# re-hash a downloaded tarball here: that would attest to what we happened to
# download, not to what upstream released.
set -euo pipefail

REPO="mcpp-community/mcpp"
BASE="https://github.com/${REPO}/releases/download"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORMULA="${ROOT}/Formula/mcpp-m.rb"

# Authenticated API calls when a token is around (CI): the anonymous rate
# limit is 60/h per IP and shared with every other job on the runner.
api() {
    if [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
        curl -fsSL -H "Authorization: Bearer ${GH_TOKEN:-${GITHUB_TOKEN}}" "$@"
    else
        curl -fsSL "$@"
    fi
}

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    # Buffer the response instead of piping into `grep -m1`: an early-exiting
    # reader closes the pipe under curl, which then fails with error 23 and
    # takes the whole `pipefail` pipeline down with it.
    latest_json=$(api "https://api.github.com/repos/${REPO}/releases/latest")
    VERSION=$(printf '%s\n' "$latest_json" | grep '"tag_name"' | head -1 \
              | sed -E 's/.*"v?([^"]+)".*/\1/')
    [[ -n "$VERSION" ]] || { echo "error: cannot resolve latest release" >&2; exit 1; }
fi
VERSION="${VERSION#v}"
echo ":: target version ${VERSION}"

fetch_sha() {  # $1 = platform tag
    local url="${BASE}/v${VERSION}/mcpp-${VERSION}-${1}.tar.gz.sha256"
    local out
    out=$(curl -fsSL "$url") || { echo "error: no sidecar at $url" >&2; return 1; }
    # Sidecar format: "<sha256>  <filename>"
    awk '{print $1; exit}' <<<"$out"
}

SHA_MAC=$(fetch_sha macosx-arm64)
SHA_X64=$(fetch_sha linux-x86_64)
SHA_ARM=$(fetch_sha linux-aarch64)

for s in "$SHA_MAC" "$SHA_X64" "$SHA_ARM"; do
    [[ "$s" =~ ^[0-9a-f]{64}$ ]] || { echo "error: bad sha256 '$s'" >&2; exit 1; }
done
echo ":: macosx-arm64  ${SHA_MAC}"
echo ":: linux-x86_64  ${SHA_X64}"
echo ":: linux-aarch64 ${SHA_ARM}"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# A sha256 line always belongs to the url line directly above it, so the
# rewrite carries the platform forward in `pending` rather than trying to
# identify a bare hash line on its own.
awk -v ver="$VERSION" -v base="$BASE" \
    -v sha_mac="$SHA_MAC" -v sha_x64="$SHA_X64" -v sha_arm="$SHA_ARM" '
function url_for(ind, plat) {
    return ind "url \"" base "/v" ver "/mcpp-" ver "-" plat ".tar.gz\""
}
{
    ind = $0; sub(/[^ \t].*$/, "", ind)
    if ($0 ~ /^[ \t]*version "/)  { print ind "version \"" ver "\""; next }
    if ($0 ~ /^[ \t]*url "/) {
        if ($0 ~ /macosx-arm64\.tar\.gz"/)  { print url_for(ind, "macosx-arm64");  pending = sha_mac; next }
        if ($0 ~ /linux-x86_64\.tar\.gz"/)  { print url_for(ind, "linux-x86_64");  pending = sha_x64; next }
        if ($0 ~ /linux-aarch64\.tar\.gz"/) { print url_for(ind, "linux-aarch64"); pending = sha_arm; next }
    }
    if (pending != "" && $0 ~ /^[ \t]*sha256 "/) { print ind "sha256 \"" pending "\""; pending = ""; next }
    print
}' "$FORMULA" > "$TMP"

# Post-conditions. A silently-unmatched pattern would leave the formula
# pointing at the previous release with a fresh version string — the one
# failure mode that still installs, and installs the wrong thing.
count() { grep -cF "$1" "$TMP" || true; }
[[ "$(count "version \"${VERSION}\"")" == 1 ]] || { echo "error: version not rewritten" >&2; exit 1; }
[[ "$(count "/v${VERSION}/mcpp-${VERSION}-")" == 3 ]] || { echo "error: expected 3 urls at ${VERSION}" >&2; exit 1; }
for s in "$SHA_MAC" "$SHA_X64" "$SHA_ARM"; do
    [[ "$(count "sha256 \"${s}\"")" == 1 ]] || { echo "error: sha256 ${s} not placed" >&2; exit 1; }
done
if command -v ruby >/dev/null 2>&1; then
    ruby -c "$TMP" >/dev/null \
        || { echo "error: rewritten formula is not valid Ruby" >&2; exit 1; }
fi

if cmp -s "$TMP" "$FORMULA"; then
    echo ":: already at ${VERSION} — nothing to do"
    exit 0
fi
cat "$TMP" > "$FORMULA"
echo ":: Formula/mcpp-m.rb updated to ${VERSION}"
