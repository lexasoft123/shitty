#!/bin/sh
# Copyright (C) 2026 Shitty team
# MIT licensed
# See the file LICENSE.MIT for the full license.
#
# Sets the GitHub Actions secrets .github/workflows/release.yml's
# sign-notarize-darwin job reads for macOS code signing and notarization,
# read live from this repo's local SOPS store (.keys/secrets.enc.yaml —
# see "Local secret store" in dev/docs/macos_signing.md). Requires Admin
# access to the target repository — `gh secret set` enforces that itself
# with its own permission error, not this script — and the ability to
# decrypt that store (the age private key that made it).
#
# Always sets the certificate pair (the store always carries
# devid_p12_password); additionally sets the ASC pair when the store also
# carries asc_key_id/asc_issuer_id/asc_key_p8 — older stores, and this one
# as of this writing, do not, since the App Store Connect API key here is
# still one reused from elsewhere rather than dedicated to this repo.
#
# usage: set_macos_signing_secrets.sh [--repo OWNER/NAME]
#
#   --repo   target repository; omit to use gh's own repo detection
#            (the current directory's remote)
set -eu

repo=

usage() {
    echo "usage: $(basename "$0") [--repo OWNER/NAME]" >&2
    exit 64
}

while [ $# -gt 0 ]; do
    case "$1" in
        --repo) repo=$2; shift 2 ;;
        -h|--help) usage ;;
        *) usage ;;
    esac
done

command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
command -v sops >/dev/null || { echo "sops is not installed (brew install sops)" >&2; exit 1; }

repo_root=$(cd "$(dirname "$0")/.." && pwd)
store="$repo_root/.keys/secrets.enc.yaml"
[ -f "$store" ] || { echo "no SOPS store found: $store" >&2; exit 1; }
p12="$repo_root/.keys/shitty-devid.p12"
[ -f "$p12" ] || { echo "SOPS store exists but its .p12 is missing: $p12" >&2; exit 1; }

# sops does not reliably fall back to the default age key path (it reports
# only SOPS_AGE_* and SSH locations and fails), so name it explicitly when
# the caller has not.
if [ -z "${SOPS_AGE_KEY_FILE:-}" ] && [ -f "$HOME/.config/sops/age/keys.txt" ]; then
    SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
    export SOPS_AGE_KEY_FILE
fi

umask 077
store_tmpdir=$(mktemp -d)
trap 'rm -rf "$store_tmpdir"' EXIT

# Parsed with python3, not grep/sed: asc_key_p8 is a multi-line PEM, and a
# line-oriented parse of it is how you get a key that is subtly truncated.
# --config /dev/null: the creation rules are for `sops -e`, and letting
# sops hunt for .sops.yaml relative to the CWD makes decryption fail in
# ways that depend on where you happened to be standing.
plain_json=$(sops --config /dev/null -d --output-type json "$store")
STORE_DEVID_P12_PASSWORD=
STORE_ASC_KEY_ID=
STORE_ASC_ISSUER_ID=
STORE_ASC_KEY_P8=
eval "$(
    printf '%s' "$plain_json" | python3 -c '
import json, shlex, sys
d = json.load(sys.stdin)
for key in ("devid_p12_password", "asc_key_id", "asc_issuer_id", "asc_key_p8"):
    if d.get(key):
        print(f"STORE_{key.upper()}={shlex.quote(d[key])}")
'
)"
unset plain_json

[ -n "$STORE_DEVID_P12_PASSWORD" ] || {
    echo "SOPS store is missing devid_p12_password" >&2
    exit 1
}
printf '%s' "$STORE_DEVID_P12_PASSWORD" > "$store_tmpdir/p12-password"
unset STORE_DEVID_P12_PASSWORD

set_secret() {
    name=$1
    if [ -n "$repo" ]; then
        gh secret set "$name" --repo "$repo"
    else
        gh secret set "$name"
    fi
    echo "set $name"
}

base64 -i "$p12" | set_secret APPLE_DEVELOPER_ID_CERTIFICATE_BASE64
printf '%s' "$(cat "$store_tmpdir/p12-password")" | set_secret APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD

if [ -n "$STORE_ASC_KEY_ID" ] && [ -n "$STORE_ASC_ISSUER_ID" ] && [ -n "$STORE_ASC_KEY_P8" ]; then
    printf '%s' "$STORE_ASC_KEY_P8" > "$store_tmpdir/AuthKey.p8"
    base64 -i "$store_tmpdir/AuthKey.p8" | set_secret APP_STORE_CONNECT_API_KEY_BASE64
    printf '%s' "$STORE_ASC_KEY_ID" | set_secret APP_STORE_CONNECT_API_KEY_ID
    printf '%s' "$STORE_ASC_ISSUER_ID" | set_secret APP_STORE_CONNECT_API_ISSUER_ID
else
    echo "SOPS store has no App Store Connect API key yet — set the certificate only" >&2
fi
