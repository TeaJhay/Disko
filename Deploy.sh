#!/usr/bin/env bash
set -euo pipefail
echo "About to WIPE according to disko.nix"
lsblk -e7,11 -o NAME,SIZE,MODEL
read -rp "Type YES to continue: " confirm
[[ "${confirm,,}" == "yes" ]] || { echo "Aborted."; exit 1; }

echo "== Phase 1:: Disko partition and Format  =="
sudo nix --experimental-features "nix-command flakes" \
run github:nix-community/disko/latest -- --mode destroy,format,mount \
--yes-wipe-all-disks ./disko.nix


echo "== Phase 2:: Minimal NixOS-Install  =="
sudo nixos-generate-config --root /mnt
cd /mnt
sudo nixos-install

echo "== Creating pristine @void-blank snapshot =="
sudo umount -R /mnt 2>/dev/null || true
sudo mount -o rw,subvol=/ /dev/disk/by-partlabel/disk-main-root /mnt
sudo btrfs subvolume snapshot -r /mnt/@void /mnt/@void-blank
sudo umount /mnt

# verify

ROOT_DEV="/dev/disk/by-partlabel/disk-main-root"
MNT="/mnt"
SUBVOL_SRC="@void"
SUBVOL_SNAP="@void-blank"
 
PASS=0
FAIL=0
 
ok()   { echo "  [OK]   $1"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
hdr()  { echo; echo "== $1 =="; }
 
# Make sure root subvol is mounted at $MNT (rw, so we can inspect properly)
NEED_UMOUNT=0
if ! mountpoint -q "$MNT"; then
    sudo mount -o rw,subvol=/ "$ROOT_DEV" "$MNT"
    NEED_UMOUNT=1
fi
 
hdr "Partition table"
lsblk -e7,11 -o NAME,SIZE,FSTYPE,PARTLABEL,MOUNTPOINT
 
hdr "Expected partitions"
for label in disk-main-ESP disk-main-SWAP disk-main-root; do
    if [[ -e "/dev/disk/by-partlabel/$label" ]]; then
        ok "Partition present: $label"
    else
        bad "Partition MISSING: $label"
    fi
done
 
hdr "Subvolumes"
SUBVOL_LIST="$(sudo btrfs subvolume list -a "$MNT")"
echo "$SUBVOL_LIST"
 
for sv in @home @nix @persistent @snapshots "$SUBVOL_SRC" "$SUBVOL_SNAP"; do
    if echo "$SUBVOL_LIST" | grep -q "path ${sv#/}$"; then
        ok "Subvolume present: $sv"
    else
        bad "Subvolume MISSING: $sv"
    fi
done
 
hdr "Snapshot read-only flag"
RO_STATE="$(sudo btrfs property get "$MNT/$SUBVOL_SNAP" ro 2>/dev/null)"
if [[ "$RO_STATE" == "ro=true" ]]; then
    ok "$SUBVOL_SNAP is read-only ($RO_STATE)"
else
    bad "$SUBVOL_SNAP is NOT read-only (got: ${RO_STATE:-<error>})"
fi
 
hdr "Snapshot content diff vs source"
DIFF_OUT="$(sudo diff -rq "$MNT/$SUBVOL_SRC" "$MNT/$SUBVOL_SNAP" 2>&1)"
if [[ -z "$DIFF_OUT" ]]; then
    ok "$SUBVOL_SNAP content matches $SUBVOL_SRC exactly"
else
    bad "$SUBVOL_SNAP differs from $SUBVOL_SRC:"
    echo "$DIFF_OUT" | sed 's/^/         /'
fi
 
hdr "Snapshot lineage (Parent UUID check)"
SRC_UUID="$(sudo btrfs subvolume show "$MNT/$SUBVOL_SRC" | awk -F':' '/^\tUUID:/{print $2}' | tr -d '[:space:]')"
SNAP_PARENT_UUID="$(sudo btrfs subvolume show "$MNT/$SUBVOL_SNAP" | awk -F':' '/Parent UUID:/{print $2}' | tr -d '[:space:]')"
if [[ -n "$SRC_UUID" && "$SRC_UUID" == "$SNAP_PARENT_UUID" ]]; then
    ok "$SUBVOL_SNAP's Parent UUID matches $SUBVOL_SRC's UUID ($SRC_UUID)"
else
    bad "UUID mismatch: $SUBVOL_SRC UUID=$SRC_UUID  vs  $SUBVOL_SNAP Parent UUID=$SNAP_PARENT_UUID"
fi
 
if [[ "$NEED_UMOUNT" -eq 1 ]]; then
    sudo umount "$MNT"
fi
 
hdr "Summary"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo
if [[ "$FAIL" -eq 0 ]]; then
    echo "All checks passed. Safe to reboot when ready."
    exit 0
else
    echo "Some checks FAILED. Do not proceed until resolved."
    exit 1
fi
