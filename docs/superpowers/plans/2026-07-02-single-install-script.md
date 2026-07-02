# Single Install Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One idempotent `install.sh` that restores the Cloudflare DDNS script and provider entry on Synology DSM after updates, self-persists for a boot-time Task Scheduler task, plus a README rewrite.

**Architecture:** A single bash installer with the DDNS script embedded as a quoted heredoc. Real system paths are the defaults; `DDNS_*` environment variables override them so tests run against a temp-dir sandbox with `DDNS_TEST_MODE=1` skipping the root/DSM guards. A plain-bash test script exercises guards, idempotency, and drift between the embedded copy and `cloudflareddns.sh`.

**Tech Stack:** bash, coreutils (`cmp`, `mktemp`, `grep`). No external test framework — `tests/test_install.sh` is plain bash. Verification via `bash -n` and `shellcheck` (if installed).

## Global Constraints

- Target DDNS script path: `/usr/syno/bin/ddns/cloudflareddns.sh` (default of `DDNS_TARGET_SCRIPT`)
- Provider conf: `/etc.defaults/ddns_provider.conf` (default of `DDNS_PROVIDER_CONF`); the installer must NEVER create this file — its absence means "not a DSM box"
- Persist dir: `/usr/local/etc/ddns-cloudflare` (default of `DDNS_PERSIST_DIR`)
- Provider entry name: `[Cloudflare]`; `modulepath` must equal the target script path (fixes the old `/sbin/` inconsistency)
- `install.sh` uses `set -euo pipefail` and is idempotent — a second run changes nothing and appends nothing
- The embedded heredoc must be byte-identical to `cloudflareddns.sh` (a test enforces this)
- Log lines are prefixed `[ddns-install]`
- Commit after each task

---

### Task 1: Installer skeleton with guards + test harness

**Files:**
- Create: `install.sh`
- Test: `tests/test_install.sh`

**Interfaces:**
- Produces: `install.sh` honoring env vars `DDNS_TARGET_SCRIPT`, `DDNS_PROVIDER_CONF`, `DDNS_PERSIST_DIR`, `DDNS_TEST_MODE`; helper functions `log`, `fail` used by all later tasks. `tests/test_install.sh` with `sandbox_setup` helper that later tasks extend.

- [ ] **Step 1: Write the failing test**

Create `tests/test_install.sh`:

```bash
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
```

