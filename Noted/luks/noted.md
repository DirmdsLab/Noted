# Buat Luks

cryptsetup luksFormat /dev/sdX

cryptsetup luksOpen /dev/sdX crypted

mkfs.ext4 /dev/mapper/crypted

# Buka pake key

sudo dd if=/dev/urandom of=luks-hdd.key bs=4096 count=1

sudo chmod 600 luks-hdd.key

sudo cryptsetup luksAddKey /dev/sda2 luks-hdd.key

sudo cryptsetup open /dev/sda2 hddex --key-file luks-hdd.key 