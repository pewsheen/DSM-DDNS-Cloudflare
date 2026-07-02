# Single Install Script for DSM Cloudflare DDNS — Design

**Date:** 2026-07-02
**Status:** Approved

## Problem

DSM updates restore `/usr/syno/bin/ddns/` and `/etc.defaults/ddns_provider.conf` to
factory defaults, wiping the custom `cloudflareddns.sh` script and the `[Cloudflare]`
provider entry. The current README requires four manual SSH steps to restore them.
Credentials set in the DSM UI live in `/etc/ddns.conf`, which survives updates, so
only the script and provider entry need reinstalling.

## Goal

One idempotent `install.sh` that restores everything in a single run, plus an
optional one-time DSM Task Scheduler boot task so the fix reapplies automatically
after every DSM update + reboot.

## Decisions

- **Embedded script, no download:** `cloudflareddns.sh` is inlined in `install.sh`
  as a quoted heredoc. No network dependency at install time.
- **Manual run + boot-time self-heal:** the installer copies itself to
  `/usr/local/etc/ddns-cloudflare/install.sh` (`/usr/local` survives DSM updates).
  The user creates a one-time **Boot-up** triggered task in Control Panel →
  Task Scheduler (user `root`) pointing at that path. Scheduled tasks survive DSM
  updates.
- **Consistent path:** the DDNS script installs to
  `/usr/syno/bin/ddns/cloudflareddns.sh` and the provider entry's `modulepath`
  points to the same path (fixes the README's `/sbin/` inconsistency).
- **Source of truth:** `cloudflareddns.sh` remains in the repo standalone; the
  embedded copy in `install.sh` is kept in sync manually. No build step (YAGNI).

## install.sh behavior

All steps are idempotent; safe to re-run any time.

1. **Guards:** must run as root; verify DSM environment (`/usr/syno/bin/ddns`
   directory and `/etc.defaults/ddns_provider.conf` exist); warn if `curl` or
   `jq` are missing.
2. **Install DDNS script:** write the embedded heredoc to
   `/usr/syno/bin/ddns/cloudflareddns.sh` only when the file is missing or its
   content differs (hash compare); `chmod 755`. Report installed / updated /
   unchanged.
3. **Register provider:** append the `[Cloudflare]` block to
   `/etc.defaults/ddns_provider.conf` only if `grep -q '^\[Cloudflare\]'` finds
   no existing entry.
4. **Self-persist:** copy the running installer to
   `/usr/local/etc/ddns-cloudflare/install.sh` when missing or different. If the
   installer is being piped (no readable `$0`), skip with a warning.
5. **Summary:** print what was installed/skipped, the one-time Task Scheduler
   instructions, and a note that credentials live in `/etc/ddns.conf` and are
   never wiped.

**Error handling:** `set -euo pipefail`; clear per-step messages; non-zero exit
on failure so the Task Scheduler can notify on error.

## Provider entry

```
[Cloudflare]
        modulepath=/usr/syno/bin/ddns/cloudflareddns.sh
        queryurl=https://www.cloudflare.com
        website=https://www.cloudflare.com
```

## README changes

Rewrite the setup flow around: download `install.sh` once, run it with sudo,
create the one-time boot task. Keep the Cloudflare parameter and DSM DDNS UI
setup sections. Document where credentials are stored (`/etc/ddns.conf`).

## Testing

- `bash -n` and shellcheck on `install.sh` locally.
- On the NAS: run installer twice (second run must report everything unchanged
  and append nothing); `grep -A3 '^\[Cloudflare\]' /etc.defaults/ddns_provider.conf`
  shows exactly one entry; DDNS "Update now" in the UI succeeds.
