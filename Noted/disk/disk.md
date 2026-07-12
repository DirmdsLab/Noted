Berikut alur lengkap yang kita lakukan untuk **menyalin partisi Ventoy secara identik** ke disk lain yang sudah memiliki partisi sendiri. Ini mengasumsikan Ventoy berada di `nbd0` dan target di `nbd5`.

---


! Fail
kalau mau berhasil hanya perlu p2 dan mbr awal disk <2048
sudo dd if=/dev/nbd0 of=/dev/nbd1 bs=512 count=1 conv=fsync

# 1. Hubungkan image QCOW2 ke NBD

```bash
sudo qemu-nbd --connect=/dev/nbd0 flaskdisk-ex.qcow2
sudo qemu-nbd --connect=/dev/nbd5 disk-tujuan.qcow2
```

**Tujuan**

Menghubungkan file `.qcow2` sehingga muncul sebagai block device Linux (`/dev/nbd0`, `/dev/nbd5`).

---

# 2. Minta kernel membaca tabel partisi

```bash
sudo partprobe /dev/nbd0
sudo partprobe /dev/nbd5
```

**Tujuan**

Kernel membuat device seperti:

```
/dev/nbd0p1
/dev/nbd0p2
```

---

# 3. Buat partisi tujuan

Misalnya menggunakan `fdisk`.

Tujuan akhirnya menjadi:

```
p1  Linux
p2  Ventoy Data
p3  Ventoy EFI
```

Yang penting:

* ukuran sama
* jumlah sektor sama

Posisinya boleh berbeda.

---

# 4. Copy isi partisi

Partisi data

```bash
sudo dd if=/dev/nbd0p1 of=/dev/nbd5p2 bs=4M status=progress conv=fsync
```

Partisi EFI

```bash
sudo dd if=/dev/nbd0p2 of=/dev/nbd5p3 bs=1M status=progress conv=fsync
```

**Yang ikut tersalin**

* seluruh file
* boot sector filesystem
* filesystem UUID
* filesystem LABEL
* seluruh metadata filesystem

---

# 5. Samakan PARTUUID

Partisi data

```bash
sudo sgdisk --partition-guid=2:276c43b5-ba19-084e-2bf4-5be935a9b6c9 /dev/nbd5
```

Partisi EFI

```bash
sudo sgdisk --partition-guid=3:159328d7-aace-1482-164a-c0af6bcf5000 /dev/nbd5
```

**Mengubah**

```
Partition unique GUID
```

---

# 6. Samakan Type GUID

Partisi data

```bash
sudo sgdisk --typecode=2:0700 /dev/nbd5
```

Partisi EFI

```bash
sudo sgdisk --typecode=3:0700 /dev/nbd5
```

**Mengubah**

```
Partition GUID code
```

menjadi

```
Microsoft Basic Data
```

---

# 7. Samakan nama partisi GPT

Partisi data

```bash
sudo sgdisk --change-name=2:Ventoy /dev/nbd5
```

Partisi EFI

```bash
sudo sgdisk --change-name=3:VTOYEFI /dev/nbd5
```

**Mengubah**

```
Partition name
```

---

# 8. Samakan Attribute Flags

Untuk EFI

```bash
sudo sgdisk --attributes=3:set:63 /dev/nbd5
```

Karena Ventoy menggunakan

```
8000000000000000
```

Sedangkan partisi data tetap

```
0000000000000000
```

---

# 9. Minta kernel membaca ulang GPT

```bash
sudo partprobe /dev/nbd5
```

---

# 10. Verifikasi

Filesystem

```bash
lsblk -o NAME,FSTYPE,LABEL,UUID,PARTUUID
```

Metadata GPT

```bash
sudo sgdisk -i 2 /dev/nbd5
sudo sgdisk -i 3 /dev/nbd5
```

Bandingkan dengan sumber.

---

# 11. Lepaskan image

```bash
sudo qemu-nbd --disconnect /dev/nbd5
sudo qemu-nbd --disconnect /dev/nbd0
```

---

# Yang berhasil disamakan

## Metadata GPT Partisi

* ✅ Type GUID
* ✅ Partition GUID (PARTUUID)
* ✅ Attribute Flags
* ✅ Partition Name

## Filesystem

* ✅ UUID
* ✅ LABEL
* ✅ Isi filesystem
* ✅ Semua file
* ✅ Boot sector filesystem

## Layout Partisi

* ✅ Jumlah sektor
* ✅ Ukuran partisi

---

# Yang sengaja tidak disamakan

* ❌ Disk GUID (identitas seluruh disk)
* ❌ First LBA absolut (karena layout disk berbeda)
* ❌ Last LBA absolut
* ❌ GPT Header
* ❌ Backup GPT Header
* ❌ CRC GPT
* ❌ Protective MBR

---

## Kesimpulan

Metode ini menghasilkan **clone partisi secara logis**, bukan **clone disk secara biner**.

Artinya, setiap partisi yang disalin memiliki isi filesystem dan metadata GPT yang sama dengan sumber, tetapi tetap dapat ditempatkan di lokasi LBA yang berbeda pada disk tujuan. Pendekatan ini sangat cocok untuk aplikasi yang membangun satu disk baru dari beberapa sumber (misalnya Ventoy, Windows, MemTest, dan lainnya), karena setiap partisi dapat diposisikan sesuai layout baru tanpa harus menyalin seluruh disk sektor demi sektor.
