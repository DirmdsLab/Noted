# EFI
mkfs.fat -F 32 /dev/nvme0n1p4

# LUKS pada root
cryptsetup luksFormat /dev/nvme0n1p12

# Buka LUKS
cryptsetup open /dev/nvme0n1p12 cryptroot

# Btrfs di dalam LUKS
mkfs.btrfs /dev/mapper/cryptroot



mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount /dev/nvme0n1p4 /mnt/boot


/dev/nvme0n1p4
└── FAT32
    └── /mnt/boot

/dev/nvme0n1p12
└── LUKS
    └── cryptroot
        └── Btrfs
            └── /mnt


Btrfs
├── @              → /
├── @nix           → /nix
├── @home          → /home
├── @root          → /root
└── @snapshots     → /.snapshots

# 1. Format EFI
mkfs.fat -F 32 /dev/nvme0n1p4

# 2. Buat LUKS di p12
cryptsetup luksFormat /dev/nvme0n1p12

# 3. Buka LUKS
cryptsetup open /dev/nvme0n1p12 cryptroot

# 4. Buat filesystem Btrfs
mkfs.btrfs /dev/mapper/cryptroot

# 5. Mount Btrfs sementara
mount /dev/mapper/cryptroot /mnt

# 6. Buat 5 subvolume
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@root
btrfs subvolume create /mnt/@snapshots

# 7. Unmount
umount /mnt

mkdir -p /mnt/{nix,home,root,.snapshots,boot}

mount -o subvol=@nix /dev/mapper/cryptroot /mnt/nix
mount -o subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o subvol=@root /dev/mapper/cryptroot /mnt/root
mount -o subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots

mount /dev/nvme0n1p4 /mnt/boot


findmnt -R /mnt


/mnt
├─/mnt/nix
├─/mnt/home
├─/mnt/root
├─/mnt/.snapshots
└─/mnt/boot