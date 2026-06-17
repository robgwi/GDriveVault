# GDriveVault

GDriveVault is a native SwiftUI macOS app for moving large Google Drive datasets with `rclone`. It coordinates multiple Google Drive remotes as a failover pool, tracks each account against Google's 750 GB/day transfer window, and reports status to GDriveVault Control.

The app is designed for a simple operator workflow: configure one or more sync profiles, choose the destination folder, then run saved jobs or drag files/folders onto the Dashboard for quick upload.

## Repository

```text
git@github.com:robgwi/GDriveVault.git
```

## Requirements

- macOS 14 or newer
- Apple Silicon Mac for the current packaged build
- Xcode 26 or newer to build from source
- `rclone` installed at `/opt/homebrew/bin/rclone` or `/usr/local/bin/rclone`
- A GDriveVault Control license or dashboard approval from `https://app.gdrivevault.com`
- One or more Google Drive `rclone` remotes

Install `rclone` with Homebrew:

```sh
brew install rclone
```

## Build From Source

If Xcode has not been used on the Mac yet, accept the license first:

```sh
sudo xcodebuild -license
```

Build and run from the repository:

```sh
swift run GDriveVault
```

Build release mode only:

```sh
swift build -c release
```

## Package For Another Mac

Use the packaging script to build a release `.app` bundle and zip it:

```sh
./scripts/package-mac.sh
```

The script creates:

```text
dist/GDriveVault.app
dist/GDriveVault-mac-arm64-1.1.0.zip
```

Set a release version when packaging:

```sh
VERSION=1.0.1 BUILD_NUMBER=2 ./scripts/package-mac.sh
```

To install on another Mac:

1. Copy `dist/GDriveVault-mac-arm64-1.1.0.zip` to the target Mac.
2. Unzip it.
3. Drag `GDriveVault.app` into `/Applications`.
4. Install `rclone` with Homebrew.
5. Launch GDriveVault and activate it with a license key or approve it from GDriveVault Control.

The packaged app is ad-hoc signed by default. For external distribution, sign with a Developer ID certificate and notarize the zip or DMG.

## Packaging Script Options

The script accepts environment variables:

```text
VERSION=1.1.0
BUILD_NUMBER=1
CONFIGURATION=release
SIGN_IDENTITY=-
```

Example with a Developer ID identity:

```sh
SIGN_IDENTITY="Developer ID Application: Your Company (TEAMID)" VERSION=1.0.1 BUILD_NUMBER=2 ./scripts/package-mac.sh
```

## First Launch And Licensing

GDriveVault is locked to the production control server:

```text
https://app.gdrivevault.com
```

On first launch, the app opens the license screen. The app cannot be used until it is registered.

There are two supported activation paths:

- Enter a license key directly in the app.
- Leave the license key blank and let the app request dashboard approval.

When dashboard approval is used, GDriveVault stores the pending approval request ID, polls the server, receives the generated license key after approval, and then registers the device token for control commands and heartbeat updates.

## rclone Setup

GDriveVault uses the active `rclone.conf` file from the local Mac. It can:

- Open the interactive `rclone config` wizard inside the app.
- Import another `rclone.conf` file.
- Edit profile sections directly.
- Browse remote folders from each profile's configured Google Drive root, team drive, or root folder.

Common config path:

```text
~/.config/rclone/rclone.conf
```

## Sync Profiles

A sync profile stores:

- Local source folder
- Remote destination path
- Selected `rclone` profiles/remotes
- Transfer mode
- Worker/checker counts
- Dry-run setting

Selected profiles form the failover pool. If one profile reaches its remaining transfer limit or exits before completion, GDriveVault can continue with the next selected profile.

## Quick Upload

The Dashboard supports drag-and-drop uploads:

- Drop one file to upload it into the selected destination folder.
- Drop one folder to upload that folder.
- Drop multiple files/folders to stage them into a temporary batch folder first.

Temporary staged uploads are removed after the upload finishes successfully.

## Transfer Modes

- `copy`: Uploads new and changed files without deleting destination files.
- `sync`: Makes the destination match the source, including deletes.
- `bisync`: Two-way sync for advanced cases where both sides may change.

GDriveVault defaults new jobs to dry-run mode. Turn dry-run off only after confirming the source, destination, and selected profiles are correct.

## Usage Tracking

Google Drive accounts have a practical 750 GB/day upload limit. GDriveVault tracks bytes reported by `rclone` for each profile in a rolling 24-hour window and applies each profile's remaining allowance with `rclone --max-transfer`.

You can reset usage in the app if the local estimate differs from the real account state.

## Stop, Resume, And Cancel

- Stop pauses the active `rclone` process while GDriveVault stays open.
- Resume continues the paused process while the app remains open.
- Restart Sync reruns the same job after an interruption so `rclone` can skip completed files.
- Cancel Job terminates the current process and halts failover.

If the app is closed during a transfer, a later restart can skip completed files, but a partially uploaded Google Drive file may restart from the beginning.

## Logs

After each run, GDriveVault writes logs under:

```text
~/Library/Application Support/GDriveVault/Run Logs/
```

Each run folder contains:

- One `rclone` log per profile
- `summary.txt` with job details, paths, status, transferred bytes, and log locations

## Backups And Restore

GDriveVault can export a `.gdrivevault-backup.json` file containing:

- Saved sync profiles
- Account usage records
- Remote-control settings
- Google Chat settings
- Active `rclone.conf` contents

The app can also push settings backups to GDriveVault Control. Treat these backups as sensitive because they may include rclone tokens.

GDriveVault supports the remote `restore_settings_backup` command. The agent fetches the backup from GDriveVault Control, applies it locally, and only acknowledges the command after restore succeeds.

## GDriveVault Control

The desktop app sends heartbeat data to GDriveVault Control, including:

- Device status
- Running job
- Current file
- Transfer speed and ETA
- Files added, updated, and deleted
- Recent changed files
- Account usage
- App version
- Internet speed test result

Supported remote commands include:

```text
start_current
start_job
stop
resume
cancel_job
refresh_remotes
check_updates
restart_app
restore_settings_backup
```

## Google Chat Notifications

GDriveVault can send updates to a Google Chat Space with an incoming webhook.

Supported notifications:

- Sync started
- Progress updates
- Completed file batches
- Sync completed
- Sync failed

Messages use the visible shared-drive/root label instead of internal rclone profile names.

## Updates

GDriveVault checks GDriveVault Control at:

```text
/api/updates/latest
```

Keep `AppVersion.current` in `Sources/GoogleDriveClone/Models.swift` aligned with each packaged release and update the control-server feed when publishing a new build.
