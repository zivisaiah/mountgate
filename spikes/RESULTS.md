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

### Phase 2: tmutil acceptance + real backup (requires sudo) — ⏳ PENDING

The open question: does `tmutil setdestination -a /Volumes/MountGateTM`
accept an attached sparsebundle whose bundle lives on an NFS mount, and does
`backupd` complete a real backup into it on macOS 26? Run:

```sh
./spikes/tm-direct-spike.sh phase2   # prompts for sudo password
sudo tmutil startbackup -b           # then watch: tmutil status
```

## Staged mode — local sparsebundle + rclone sync after backup

Not yet run. Guaranteed-workable per Wasabi-documented pattern; will validate
during M5.
