# MountGate

**Mount any cloud storage as a drive in Finder — and use it for Time Machine backups.**

MountGate is an open-source macOS menu-bar app that mounts cloud storage (Amazon S3 and
S3-compatibles, Google Drive, Google Cloud Storage, SFTP, WebDAV — including Hetzner
Storage Box) as native volumes in Finder, with no kernel extensions.

Its headline feature: **Time Machine backups to your own cloud storage.**

## How it works

- **Engine**: [rclone](https://rclone.org) (MIT) is bundled inside the app and provides
  70+ storage backends, a VFS write cache, and client-side encryption.
- **Mounting**: `rclone nfsmount` runs a localhost NFS server that macOS's *built-in*
  NFS client mounts. No macFUSE, no kexts, no reduced security on Apple Silicon.
- **Time Machine**: modern macOS refuses NFS/plain-SMB destinations — and (verified
  on macOS 26) also rejects disk images backed by network mounts. So MountGate uses
  **Staged mode**: Time Machine backs up into a local APFS sparsebundle, and after
  each backup MountGate syncs only the changed band files to your cloud remote.
  Restore = download the bundle, attach, browse your backups.

## Status

Early development. See [milestones](#roadmap) below.

## Roadmap

- [x] M0 — Repo scaffolding
- [x] M1 — Walking skeleton: mount rclone remotes in Finder from the menu bar
- [x] M2 — Time Machine spike: Direct mode rejected by macOS 26 (error 45); Staged mode validated end-to-end ([results](spikes/RESULTS.md))
- [x] M3 — Robust mount lifecycle (auto-remount with backoff, stale-mount recovery)
- [x] M4 — Account wizards (S3-compatible presets, SFTP, WebDAV, Google Drive & GCS via OAuth)
- [x] M5 — Time Machine productization (setup wizard, auto-sync after backups, restore)
- [x] M6 — Settings (login item, cache limits), disconnect notifications
- [ ] M7 — Signed/notarized releases (needs Apple Developer ID), Homebrew cask — CI with unsigned artifacts is live

## Building

Requires macOS 14+ and the Swift toolchain (Command Line Tools are enough — no Xcode needed).

```sh
./scripts/fetch-rclone.sh   # download the rclone engine binary
./scripts/build-app.sh      # build dist/MountGate.app
open dist/MountGate.app
```

## License

[MIT](LICENSE). Bundles the [rclone](https://rclone.org) binary (MIT).
