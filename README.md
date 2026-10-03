# YASB True-Portable Builder

This repository builds the raw **cx_Freeze** YASB application folder on a GitHub-hosted Windows runner. It deliberately does **not** build or install the MSI.

## Normal build

**Actions → Build YASB Portable → Run workflow → `portable-data`**

The portable source patch redirects YASB-owned state to:

- `Data\Config` — `config.yaml`, `styles.css`, `.env`, `yasb.log`, generated colors, dumps folder path
- `Data\LocalState` — systray state, update timestamp, GitHub OAuth tokens, quick-launch state, Open-Meteo location, widget caches, taskbar state, thumbnails, Cloud files, etc.
- `Data\Temp` — YASB-owned `tempfile` caches such as quick-launch icon caches

The builder also disables:

- official MSI self-update/channel switching;
- registry/Task-Scheduler YASB autostart;
- WER crash-dump registry setup;
- YASB Cloud automatic-backup Scheduled Task creation.

Use the packaged `INSTALL-PORTABLE-STARTUP.cmd` instead.

## YASB Cloud security limitation

YASB Cloud `session.bin` and `vault.bin` still use upstream Windows DPAPI. Their files move with `Data\LocalState\cloud`, but the cached sign-in is intentionally bound to the Windows user/machine. After a clean Windows installation or on another Windows account, sign in to YASB Cloud again.

This preserves upstream credential security instead of weakening it merely to make the login token portable.

## Deliberate Windows interactions that remain

Some YASB features intentionally interact with Windows:

- the first-run wizard can install fonts;
- Control Center can change Windows theme settings;
- widgets read state from other applications such as browsers, VS Code and Windows Terminal.

Those are application features/system dependencies, not YASB's own persistent configuration.

## Diagnostic mode

If a future upstream update breaks the patch, run:

`inspect-source`

and send the resulting `YASB-Portable-Inspection-<commit>` artifact to ChatGPT.
