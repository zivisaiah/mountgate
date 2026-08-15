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
- **Time Machine**: modern macOS refuses NFS/plain-SMB destinations, so MountGate
  manages an APFS **sparsebundle** that Time Machine backs up into:
  - **Staged mode** (default): Time Machine writes to a local sparsebundle; after each
    backup MountGate syncs the changed band files to your cloud remote.
  - **Direct mode** (where supported): the sparsebundle lives on the cloud mount and is
    attached as a local volume.

## Status

Early development. See [milestones](#roadmap) below.

## Roadmap

- [x] M0 — Repo scaffolding
- [ ] M1 — Walking skeleton: mount an S3 bucket in Finder from the menu bar
- [ ] M2 — Time Machine spike: validate Direct & Staged modes on macOS 26
- [ ] M3 — Robust mount lifecycle (supervision, recovery)
- [ ] M4 — Account wizards (S3, SFTP, WebDAV, Google Drive, GCS)
- [ ] M5 — Time Machine productization
- [ ] M6 — Settings & polish
- [ ] M7 — Signed/notarized releases, Homebrew cask

## Building

Requires macOS 14+ and the Swift toolchain (Command Line Tools are enough — no Xcode needed).

```sh
./scripts/fetch-rclone.sh   # download the rclone engine binary
./scripts/build-app.sh      # build dist/MountGate.app
open dist/MountGate.app
```

## License

[MIT](LICENSE). Bundles the [rclone](https://rclone.org) binary (MIT).