Make it executable: `chmod +x tests/test_install.sh`

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_install.sh`
Expected: FAIL — `install.sh: No such file or directory` (the first `bash install.sh` invocation succeeds/fails wrongly; the harness dies before "ALL TESTS PASSED")

- [ ] **Step 3: Write minimal implementation**

Create `install.sh`:

```bash
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
```

Make it executable: `chmod +x install.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_install.sh`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Syntax check and commit**

```bash
bash -n install.sh && bash -n tests/test_install.sh
git add install.sh tests/test_install.sh
git commit -m "feat: add install.sh skeleton with DSM guards and test harness"
```

---

### Task 2: Embedded DDNS script installation

**Files:**
- Modify: `install.sh` (insert between the guards block and the final `log "done."`)
- Modify: `tests/test_install.sh` (add tests before the `echo "ALL TESTS PASSED"` line)

**Interfaces:**
- Consumes: `log` helper, `TARGET_SCRIPT` variable from Task 1.
- Produces: `write_ddns_script` (prints the embedded script to stdout) and `install_ddns_script` (installs to `$TARGET_SCRIPT`, mode 755, skips when content identical, logs "installed:" or "unchanged:").

- [ ] **Step 1: Write the failing tests**

In `tests/test_install.sh`, add before `echo "ALL TESTS PASSED"`:

```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_install.sh`
Expected: FAIL with "DDNS script was not installed"

- [ ] **Step 3: Implement the embedded script install**

In `install.sh`, insert between the guards block and `log "done."`:

```bash
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
	tmp="$(mktemp)"
	write_ddns_script > "$tmp"
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
```

IMPORTANT: the heredoc body must be the exact bytes of `cloudflareddns.sh` (tab-indented, trailing newline included). If the test's `cmp` fails, copy the file content again verbatim — do not retype it.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_install.sh`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/test_install.sh
git commit -m "feat: install embedded DDNS script idempotently"
```

---

### Task 3: Provider registration with duplicate guard

**Files:**
- Modify: `install.sh` (insert after the `install_ddns_script` call, before `log "done."`)
- Modify: `tests/test_install.sh` (add tests before the `echo "ALL TESTS PASSED"` line)

**Interfaces:**
- Consumes: `log`, `PROVIDER_CONF`, `PROVIDER_NAME`, `TARGET_SCRIPT` from Tasks 1–2.
- Produces: `register_provider` — appends the `[Cloudflare]` block only when `grep -q "^\[Cloudflare\]"` finds nothing; logs "provider registered in:" or "provider already present in:".

- [ ] **Step 1: Write the failing tests**

In `tests/test_install.sh`, add before `echo "ALL TESTS PASSED"`:

```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_install.sh`
Expected: FAIL with "provider entry was not added"

- [ ] **Step 3: Implement provider registration**

In `install.sh`, insert after the `install_ddns_script` call and before `log "done."`:

```bash
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
```

(The `modulepath`/`queryurl`/`website` lines are tab-indented, matching the format DSM uses for its built-in entries.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_install.sh`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/test_install.sh
git commit -m "feat: register Cloudflare provider with duplicate guard"
```

---

### Task 4: Self-persist and summary output

**Files:**
- Modify: `install.sh` (insert after the `register_provider` call; replace the final `log "done."` with the summary)
- Modify: `tests/test_install.sh` (add tests before the `echo "ALL TESTS PASSED"` line)

**Interfaces:**
- Consumes: `log`, `PERSIST_DIR` from Task 1.
- Produces: `persist_installer` — copies the running installer to `$PERSIST_DIR/install.sh` (mode 755) when missing or different, logs "persistent copy updated:" / "persistent copy unchanged:", and logs a WARNING (without failing) when `$0` is not a readable file (piped invocation). Final summary text printed to stdout.

- [ ] **Step 1: Write the failing tests**

In `tests/test_install.sh`, add before `echo "ALL TESTS PASSED"`:

```bash
# --- Self-persist and summary ---

sandbox_setup
bash install.sh > "$TMP/out.log" 2>&1 || die "install run failed"
[ -f "$DDNS_PERSIST_DIR/install.sh" ] || die "installer was not persisted"
[ -x "$DDNS_PERSIST_DIR/install.sh" ] || die "persisted installer is not executable"
cmp -s "$DDNS_PERSIST_DIR/install.sh" install.sh || die "persisted installer differs from install.sh"
grep -q "persistent copy updated: $DDNS_PERSIST_DIR/install.sh" "$TMP/out.log" || die "first run should log 'persistent copy updated:'"
grep -q "Task Scheduler" "$TMP/out.log" || die "summary should mention Task Scheduler setup"
grep -q "/etc/ddns.conf" "$TMP/out.log" || die "summary should mention where credentials are stored"

bash install.sh > "$TMP/out.log" 2>&1 || die "second install run failed"
grep -q "persistent copy unchanged: $DDNS_PERSIST_DIR/install.sh" "$TMP/out.log" || die "second run should log 'persistent copy unchanged:'"

# Running the persisted copy itself must also work (boot-task scenario).
bash "$DDNS_PERSIST_DIR/install.sh" > "$TMP/out.log" 2>&1 || die "running the persisted copy failed"
grep -q "persistent copy unchanged: $DDNS_PERSIST_DIR/install.sh" "$TMP/out.log" || die "persisted copy run should be a no-op"

# Piped invocation cannot self-persist; must warn but still succeed.
sandbox_setup
bash < install.sh > "$TMP/out.log" 2>&1 || die "piped run should still succeed"
grep -q "WARNING: cannot locate installer file" "$TMP/out.log" || die "piped run should warn about skipping self-persist"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_install.sh`
Expected: FAIL with "installer was not persisted"

- [ ] **Step 3: Implement self-persist and summary**

In `install.sh`, insert after the `register_provider` call:

```bash
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
```

Then replace the final `log "done."` with:

```bash
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_install.sh`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/test_install.sh
git commit -m "feat: self-persist installer and print setup summary"
```

