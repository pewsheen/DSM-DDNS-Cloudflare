#!/bin/bash
# Plain-bash tests for install.sh. Runs everything in a temp sandbox.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

die() {
	echo "FAIL: $*" >&2
	exit 1
}

# Fresh sandbox mimicking the DSM paths; exports the env overrides.
sandbox_setup() {
	rm -rf "$TMP/sandbox"
	mkdir -p "$TMP/sandbox/ddns" "$TMP/sandbox/etc.defaults" "$TMP/sandbox/persist"
	printf '[USER]\n\tmodulepath=/sbin/ddns_user.sh\n' > "$TMP/sandbox/etc.defaults/ddns_provider.conf"
	export DDNS_TEST_MODE=1
	export DDNS_TARGET_SCRIPT="$TMP/sandbox/ddns/cloudflareddns.sh"
	export DDNS_PROVIDER_CONF="$TMP/sandbox/etc.defaults/ddns_provider.conf"
	export DDNS_PERSIST_DIR="$TMP/sandbox/persist/ddns-cloudflare"
}

# --- Guard tests ---

sandbox_setup
rm "$DDNS_PROVIDER_CONF"
if bash install.sh > "$TMP/out.log" 2>&1; then
	die "install.sh should exit non-zero when provider conf is missing"
fi
grep -q "ddns_provider.conf" "$TMP/out.log" || die "missing-conf error should mention ddns_provider.conf"

sandbox_setup
rmdir "$TMP/sandbox/ddns"
if bash install.sh > "$TMP/out.log" 2>&1; then
	die "install.sh should exit non-zero when the ddns script directory is missing"
fi

sandbox_setup
bash install.sh > "$TMP/out.log" 2>&1 || die "install.sh should succeed in a valid sandbox"

echo "ALL TESTS PASSED"
