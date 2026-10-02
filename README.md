# YASB Portable Builder — Inspection Edition

This repository is the **inspection stage** for making YASB truly portable.

It does **not** compile or modify YASB yet.

## Why inspect first?

YASB already supports `YASB_CONFIG_HOME`, so its main configuration can be moved away from the normal user profile.

However, current YASB behavior/documentation also uses `%LOCALAPPDATA%\YASB` for runtime state such as systray state and some token/cache files.

Before writing a source patch, the inspection finds every important path writer in the exact current upstream revision.

## Clean fork

Create a clean fork named exactly:

`yasb`

from:

`amnweb/yasb`

Do not put portable changes in that fork.

Your Universal Fork Sync already discovers all forks in your account, so it will keep the fork synchronized automatically.

## Builder repository

Create a normal repository named exactly:

`YASB-Portable-Builder`

Upload this inspection builder there.

## Run

Actions → Inspect YASB for Portability → Run workflow

When it succeeds, download:

`YASB-Portable-Inspection-<commit>`

Upload that artifact to ChatGPT.

The final builder will then replace this temporary inspection edition.
