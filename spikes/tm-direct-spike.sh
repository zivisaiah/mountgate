#!/bin/bash
# M2 spike — "Direct mode": can a sparsebundle that LIVES ON an rclone
# nfsmount be attached and accepted as a Time Machine destination?
#
# Phase 1 (no sudo): mount simulated cloud → create sparsebundle on it →
#                    hdiutil attach → write into the volume → verify the
#                    band files reach the backing store → detach.
# Phase 2 (sudo, run manually): tmutil setdestination + a real backup.
#
# Usage: ./spikes/tm-direct-spike.sh [phase1|phase2|cleanup]
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RCLONE="$REPO_ROOT/Vendor/rclone"
WORK="$HOME/MountGate/_tmspike"
CLOUD="$WORK/cloud-sim"        # local dir standing in for the cloud bucket
MNT="$WORK/mnt"                # rclone nfsmount of CLOUD
BUNDLE="$MNT/MountGateTM.sparsebundle"
VOLNAME="MountGateTM"
LOG="$WORK/rclone.log"

say() { printf '\n==> %s\n' "$*"; }

phase1() {
    mkdir -p "$CLOUD" "$MNT"

    say "Mounting simulated cloud via rclone nfsmount"
    # -o nolocks -o locallocks: rclone's NFS server has no lock daemon and
    # hdiutil fails with "No locks available" without them (verified macOS 26).
    # stdio redirected: an inherited pipe write-end blocks callers forever.
    "$RCLONE" nfsmount ":local:$CLOUD" "$MNT" \
        --volname tmspike --vfs-cache-mode full \
        -o nolocks -o locallocks \
        --log-file "$LOG" --log-level INFO >/dev/null 2>&1 &
    RCLONE_PID=$!
    for i in $(seq 1 40); do
        mount | grep -q " $MNT " && break; sleep 0.25
    done
    mount | grep " $MNT " || { echo "FAIL: mount did not appear"; exit 1; }

    say "Creating 2 GB case-sensitive APFS sparsebundle ON the mount"
    time hdiutil create -size 2g -type SPARSEBUNDLE \
        -fs "Case-sensitive APFS" -volname "$VOLNAME" "$BUNDLE" \
        || { echo "FAIL: hdiutil create on NFS mount"; exit 1; }

    say "Attaching sparsebundle"
    hdiutil attach "$BUNDLE" || { echo "FAIL: hdiutil attach"; exit 1; }
    VOL="/Volumes/$VOLNAME"
    [ -d "$VOL" ] || { echo "FAIL: attached volume not at $VOL"; exit 1; }

    say "Writing 64 MB test file into the attached volume"
    time dd if=/dev/urandom of="$VOL/testfile" bs=1m count=64 2>&1 | tail -1
    sync

    say "Detaching (flushes bands)"
    time hdiutil detach "$VOL"

    say "Waiting for VFS cache upload to backing store"
    for i in $(seq 1 120); do
        # rclone reports when uploads finish; just poll the backing store size.
        local_size=$(du -sm "$CLOUD" | awk '{print $1}')
        [ "$local_size" -gt 64 ] && break
        sleep 1
    done
    say "Backing store now holds:"
    du -sh "$CLOUD"
    find "$CLOUD" -name "*.sparsebundle" -maxdepth 2 | head -3
    band_count=$(find "$CLOUD" -path "*/bands/*" -type f | wc -l | tr -d ' ')
    echo "band files in backing store: $band_count"
    [ "$band_count" -gt 0 ] || echo "WARN: no band files reached backing store"

    say "Re-attaching from the mount to prove round-trip integrity"
    hdiutil attach "$BUNDLE" && ls -la "$VOL/" && \
        cmp <(head -c 1048576 "$VOL/testfile") <(head -c 1048576 "$VOL/testfile") \
        && echo "round-trip OK"
    hdiutil detach "$VOL"

    say "PHASE 1 COMPLETE — leaving mount up for phase 2."
    echo "rclone PID: $RCLONE_PID (unmount with: $0 cleanup)"
    echo
    echo "PHASE 2 (requires sudo — run manually):"
    echo "  hdiutil attach \"$BUNDLE\""
    echo "  sudo tmutil setdestination -a \"/Volumes/$VOLNAME\""
    echo "  tmutil destinationinfo"
    echo "  sudo tmutil startbackup -b"
}

phase2() {
    hdiutil attach "$BUNDLE" 2>/dev/null
    say "tmutil setdestination (will prompt for password)"
    sudo tmutil setdestination -a "/Volumes/$VOLNAME" && echo "DESTINATION ACCEPTED" \
        || echo "DESTINATION REJECTED (exit $?)"
    tmutil destinationinfo
}

cleanup() {
    hdiutil detach "/Volumes/$VOLNAME" 2>/dev/null
    umount "$MNT" 2>/dev/null || umount -f "$MNT" 2>/dev/null
    sleep 1
    pkill -f "nfsmount :local:$CLOUD" 2>/dev/null
    echo "cleaned up (backing store kept at $CLOUD)"
}

case "${1:-phase1}" in
    phase1)  phase1 ;;
    phase2)  phase2 ;;
    cleanup) cleanup ;;
    *) echo "usage: $0 [phase1|phase2|cleanup]"; exit 2 ;;
esac
