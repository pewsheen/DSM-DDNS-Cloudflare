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
