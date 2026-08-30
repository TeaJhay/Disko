#!/usr/bin/env bash
set -euo pipefail
echo "About to WIPE according to disko.nix"
lsblk -o NAME,SIZE,MODEL 
read -rp "Type YES to continue: " confirm
[[ "${confirm,,}" == "yes" ]] || { echo "Aborted."; exit 1; }

echo "== Phase 1:: Disko partition and Format  =="
sudo nix --experimental-features "nix-command flakes" /
run github:nix-community/disko/latest -- --mode destroy,format /
--yes-wipe-all-disks ./disko.nix

echo "== Creating pristine @void-blank snapshot =="
sudo mount -o subvol=/ /dev/disk/by-partlabel/disk-main-root /mnt
sudo btrfs subvolume snapshot -r /mnt/@void /mnt/@void-blank
sudo umount /mnt

echo "Done. Run 'sudo reboot' when ready."