---

### Task 5: README rewrite and final verification

**Files:**
- Modify: `README.md` (full rewrite, content below)

**Interfaces:**
- Consumes: the `install.sh` behavior and paths from Tasks 1–4.
- Produces: user-facing docs; no code interfaces.

- [ ] **Step 1: Replace README.md content**

```markdown
# Synology Cloudflare DDNS Script 📜

**This is modified for my personal usage, which supports only IPv4 (A Record)**

A script to add [Cloudflare](https://www.cloudflare.com/) as a DDNS provider on
a [Synology](https://www.synology.com/) NAS, using the Cloudflare API v4.

DSM updates wipe custom DDNS scripts (`/usr/syno/bin/ddns/`) and provider
entries (`/etc.defaults/ddns_provider.conf`). `install.sh` restores both in one
idempotent run and can be hooked to a boot-up scheduled task so this happens
automatically after every update.

## Tested DSM Version

- DSM 7.3.1-86003 Update 1

## Install

1. Log in to your DSM, go to Control Panel > Terminal & SNMP > Enable SSH
   service, and connect with an administrator account.

   **DISABLE SSH SERVICE AFTER SETUP! IT'S DANGEROUS TO EXPOSE SSH ACCESS**

2. Download and run the installer:

   ```
   wget https://raw.githubusercontent.com/pewsheen/DSM-DDNS-Cloudflare/refs/heads/master/install.sh -O /tmp/ddns-install.sh
   sudo bash /tmp/ddns-install.sh
   ```

   The installer is idempotent — re-running it never duplicates anything. It:

   - installs the embedded DDNS script to `/usr/syno/bin/ddns/cloudflareddns.sh` (skipped if already current)
   - adds the `[Cloudflare]` entry to `/etc.defaults/ddns_provider.conf` (skipped if already present)
   - copies itself to `/usr/local/etc/ddns-cloudflare/install.sh`, which survives DSM updates

3. (Recommended) Make it survive DSM updates automatically: go to Control
   Panel > Task Scheduler > Create > Triggered Task > User-defined script:

   - User: `root`
   - Event: `Boot-up`
   - Command: `bash /usr/local/etc/ddns-cloudflare/install.sh`

   Scheduled tasks survive DSM updates, so after every update + reboot the
   script and provider entry are restored before you notice they were gone.

## Get Cloudflare parameters

1. Go to your domain overview page and copy your Zone ID.
2. Go to your profile > **API Tokens** > **Create Token** with the permission
   `Zone > DNS > Edit`, and copy the API token.

## Set up DDNS in DSM

1. Go to Control Panel > External Access > DDNS > Add
2. Enter the following:
   - Service provider: `Cloudflare`
   - Hostname: `www.example.com`
   - Username/Email: `<Zone ID>`
   - Password Key: `<API Token>`

Credentials entered here are stored in `/etc/ddns.conf`, which survives DSM
updates — you never need to re-enter them.

**DISABLE SSH SERVICE AFTER SETUP! IT'S DANGEROUS TO EXPOSE SSH ACCESS**

## Development

- `cloudflareddns.sh` is the source of truth for the DDNS script; `install.sh`
  embeds a copy of it. If you edit one, update the other to match.
- Run the tests (sandboxed, no root needed): `bash tests/test_install.sh` —
  they fail if the embedded copy drifts from `cloudflareddns.sh`.
```

- [ ] **Step 2: Final verification**

```bash
bash -n install.sh && bash -n tests/test_install.sh
command -v shellcheck > /dev/null && shellcheck install.sh tests/test_install.sh || echo "shellcheck not installed, skipped"
bash tests/test_install.sh
```

Expected: syntax checks pass, shellcheck clean (or skipped), `ALL TESTS PASSED`

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README around single install.sh flow"
```
