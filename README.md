# GDriveVault

GDriveVault is a native SwiftUI macOS app that orchestrates parallel `rclone` runs across multiple configured Google Drive remotes. It is designed for large transfers where one remote/account hits Google Drive transfer limits.

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
swift run GDriveVault
```

## Package for another Mac

Build a release `.app` bundle and zip it for install:

```sh
./scripts/package-mac.sh
```

The script writes:

- `dist/GDriveVault.app`
- `dist/GDriveVault-mac-arm64-1.0.0.zip`

Optional version overrides:

```sh
VERSION=1.0.1 BUILD_NUMBER=2 ./scripts/package-mac.sh
```

Copy the zip to the other Mac, unzip it, drag `GDriveVault.app` into `/Applications`, and make sure `rclone` is installed at `/opt/homebrew/bin/rclone` or `/usr/local/bin/rclone`.

## Current behavior

- Discovers remotes via `rclone listremotes`
- Lets you select multiple profiles/remotes
- Separates Dashboard, Sync Settings, and Status into dedicated pages
- Shows live transfer usage on the Dashboard while a run is active
- Parses rclone progress into percent complete, speed, ETA, file counts, and active files
- Selects the profile failover pool inside Sync Settings instead of the app sidebar
- Saves multiple sync jobs locally before running them
- Backs up and restores sync profiles, account usage, and rclone config settings
- Pushes settings backups to GDriveVault Control for remote storage
- Browses remote folders from each profile's default `rclone` root
- Tracks transfer usage against a 750 GB per-profile rolling 24-hour quota window
- Applies each profile's remaining quota window with `rclone --max-transfer`
- Fails over through selected profiles when a run exits before completion
- Stop pauses the active rclone process while GDriveVault stays open
- Cancel Job terminates the current rclone process and halts failover
- Resumes cancelled or incomplete runs by rerunning the same job so rclone skips completed files
- Restores resume context after the app is closed and reopened during an incomplete run
- Saves per-profile rclone log files and a summary after each run
- Runs a bandwidth test before sync starts and reports device internet speed
- Lets users drag files or folders onto the Dashboard for quick uploads
- Checks GDriveVault Control for newer GDriveVault versions
- Sends sync notifications to Google Chat Spaces with an incoming webhook
- Connects to GDriveVault Control for remote status and command polling
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

Use Quick Upload on the Dashboard when someone just needs to drag files or folders into GDriveVault. Quick Upload uses the currently loaded sync profile, or the only saved sync profile when there is exactly one. A single dropped file uploads directly into the selected remote folder; a dropped folder uploads as that folder. Multiple dropped items are copied into a temporary batch folder first, then GDriveVault removes that temporary copy after the upload completes successfully.

The Account Tracker records transferred bytes reported by rclone stats for each profile and persists those updates immediately. Usage is calculated from the last 24 hours when GDriveVault launches. You can manually reset one profile or all profiles if your real Google quota window differs from the app's estimate.

Use Backup to export a `.gdrivevault-backup.json` file containing saved sync profiles, account usage, and the active `rclone.conf` contents. Use Restore to import that backup later; GDriveVault creates a pre-restore backup of the existing rclone config before replacing it.

Use Push Backup to Control Server in Settings > Backup to upload the same backup payload to GDriveVault Control. This includes the active `rclone.conf`, so the control server should be treated as sensitive storage.

When Remote Control is enabled, GDriveVault automatically uploads one settings backup after it confirms a connection to GDriveVault Control. It uploads again after the app reconnects with a new registration token or after remote-control settings are changed.

GDriveVault also accepts the `restore_settings_backup` remote command with a `backup_id` payload. The agent fetches `/api/agent/settings-backups/{backup_id}` with its bearer token, applies the returned settings/rclone payload, and only acknowledges the command after the restore succeeds. Active transfers must be stopped before restore.

If a run is cancelled, fails, or the app is reopened after an incomplete run, GDriveVault offers Restart Sync for the same sync profile. Restart Sync reruns rclone so it can compare the destination and skip files already completed; it does not continue inside a partially uploaded Google Drive file. Use Stop when you need to temporarily halt the active in-progress file without restarting it, and keep GDriveVault open until you resume. Use Cancel Job only when you want to terminate the rclone process.

GDriveVault warns before quitting while a sync is active. Quitting destroys the live rclone process that makes Stop/Resume able to continue an in-progress Google Drive upload.

After each run, GDriveVault writes logs under `~/Library/Application Support/GDriveVault/Run Logs/`. Each run folder contains one rclone log per profile plus `summary.txt` with the job, paths, final status, transferred bytes, and log file locations.

GDriveVault checks the configured GDriveVault Control server at `/api/updates/latest` once on launch and from the Updates toolbar button. Keep `AppVersion.current` in `Sources/GoogleDriveClone/Models.swift` aligned with each build, and update the GDriveVault Control feed when publishing a new build.

Use Chat in the toolbar to connect a Google Chat Space. In Google Chat, open the target Space, create an incoming webhook, and paste the webhook URL into GDriveVault. GDriveVault can post start, completion, failure, and batched completed-file updates. Completed-file batches depend on rclone INFO copied-file log lines.

Google Chat messages use the sync profile's shared-drive/root label instead of internal rclone profile names. New sync jobs default this label to `MrHandPay`, so destinations appear as paths like `MrHandPay/tmp`.

GDriveVault always connects to GDriveVault Control. The registration server is locked to `https://app.gdrivevault.com`; enter a license key or let the app automatically request dashboard approval. If no license key is entered, GDriveVault requests dashboard approval on startup and stores the returned `approval_request_id`. After an operator approves the agent, GDriveVault retries registration with that approval request ID, saves the generated `license_key`, then uses the issued device token for heartbeat status and command polling.

Remote Control heartbeats include live transfer status plus files added, updated, deleted, current file, recent changes, app version, and account usage so GDriveVault Control can show what changed during a sync.

GDriveVault runs a lightweight Cloudflare download test before starting a sync and stores the latest result on the Dashboard. The result is also sent to GDriveVault Control as `internet_download_mbps` and `speed_tested_at`.
