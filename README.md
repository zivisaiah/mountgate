# MountGate — Mount Cloud Storage as a Drive on macOS (Free & Open Source)

**MountGate is a free, open-source macOS menu-bar app that mounts cloud storage — Amazon S3, Google Drive, Google Cloud Storage, SFTP, WebDAV, Cloudflare R2, Backblaze B2, Hetzner Storage Box, MinIO and any S3-compatible service — as native drives in Finder, with no kernel extensions. It can also turn that cloud storage into a Time Machine backup destination.**

An open-source alternative to CloudMounter, Mountain Duck and ExpanDrive, powered by [rclone](https://rclone.org).

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Engine](https://img.shields.io/badge/engine-rclone-orange)
[![CI](https://github.com/zivisaiah/mountgate/actions/workflows/ci.yml/badge.svg)](https://github.com/zivisaiah/mountgate/actions)

---

## What can MountGate do?

- **Mount cloud storage in Finder** — your S3 bucket or Google Drive appears as a normal volume; open, edit, copy and save files with any Mac app.
- **No kernel extensions, no macFUSE** — works on Apple Silicon with full System Integrity Protection. Mounting uses macOS's *built-in* NFS client against a localhost server.
- **Back up your Mac to the cloud with Time Machine** — MountGate manages an APFS sparsebundle that Time Machine backs up into, then syncs only the changed pieces to your cloud storage after each backup.
- **Menu-bar control** — one-click mount/unmount, sync status, and account management from the macOS menu bar.
- **Resilient mounts** — supervised processes, automatic remount with backoff after crashes or network loss, stale-mount recovery at launch.
- **Private by design** — credentials stay on your Mac (rclone config, permissions 0600; passphrases in the macOS Keychain). No telemetry, no account, no server.

## Supported cloud storage providers

| Provider | Protocol / API | Notes |
|---|---|---|
| Amazon S3 | S3 | plus any S3-compatible endpoint |
| Cloudflare R2 | S3 | endpoint preset built in |
| Backblaze B2 | S3 | endpoint preset built in |
| Hetzner Object Storage | S3 | endpoint preset built in |
| MinIO / self-hosted | S3 | endpoint preset built in |
| Google Drive | Google API | browser OAuth sign-in |
| Google Cloud Storage | GCS API | OAuth or service-account JSON |
| Hetzner Storage Box | SFTP | password or SSH key |
| Any SFTP server | SFTP | NAS, VPS, shared hosting |
| Any WebDAV server | WebDAV | Nextcloud, ownCloud, Fastmail, … |

Because the engine is rclone, adding more of its [70+ backends](https://rclone.org/overview/) is straightforward — open an issue for the one you need.

## How does MountGate mount cloud storage without macFUSE or kernel extensions?

Most cloud-drive apps for macOS historically relied on macFUSE, which requires a kernel extension and reduced security on Apple Silicon. MountGate instead uses **`rclone nfsmount`**: rclone runs a tiny NFS server on `localhost` and macOS's built-in NFS client mounts it. The result is a normal network volume in Finder — no kexts, no `csrutil`, no System Settings security exceptions. A VFS write-back cache makes saves fast and uploads happen in the background.

## Can Time Machine back up to cloud storage?

Not directly — modern macOS (Sequoia, Tahoe) rejects NFS and plain SMB destinations, and (as verified on macOS 26) also rejects disk images that live on network mounts. MountGate implements the workaround Apple's own rules allow, **Staged mode**:

1. MountGate creates a local, optionally AES-256-encrypted APFS sparsebundle and registers it with Time Machine.
2. Time Machine backs up into it on its normal schedule.
3. After each backup, MountGate syncs only the **changed band files** to your cloud remote — incremental, resumable uploads.
4. Restore = download the bundle, attach it, and browse your backups in Time Machine as usual.

**Current limitation:** staged mode needs local (or external-disk) staging space roughly the size of your backup set. A **streaming mode** that removes this constraint — a local Time-Machine-advertising SMB service backed by rclone's cache — is the next major milestone ([details](spikes/RESULTS.md)).

## MountGate vs CloudMounter vs Mountain Duck

| | MountGate | CloudMounter | Mountain Duck |
|---|---|---|---|
| Price | **Free** | $29+/year or $74+ | $39+ |
| Open source | **Yes (MIT)** | No | No (Cyberduck core is) |
| Kernel-extension-free | Yes | Yes | Yes |
| Providers | 10+ built-in, 70+ via rclone | 12+ | 30+ |
| Time Machine to cloud | Yes (staged mode) | No | No |
| Client-side encryption | Backup bundles (AES-256); rclone crypt planned | Yes | Yes |

## Installation

Requires macOS 14 Sonoma or later (Apple Silicon or Intel). Until signed releases ship, build from source — no Xcode needed, Command Line Tools are enough:

```sh
git clone https://github.com/zivisaiah/mountgate.git
cd mountgate
./scripts/fetch-rclone.sh   # downloads the SHA256-verified rclone engine
./scripts/build-app.sh      # builds dist/MountGate.app
ditto dist/MountGate.app /Applications/MountGate.app
open /Applications/MountGate.app
```

Signed and notarized releases plus a Homebrew cask are on the roadmap.

## Frequently asked questions

**Is MountGate really free?**
Yes — MIT-licensed, no accounts, no subscriptions, no telemetry. It bundles the MIT-licensed rclone binary.

**Does it work on Apple Silicon (M1/M2/M3/M4/M5)?**
Yes, natively — and on Intel Macs. No security downgrade needed, unlike macFUSE-based tools.

**Where are my files cached?**
In a size-capped local cache (default 10 GB, configurable in Settings). Writes land in the cache instantly and upload in the background.

**Are my credentials safe?**
They're stored in a mode-0600 rclone config on your Mac; backup passphrases go in the macOS Keychain. Nothing is sent anywhere except to your storage provider.

**Can I use my own Google OAuth client?**
Yes — the add-account form has an Advanced section for a custom client ID/secret (recommended, since rclone's shared client is being retired during 2026).

**How do I restore a Time Machine backup made with MountGate?**
Menu bar → Time Machine… → ⋯ → *Restore from Cloud*: MountGate downloads the bundle, attaches it, and your backups browse like any Time Machine disk.

## Architecture

SwiftPM package, no Xcode project. `MountGateCore` (library): rclone engine wrapper, mount supervision, provider catalog, config store, and `TimeMachineKit` (sparsebundle management, backup watcher, cloud sync, restore). `MountGateApp`: AppKit status item + SwiftUI windows. See [spikes/RESULTS.md](spikes/RESULTS.md) for the macOS 26 research that shaped the design.

## Roadmap

- [x] Cloud mounting via `rclone nfsmount` (kext-free), account wizards, OAuth
- [x] Robust mount lifecycle: supervision, auto-remount, recovery
- [x] Time Machine staged mode: setup wizard, auto-sync after backups, restore
- [x] Settings, notifications, CI
- [ ] Signed/notarized releases, Homebrew cask, Sparkle updates
- [ ] **Streaming Time Machine mode** — full-disk cloud backups without local staging space
- [ ] rclone `crypt` client-side encryption for mounts

## Contributing

Issues and pull requests welcome. Run the test suite with `swift test` (17 tests, including end-to-end mount and Time Machine pipeline tests against rclone's in-memory backend).

## License

[MIT](LICENSE) © Ziv Isaiah. Bundles [rclone](https://rclone.org) (MIT).

---

*Keywords: mount S3 as drive macOS, mount Google Drive in Finder, Time Machine cloud backup, rclone GUI for Mac, CloudMounter alternative, Mountain Duck alternative, ExpanDrive alternative, open source cloud mounting, macOS menu bar app, WebDAV Finder, SFTP Finder, no macFUSE.*
