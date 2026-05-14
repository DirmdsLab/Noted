From https://nixos.org/manual/nixos/stable/#sec-installation-manual

# NixOS Installation Manual (Summary)

## 1. Switch to root
sudo -i

---

## 2. Networking in the installer

Check network interfaces:
ip a

> Note: On the minimal installer, NetworkManager is not available. Network must be configured manually.

### Wi-Fi setup
Start wpa_supplicant:
sudo systemctl start wpa_supplicant

Run wpa_cli and configure your network:

add_network 0

set_network 0 ssid "myhomenetwork"

set_network 0 psk "mypassword"

enable_network 0

Successful connection example:
<3>CTRL-EVENT-CONNECTED - Connection to 32:85:ab:ef:24:5c completed [id=0 id_str=]

Exit wpa_cli:
quit

### Optional: SSH for remote installation
- Copy your SSH key to /home/nixos/.ssh/authorized_keys or /root/.ssh/authorized_keys.
- Or set a password for root or nixos with:
passwd

---

## 3. Partitioning and formatting

> Note: The NixOS installer does not partition or format disks automatically. You must do it manually.

Use tools like parted, fdisk, gdisk, cfdisk, or cgdisk. Example with fdisk:

1. Find your disk:
lsblk

2. Create partitions (I'm use fdisk):
GPT
- Boot partition  
- Root (/) partition  

cryptsetup luksFormat /dev/sdX

cryptsetup luksOpen /dev/sdX crypted

### Format filesystems
mkfs.fat -F 32 -n BOOT /dev/sdX1

mkfs.ext4 /dev/mapper/crypted

---

## 4. Mount filesystems
mount /dev/mapper/crypted /mnt

mkdir -p /mnt/boot

mount -o umask=077 /dev/disk/by-label/BOOT /mnt/boot

---

## 5. Generate NixOS configuration
nixos-generate-config --root /mnt

Edit configuration file:
nano /mnt/etc/nixos/configuration.nix
> Replace with configuration-live-1.nix 

---

## 6. Install NixOS
nixos-install

Reboot after installation:
reboot

---

