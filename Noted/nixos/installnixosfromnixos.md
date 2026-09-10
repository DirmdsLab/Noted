buat 2 partiton efi dan root

efi
buat 1024
dengan flag efi
/dev/nvme0n1p4  270534656  272631807   2097152     1G EFI System

format
mkfs.fat -F 32 -n BOOT /dev/nvme0n1p4

untuk root saya pakai btrfs dengan luks

cryptsetup luksFormat /dev/nvme0n1p12

open

cryptsetup open /dev/nvme0n1p12 cryptroot

format btrfs
mkfs.btrfs /dev/mapper/cryptroot

mount /dev/mapper/cryptroot /mnt

buat sub vol

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@root
btrfs subvolume create /mnt/@snapshots

cek

[nix-shell:~]# btrfs subvolume list /mnt
ID 256 gen 9 top level 5 path @
ID 257 gen 10 top level 5 path @nix
ID 258 gen 10 top level 5 path @home
ID 259 gen 10 top level 5 path @root
ID 260 gen 10 top level 5 path @snapshots

[nix-shell:~]# 


setelah itu unmount
umount /mnt

mount main

mount -o subvol=@ /dev/mapper/cryptroot /mnt

buat folder
mkdir -p /mnt/{nix,home,root,.snapshots,boot}

mount semua sub vol
mount -o subvol=@nix /dev/mapper/cryptroot /mnt/nix
mount -o subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o subvol=@root /dev/mapper/cryptroot /mnt/root
mount -o subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots

mount efi
mount -o umask=077 /dev/disk/by-uuid/12CE-A600 /mnt/boot

hasil akhir

└─nvme0n1p12  259:12   0 114.9G  0 part  
  └─cryptroot 254:1    0 114.9G  0 crypt /mnt/.snapshots
                                         /mnt/root
                                         /mnt/home
                                         /mnt/nix
                                         /mnt

├─nvme0n1p4   259:4    0     1G  0 part  /mnt/boot

[nix-shell:~]# findmnt -R /mnt
TARGET            SOURCE                             FSTYPE OPTIONS
/mnt              /dev/mapper/cryptroot[/@]          btrfs  rw,relatime,ssd,space_cache=v2,subvolid=256,subvol=/@
├─/mnt/nix        /dev/mapper/cryptroot[/@nix]       btrfs  rw,relatime,ssd,space_cache=v2,subvolid=257,subvol=/@nix
├─/mnt/home       /dev/mapper/cryptroot[/@home]      btrfs  rw,relatime,ssd,space_cache=v2,subvolid=258,subvol=/@home
├─/mnt/root       /dev/mapper/cryptroot[/@root]      btrfs  rw,relatime,ssd,space_cache=v2,subvolid=259,subvol=/@root
├─/mnt/.snapshots /dev/mapper/cryptroot[/@snapshots] btrfs  rw,relatime,ssd,space_cache=v2,subvolid=260,subvol=/@snapshots
└─/mnt/boot       /dev/nvme0n1p4                     vfat   rw,relatime,fmask=0077,dmask=0077,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro

[nix-shell:~]# 

nixos-generate-config --root /mnt

edit configuration.nix
cek hardware configuration

dan nixos-install

nixos-enter --root /mnt

set password user passwd user

exit

umount -R /mnt

and reboot via bios