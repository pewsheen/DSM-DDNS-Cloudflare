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

# --- DDNS script installation ---

sandbox_setup
bash install.sh > "$TMP/out.log" 2>&1 || die "install run failed"
[ -f "$DDNS_TARGET_SCRIPT" ] || die "DDNS script was not installed"
[ -x "$DDNS_TARGET_SCRIPT" ] || die "DDNS script is not executable"
cmp -s "$DDNS_TARGET_SCRIPT" cloudflareddns.sh || die "embedded script drifted from cloudflareddns.sh — update the heredoc in install.sh"
grep -q "installed: $DDNS_TARGET_SCRIPT" "$TMP/out.log" || die "first run should log 'installed:'"

bash install.sh > "$TMP/out.log" 2>&1 || die "second install run failed"
grep -q "unchanged: $DDNS_TARGET_SCRIPT" "$TMP/out.log" || die "second run should log 'unchanged:'"

echo "stale" > "$DDNS_TARGET_SCRIPT"
bash install.sh > "$TMP/out.log" 2>&1 || die "repair install run failed"
cmp -s "$DDNS_TARGET_SCRIPT" cloudflareddns.sh || die "stale DDNS script was not repaired"
grep -q "installed: $DDNS_TARGET_SCRIPT" "$TMP/out.log" || die "repair run should log 'installed:'"

# --- Provider registration ---

sandbox_setup
bash install.sh > "$TMP/out.log" 2>&1 || die "install run failed"
grep -q "^\[Cloudflare\]" "$DDNS_PROVIDER_CONF" || die "provider entry was not added"
grep -q "modulepath=$DDNS_TARGET_SCRIPT" "$DDNS_PROVIDER_CONF" || die "modulepath should match the target script path"
grep -q "provider registered in: $DDNS_PROVIDER_CONF" "$TMP/out.log" || die "first run should log 'provider registered in:'"
grep -q "^\[USER\]" "$DDNS_PROVIDER_CONF" || die "existing provider entries must be preserved"

bash install.sh > "$TMP/out.log" 2>&1 || die "second install run failed"
[ "$(grep -c "^\[Cloudflare\]" "$DDNS_PROVIDER_CONF")" -eq 1 ] || die "re-run must not duplicate the provider entry"
grep -q "provider already present in: $DDNS_PROVIDER_CONF" "$TMP/out.log" || die "second run should log 'provider already present in:'"

echo "ALL TESTS PASSED"
