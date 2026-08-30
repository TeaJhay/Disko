{
  fileSystems."/nix".neededForBoot = true;
  fileSystems."/persistent".neededForBoot = true; # Required for impermanence persistence

 # Below if going for ephemeral
 # disko.devices.nodev = {
 #   "/" = {
 #     fsType = "tmpfs";
 #     mountOptions = [
 #       "size=25%"
 #       "mode=755"
 #     ];
 #   };
 # };

  disko.devices.disk.main = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0";
#    device = "/dev/disk/by-id/nvme-CT1000T500SSD8_242649A0A283";
    type = "disk";
    content.type = "gpt";
    content.partitions.esp = {
      name = "ESP";
      priority = 1;
      size = "1G";
      type = "EF00";
      content = {
        type = "filesystem";
        format = "vfat";
        mountpoint = "/boot";
      };
    };
    content.partitions.root = {
      name = "root";
      priority = 3;
      size = "100%";
      content = {
        extraArgs = [ "-f" ];
        type = "btrfs";
        subvolumes = {
          "/@nix" = {
            mountpoint = "/nix";
            mountOptions = [ "compress=zstd" "noatime" ];
          };
          "/@persistent" = {
            mountpoint = "/persistent";
            mountOptions = [ "compress=zstd" "noatime" ];
          };
          "/@snapshots" = {
            mountpoint = "/snapshots";
          };
          "/@home" = {
            mountpoint = "/persistent/home";
            mountOptions = [ "compress=zstd" ];
          };
          "/@void" = {
            mountpoint = "/";
            mountOptions = [ "compress=zstd" "noatime" ];
          };
        };
      };
    };
    content.partitions.swap = {
      name = "SWAP";
      priority = 2;
      size = "12G";
      content = {
        resumeDevice = true;
        type = "swap";
      };
    };
  };
}
