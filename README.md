# SkyVault for Google

SkyVault for Google is a native SwiftUI macOS app that orchestrates parallel `rclone` runs across multiple configured Google Drive remotes. It is designed for large transfers where one remote/account hits Google Drive transfer limits.

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
- Tracks transfer usage against a 750 GB per-profile rolling 24-hour quota window
- Applies each profile's remaining quota window with `rclone --max-transfer`
- Fails over through selected profiles when a run exits before completion
- Stop pauses the active rclone process while SkyVault stays open
- Cancel Job terminates the current rclone process and halts failover
- Resumes cancelled or incomplete runs by rerunning the same job so rclone skips completed files
- Restores resume context after the app is closed and reopened during an incomplete run
- Saves per-profile rclone log files and a summary after each run
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

The Account Tracker records transferred bytes reported by rclone stats for each profile and persists those updates immediately. Usage is calculated from the last 24 hours when SkyVault launches. You can manually reset one profile or all profiles if your real Google quota window differs from the app's estimate.

Use Backup to export a `.skyvault-backup.json` file containing saved sync profiles, account usage, and the active `rclone.conf` contents. Use Restore to import that backup later; SkyVault creates a pre-restore backup of the existing rclone config before replacing it.

If a run is cancelled, fails, or the app is reopened after an incomplete run, SkyVault offers Restart Sync for the same sync profile. Restart Sync reruns rclone so it can compare the destination and skip files already completed; it does not continue inside a partially uploaded Google Drive file. Use Stop when you need to temporarily halt the active in-progress file without restarting it, and keep SkyVault open until you resume. Use Cancel Job only when you want to terminate the rclone process.

SkyVault warns before quitting while a sync is active. Quitting destroys the live rclone process that makes Stop/Resume able to continue an in-progress Google Drive upload.

After each run, SkyVault writes logs under `~/Library/Application Support/SkyVault for Google/Run Logs/`. Each run folder contains one rclone log per profile plus `summary.txt` with the job, paths, final status, transferred bytes, and log file locations.
