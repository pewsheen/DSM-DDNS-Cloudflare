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

# --- DDNS script (embedded) ---
# Must be byte-identical to cloudflareddns.sh in the repo;
# tests/test_install.sh enforces this.
write_ddns_script() {
	cat << 'DDNS_SCRIPT_EOF'
#!/bin/bash
set -e

# DSM Config
username="$1" # Zone ID
password="$2" # API Token
hostname="$3" # www.example.com
ipAddr="$4"   # IPv4 Address

# Cloudflare API-Calls for listing entries
listDnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records?type=A&name=${hostname}"

res=$(curl -s -X GET "$listDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json")
resSuccess=$(echo "$res" | jq -r ".success")

if [[ $resSuccess != "true" ]]; then
	echo "badparam"
	exit 1
fi

recordId=$(echo "$res" | jq -r ".result[0].id")
recordIp=$(echo "$res" | jq -r ".result[0].content")
recordProx=$(echo "$res" | jq -r ".result[0].proxied")

# API-Calls for creating DNS-Entries
createDnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records"

# API-Calls for update DNS-Entries
updateDnsApi="https://api.cloudflare.com/client/v4/zones/${username}/dns_records/${recordId}"

if [[ $recordIp = "$ipAddr" ]]; then
	echo "nochg"
	exit 0
fi

if [[ $recordId = "null" ]]; then
	# Record not exists, create it
	res=$(curl -s -X POST "$createDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"A\",\"name\":\"$hostname\",\"content\":\"$ipAddr\",\"proxied\":false}")
else
	# Record exists, overwrite it
	res=$(curl -s -X PUT "$updateDnsApi" -H "Authorization: Bearer $password" -H "Content-Type:application/json" --data "{\"type\":\"A\",\"name\":\"$hostname\",\"content\":\"$ipAddr\",\"proxied\":$recordProx}")
fi
resSuccess=$(echo "$res" | jq -r ".success")

if [[ $resSuccess = "true" ]]; then
	echo "good"
	exit 0
else
	echo "badparam"
	exit 1
fi
DDNS_SCRIPT_EOF
}

install_ddns_script() {
	local tmp
	tmp="$(mktemp "$(dirname "$TARGET_SCRIPT")/.cloudflareddns.XXXXXX")"
	write_ddns_script > "$tmp"
	chmod 755 "$tmp"
	if [ -f "$TARGET_SCRIPT" ] && cmp -s "$tmp" "$TARGET_SCRIPT"; then
		rm -f "$tmp"
		log "unchanged: $TARGET_SCRIPT"
	else
		mv "$tmp" "$TARGET_SCRIPT"
		log "installed: $TARGET_SCRIPT"
	fi
	chmod 755 "$TARGET_SCRIPT"
}

install_ddns_script

# --- Provider entry ---
register_provider() {
	if grep -q "^\[$PROVIDER_NAME\]" "$PROVIDER_CONF"; then
		log "provider already present in: $PROVIDER_CONF"
		return 0
	fi
	cat >> "$PROVIDER_CONF" << EOF
[$PROVIDER_NAME]
	modulepath=$TARGET_SCRIPT
	queryurl=https://www.cloudflare.com
	website=https://www.cloudflare.com
EOF
	log "provider registered in: $PROVIDER_CONF"
}

register_provider

# --- Persist the installer so a boot-up scheduled task can re-run it ---
persist_installer() {
	local self="${BASH_SOURCE[0]:-}"
	if [ ! -f "$self" ]; then
		log "WARNING: cannot locate installer file (piped invocation?); skipping self-persist"
		return 0
	fi
	local dest="$PERSIST_DIR/install.sh"
	mkdir -p "$PERSIST_DIR"
	if [ -f "$dest" ] && cmp -s "$self" "$dest"; then
		log "persistent copy unchanged: $dest"
	else
		cp "$self" "$dest"
		log "persistent copy updated: $dest"
	fi
	chmod 755 "$dest"
}

persist_installer

log "done."
cat << SUMMARY

One-time setup (if not done already):
  1. DSM Control Panel > Task Scheduler > Create > Triggered Task > User-defined script
       User:    root
       Event:   Boot-up
       Command: bash $PERSIST_DIR/install.sh
     This reapplies the script and provider entry after every DSM update + reboot.
  2. DSM Control Panel > External Access > DDNS > Add
       Service provider: $PROVIDER_NAME
       Hostname:         your record, e.g. www.example.com
       Username/Email:   your Cloudflare Zone ID
       Password:         a Cloudflare API token with Zone > DNS > Edit

Note: credentials entered in the DDNS UI are stored in /etc/ddns.conf, which
survives DSM updates — only the script and provider entry get wiped.
SUMMARY
