# PROMPT: H264 Anime Dance Video menjadi Unicode ASCII Terminal Animation

Bertindak sebagai ahli ASCII Art, pemrosesan video, computer vision, dan animasi terminal Linux.

Saya akan mengunggah satu file:

1. Video anime green screen format H264 MP4

Tujuan:
Ubah video anime dance tersebut menjadi animasi ASCII Art yang dapat diputar di terminal Linux tanpa membutuhkan Python.

Prioritas:
- Pertahankan identitas karakter anime.
- Pertahankan pose, ekspresi, rambut, pakaian, dan gerakan dance.
- Gunakan gaya ASCII seperti contoh dense Unicode ASCII art.
- Jangan membuat ASCII brightness biasa yang kehilangan bentuk karakter.

---

## LANGKAH 1 — ANALISIS VIDEO

Periksa video:

- codec
- resolusi
- FPS
- durasi
- jumlah frame

Analisis:

- posisi karakter
- ukuran karakter
- area green screen
- gerakan dance
- frame penting

Gunakan green screen sebagai transparansi.

Background harus menjadi:
- spasi kosong
- atau karakter minimal

Jangan mengubah background menjadi noise ASCII.

---

## LANGKAH 2 — METODE KONVERSI

Gunakan pipeline:

Video H264
↓
Frame extraction
↓
Green screen removal (HSV masking)
↓
Character segmentation
↓
Bounding box tracking
↓
Resize dengan mempertahankan aspect ratio
↓
Edge preservation
↓
Shading conversion
↓
Unicode ASCII mapping
↓
Terminal animation


Gunakan karakter ASCII padat seperti:

⣿ ⣶ ⣀ ⢀ ⠈ ⠂

atau karakter Unicode dengan tingkat density tinggi.

Hindari:

#
@
.
:
karena terlalu sederhana.

---

## LANGKAH 3 — KUALITAS VISUAL

Pastikan:

- kepala tidak terpotong
- tangan dan kaki tetap terlihat
- ukuran karakter konsisten antar frame
- tidak flicker
- tidak berubah bentuk setiap frame

Gunakan:

- temporal smoothing
- frame normalization
- silhouette preservation


Jika perlu lakukan iterasi:

1. buat preview
2. evaluasi bentuk karakter
3. perbaiki threshold
4. ulangi

---

## LANGKAH 4 — OUTPUT

Buat folder:

output/

isi:

frames/
- frame_0000.txt
- frame_0001.txt
- dst

dance_ascii.txt

player.sh

README.md


---

## LANGKAH 5 — PLAYER TANPA PYTHON

Output harus dapat dijalankan di Linux fish/bash tanpa Python.

Buat:

player.sh


Isi menggunakan shell:

- clear terminal ANSI
- membaca frame txt
- sleep sesuai FPS


Contoh penggunaan:

chmod +x player.sh

./player.sh


---

## LANGKAH 6 — UKURAN OUTPUT

Buat dua versi:

### MASTER
Untuk kualitas:

- width 100–120 karakter
- FPS 8–10
- detail tinggi


### SMALL
Untuk terminal kecil:

- width 60–80 karakter
- ukuran file lebih kecil


---

## LANGKAH 7 — VALIDASI

Sebelum selesai:

Periksa:

✓ karakter masih dikenali  
✓ gerakan sesuai video asli  
✓ tidak ada frame kosong  
✓ tidak ada flicker berlebihan  
✓ terminal Linux dapat menjalankan hasil tanpa Python  


Berikan:

1. Ringkasan analisis video.
2. Struktur folder output.
3. File ZIP hasil.
4. Cara menjalankan di Linux fish shell.