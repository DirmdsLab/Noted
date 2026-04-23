membuat windows di virt-manager jadi native boot ke storage yang sudah terisi

contoh
dari
win11.qcow 
ke
sda             
├─sda1          
└─sda2        

perkecil partition c jadi batas aman untuk mempercepat proses clone

cek nama disknya
contoh 
win11.qcow


di terminal
sudo modprobe nbd max_part=8
seharunya lsblk keluar
nbd0 sampai max

pergi dimana directory qcow
dan run
sudo qemu-nbd --connect=/dev/nbd0 win11.qcow 
atau
sudo qemu-nbd --connect=/dev/nbd0 "fullpath"

hasilnya
nbd0         43:0    0   120G  0 disk  
├─nbd0p1     43:1    0   200M  0 part  
├─nbd0p2     43:2    0    16M  0 part  
├─nbd0p3     43:3    0  33.7G  0 part  
└─nbd0p4     43:4    0   735M  0 part  

detailnya
sudo fdisk -l /dev/nbd0                                                                       17:43
Disk /dev/nbd0: 120 GiB, 128849018880 bytes, 251658240 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 131072 bytes
Disklabel type: gpt
Disk identifier: 9D642309-5FCD-4C57-92F8-EEC377CD559E

Device          Start       End  Sectors  Size Type
/dev/nbd0p1      2048    411647   409600  200M EFI System
/dev/nbd0p2    411648    444415    32768   16M Microsoft reserved
/dev/nbd0p3    444416  71178239 70733824 33.7G Microsoft basic data
/dev/nbd0p4 250148864 251654143  1505280  735M Windows recovery environment

untuk minimal boot kita cuma perlu ambil C nya aja nbd0p3 cek dari size C di windows vm
kita perlu ruang kosong setidaknya 70733824 sectors dan 200MiB(409600) untuk efi

sudo parted /dev/sda unit s print free                                                        17:46
Model: Seagate Expansion HDD (scsi)
Disk /dev/sda: 1953525167s
Sector size (logical/physical): 512B/4096B
Partition Table: gpt
Disk Flags: 

Number  Start        End          Size         File system  Name  Flags
        34s          2047s        2014s        Free Space
 1      2048s        1441523711s  1441521664s
 2      1441523712s  1818324991s  376801280s
        1818324992s  1953525133s  135200142s   Free Space


freespace aman 135200142
sekarang buat dulu efi 200MiB (msr juga bisa sekalian tapi harus full disk supaya dia otomatis memilih 16MiB yang kosong)

dan lakukan proses dd

1818357760 1818767359     409600   200M

sudo dd if=/dev/nbd0p3 of=/dev/sda bs=512 seek=1818767360 status=progress


setelah berhasil buat partition di fdisk sesuai jumlah sektor 70733824
Do you want to remove the signature? [Y]es/[N]o: n
hasilnya bakal
1818767360 1889501183   70733824


sekarang booting ke vm pakai disk tadi sebagai sata
/dev/sda

booting ke iso windows
restore efi windows
masuk ke cmd
diskpart
sel vol 
sel part partition yang di sisikan 200MiB tadi
setelah itu format 
format fs=fat32 quick 
jadikan 
assign letter=Z

setelah itu restore
bcdboot C:\Windows /s Z: /f UEFI

cek windowsnya di mana C atau D sesuaikan

reboot 
kalau di vm berhasil matikan vm
masuk ke bios real machine
pilih external storage tadi dan booting


1818767360 di dapat dari hasil + efi (409600)
First sector (1818767360-1953525133, default 1818767360): 
Last sector, +/-sectors or +/-size{K,M,G,T,P} (1818767360-1953525133, default 1953523711): 1889501183

Created a new partition 4 of type 'Linux filesystem' and of size 33.7 GiB.
Partition #4 contains a ntfs signature.

Do you want to remove the signature? [Y]es/[N]o: n

Command (m for help): p

Disk /dev/sda: 931.51 GiB, 1000204885504 bytes, 1953525167 sectors
Disk model: Expansion HDD   
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 4096 bytes
I/O size (minimum/optimal): 4096 bytes / 4096 bytes
Disklabel type: gpt
Disk identifier: 9C6098A0-89C8-03B0-2826-18277222EC00

Device          Start        End    Sectors   Size Type
/dev/sda1        2048 1441523711 1441521664 687.4G Linux filesystem
/dev/sda2  1441523712 1818357759  376834048 179.7G Linux filesystem
/dev/sda3  1818357760 1818767359     409600   200M Microsoft basic data
/dev/sda4  1818767360 1889501183   70733824  33.7G Linux filesystem

Command (m for help): 
sudo qemu-nbd --disconnect /dev/nbd0
sudo rmmod nbd
