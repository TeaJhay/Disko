sudo nix run github:nix-community/disko/latest -- --mode destroy,format,mount --arg disks '[ "/dev/nvme0n1" ]' ./hosts/laptop/disko-config.nix --experimental-feature "nix-command flakes"
