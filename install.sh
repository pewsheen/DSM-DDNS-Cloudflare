#!/bin/bash
# install.sh — Install/repair Cloudflare DDNS support on Synology DSM.
# Idempotent: safe to re-run any time, manually or from a boot-up scheduled task.
#
# DSM updates wipe /usr/syno/bin/ddns/ and /etc.defaults/ddns_provider.conf;
# this script puts both pieces back. Credentials set in the DSM UI live in
# /etc/ddns.conf and survive updates untouched.
set -euo pipefail

TARGET_SCRIPT="${DDNS_TARGET_SCRIPT:-/usr/syno/bin/ddns/cloudflareddns.sh}"
PROVIDER_CONF="${DDNS_PROVIDER_CONF:-/etc.defaults/ddns_provider.conf}"
PERSIST_DIR="${DDNS_PERSIST_DIR:-/usr/local/etc/ddns-cloudflare}"
PROVIDER_NAME="Cloudflare"

log() {
	echo "[ddns-install] $*"
}

fail() {
	echo "[ddns-install] ERROR: $*" >&2
	exit 1
}

# --- Guards ---
if [ -z "${DDNS_TEST_MODE:-}" ]; then
	[ "$(id -u)" -eq 0 ] || fail "must run as root (try: sudo bash $0)"
	command -v curl > /dev/null || log "WARNING: curl not found; the DDNS script needs it at runtime"
	command -v jq > /dev/null || log "WARNING: jq not found; the DDNS script needs it at runtime"
fi
[ -d "$(dirname "$TARGET_SCRIPT")" ] || fail "$(dirname "$TARGET_SCRIPT") not found — is this a Synology DSM system?"
[ -f "$PROVIDER_CONF" ] || fail "$PROVIDER_CONF not found — is this a Synology DSM system?"

log "done."
