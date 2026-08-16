# M2 Spike Results — Time Machine over MountGate mounts

Machine: macOS 26.6.1 (Tahoe), Apple Silicon, rclone v1.75.0

## Direct mode — sparsebundle ON the rclone nfsmount

### Phase 1: disk-image mechanics (no sudo) — ✅ PASS (2026-08-15)

| Step | Result |
|---|---|
| `rclone nfsmount` of simulated cloud (`:local:` backend) | ✅ mounts via built-in NFS client |
| `hdiutil create` 2 GB case-sensitive APFS sparsebundle on mount | ❌ **"No locks available"** with default options → ✅ works with `-o nolocks -o locallocks` |
| `hdiutil attach` from the mount | ✅ |
| 64 MB write into attached volume | ✅ 184 MB/s (absorbed by VFS write cache) |
| `hdiutil detach` | ✅ clean |
| Band files propagate to backing store | ✅ 27 bands / 88 MB after ~10 s |
| Re-attach from mount, read back file | ✅ intact |

**Key learnings**
1. rclone's NFS server implements no NLM lock daemon; hdiutil requires locks.
   Mounting with `-o nolocks -o locallocks` (locks handled client-locally) fixes
   it and is safe for our single-client-per-mount design.
2. `rclone nfsmount` ignores SIGINT for teardown; the reliable unmount is
   `umount <mountpoint>` — rclone detects it, flushes, and exits by itself.
3. Killing the rclone process (SIGTERM) unmounts the volume immediately —
   writes still in the VFS cache upload only if rclone exits gracefully.
   Supervision + clean shutdown matter for backup integrity.

### Phase 2: tmutil acceptance (sudo + Full Disk Access) — ❌ FAIL (2026-08-15)

`sudo tmutil setdestination -a /Volumes/MountGateTM` →
**"Operation not supported (error 45)"**. macOS 26 detects and rejects
disk-image volumes whose backing store is an NFS mount.

Control test: an identical sparsebundle on the **local** disk was
**accepted** — so the rejection is specifically about network-backed images,
not disk images in general.

**Verdict: Direct mode is dead on macOS 26. MountGate ships Staged mode.**

Note: `tmutil setdestination` also requires the invoking terminal to have
Full Disk Access — the M5 app flow must request FDA (or use the System
Settings TM UI path).

## Staged mode — local sparsebundle + rclone sync after backup — ✅ PASS (2026-08-15)

| Step | Result |
|---|---|
| Local case-sensitive APFS sparsebundle accepted by `tmutil setdestination` | ✅ (`Kind: Local`) |
| backupd starts a REAL backup into it | ✅ `.inprogress` observed; ~1.8 GiB written before our tiny 2 GB test bundle ran out |
| TM claims the volume (user writes denied post-setdestination) | expected — backupd owns it |
| `rclone sync --checksum` bundle → cloud: initial | ✅ 243 files |
| Incremental sync after attach/detach | ✅ only 2 changed files / 24 MiB re-uploaded (band-level delta) |
| Restore: `rclone copy` back + `hdiutil attach` | ✅ volume mounts, backup contents visible |

### Real-world run (2026-08-16): staged mode capacity limit

First real backup attempt: Time Machine wanted to copy **840 GB** while the
local staging disk had **115 GB free** — staged mode requires local space
roughly equal to the backup set, which many Macs don't have. Backup was
stopped safely and the destination parked.

**Conclusion: staged mode only fits backup sets that fit on the local disk
(or an external staging disk). For full-disk backups to cloud, MountGate
needs a streaming mode — a local SMB server advertising Time Machine
support (Samba vfs_fruit-style, `fruit:time machine = yes`) backed by the
rclone VFS, where the write cache drains to the cloud while backupd writes.
That is the next major milestone (M8).**

**Additional learnings for M5**
- backupd re-attaches destination images by itself when a backup starts.
- Ziv's disk is FileVault-encrypted → macOS warns when the destination bundle
  is unencrypted. Create bundles with `-encryption AES-256` by default.
- Bundle size cap = the disk quota TM sees; size it deliberately in the wizard.
