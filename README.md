# SkyVault for Google

SkyVault for Google is a native SwiftUI macOS app that orchestrates parallel `rclone` runs across multiple configured Google Drive remotes. It is designed for large transfers where one remote/account hits daily Google Drive transfer limits.

## Requirements

- macOS 14 or newer
- Xcode 26 or newer
- `rclone` installed at `/opt/homebrew/bin/rclone` or `/usr/local/bin/rclone`
- One or more configured `rclone` remotes from `rclone config`

## Run

If Xcode has not been used on this Mac yet, accept the license first:

```sh
sudo xcodebuild -license
```

```sh
swift run SkyVaultForGoogle
```

## Current behavior

- Discovers remotes via `rclone listremotes`
- Lets you select multiple profiles/remotes
- Separates Dashboard, Sync Settings, and Status into dedicated pages
- Shows live transfer usage on the Dashboard while a run is active
- Parses rclone progress into percent complete, speed, ETA, file counts, and active files
- Selects the profile failover pool inside Sync Settings instead of the app sidebar
- Saves multiple sync jobs locally before running them
- Backs up and restores sync profiles, account usage, and rclone config settings
- Browses remote folders from each profile's default `rclone` root
- Tracks daily transfer usage against a 750 GB per-profile limit
- Applies each profile's remaining daily budget with `rclone --max-transfer`
- Fails over through selected profiles when a run exits before completion
- Stops an active transfer by terminating the current rclone process and halting failover
- Resumes cancelled or incomplete runs by rerunning the same job so rclone skips completed files
- Opens and edits the active `rclone.conf` profile sections directly
- Imports profiles from another rclone config file
- Runs the interactive `rclone config` menu inside the app for guided profile setup
- Creates a timestamped config backup before saving profile changes
- Runs one `rclone` process per selected remote
- Supports `copy`, `sync`, and `bisync`
- Streams per-remote logs into the app
- Defaults to dry-run mode

The app intentionally starts in dry-run mode. Turn it off only after confirming the generated paths and selected remotes are correct.

Use the Profiles button to add, rename, delete, import, or edit rclone profile settings. Use Wizard inside Profiles when you want the guided `rclone config` flow for new remotes, OAuth setup, and backend-specific questions.

Use Browse beside Remote path to inspect folders for a selected profile. The browser starts at `profile:` so rclone applies that profile's configured Drive root, team drive, or root folder automatically.

The Account Tracker records transferred bytes reported by rclone stats for each profile and resets automatically by local calendar day. You can manually reset one profile or all profiles if your real Google quota window differs from the local day boundary.

Use Backup to export a `.skyvault-backup.json` file containing saved sync profiles, account usage, and the active `rclone.conf` contents. Use Restore to import that backup later; SkyVault creates a pre-restore backup of the existing rclone config before replacing it.
