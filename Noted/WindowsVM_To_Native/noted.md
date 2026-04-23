# Experiment Notes

## Goal
Make Windows from a virt-manager disk become native boot on an existing storage.

---

## Case

From:
```
win11.qcow
```

To:
```
sda
├─sda1
└─sda2
```

## Steps

### 1. Shrink C Partition
Reduce the C partition to a safe limit to speed up the cloning process.

---

### 2. Check Disk Name

Check the disk name.

Example:
```
win11.qcow
```

### 3. Load NBD Module

In terminal:
```bash
sudo modprobe nbd max_part=8
````

Check with:

```bash
lsblk
```

It should show:

```
nbd0 ... up to max_part
```

---

### 4. Connect QCOW Disk

Go to the directory where the qcow file is located.

Run:

```bash
sudo qemu-nbd --connect=/dev/nbd0 win11.qcow
```

or:

```bash
sudo qemu-nbd --connect=/dev/nbd0 "fullpath"
```

---

### 5. Result

After connecting, `lsblk` should show:

```
nbd0         43:0    0   120G  0 disk
├─nbd0p1     43:1    0   200M  0 part
├─nbd0p2     43:2    0    16M  0 part
├─nbd0p3     43:3    0  33.7G  0 part
└─nbd0p4     43:4    0   735M  0 part
```

### 6. Check Disk Details

Run:
```bash
sudo fdisk -l /dev/nbd0
````

Output:

```id="x8l2mn"
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
```

---

### 7. Minimum Requirement for Boot

For minimal boot, only the C partition is needed:

````
nbd0p3

Check the size of C: from Windows VM.

Required space:
- `70733824` sectors (C partition)
- `409600` sectors (~200MiB) for EFI

Make sure the target disk has enough free space for both.
````
### 8. Check Free Space on Target Disk

Run:
```bash
sudo parted /dev/sda unit s print free
````

Output:

```
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
```

---

### 9. Analyze Free Space

Available free space:

```
1818324992s → 1953525133s = 135200142 sectors
```

Compare with requirement:

* EFI: `409600` sectors
* C partition: `70733824` sectors


### 10. Create EFI Partition

Free space is safe:
```
135200142 sectors
````

Create EFI partition (200MiB).

(MSR can also be created, but must use full disk so it automatically takes the 16MiB reserved space)

EFI layout:

```
Start: 1818357760
End:   1818767359
Size:  409600 sectors (200M)
```

unfindshnot finished yet