Berikut step lengkap dari awal sampai selesai (Ubuntu + fish/bash + Playwright + unpack `.mpkg` lewat `index.html` + unzip hasil).

# 1. Install NVM + Node.js

Install nvm:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.6/install.sh | bash
```

Aktifkan nvm tanpa restart terminal:

```bash
\. "$HOME/.nvm/nvm.sh"
```

Install Node.js 24:

```bash
nvm install 24
```

Set default:

```bash
nvm alias default 24
```

Cek:

```bash
node -v
npm -v
```

Output:

```text
v24.18.0
11.16.0
```

---

# 2. Export nvm otomatis ke bash

Tambahkan ke `~/.bashrc`:

```bash
echo '. "$HOME/.nvm/nvm.sh"' >> ~/.bashrc
```

Reload:

```bash
source ~/.bashrc
```

Sekarang setiap buka terminal:

```bash
node -v
```

langsung memakai Node dari nvm.

---

# 3. Buat folder kerja

```bash
mkdir ~/mpkg-unpacker
cd ~/mpkg-unpacker
```

---

# 4. Setup Playwright

Buat package:

```bash
npm init -y
```

Install:

```bash
npm install playwright
```

Install Chromium:

```bash
npx playwright install chromium
```

Install dependency Chromium Ubuntu:

```bash
npx playwright install-deps chromium
```

Jika ada dependency kurang:

```bash
sudo apt install -y \
libasound2 \
libgbm1 \
libnspr4 \
libnss3 \
libatk1.0-0 \
libatk-bridge2.0-0 \
libatspi2.0-0 \
libcups2 \
libdrm2 \
libgtk-3-0 \
libxcomposite1 \
libxdamage1 \
libxfixes3 \
libxkbcommon0 \
libxrandr2
```

---

# 5. Pastikan server unpacker jalan

Jalankan web:

```text
http://localhost:5030
```

Test:

```bash
curl http://localhost:5030
```

Harus mengeluarkan HTML `index.html`.

---

# 6. Buat script Playwright

Buat:

```bash
nano ~/mpkg-unpacker/unpack.js
```

Isi:

```javascript
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

const INPUT_DIR = "/home/shiro/Downloads/wallpaper";
const OUTPUT_DIR = "/home/shiro/wallpaper";
const URL = "http://localhost:5030/";

fs.mkdirSync(OUTPUT_DIR, { recursive: true });

(async () => {
    const files = fs.readdirSync(INPUT_DIR)
        .filter(f => f.toLowerCase().endsWith(".mpkg"))
        .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));

    console.log(`Found ${files.length} file(s)`);

    const browser = await chromium.launch({
        headless: true
    });

    for (const file of files) {

        console.log(`Processing ${file}`);

        const page = await browser.newPage();

        await page.goto(URL, {
            waitUntil: "networkidle"
        });

        await page.locator("#file").setInputFiles(
            path.join(INPUT_DIR, file)
        );

        await page.waitForSelector("#downloadlink a", {
            timeout: 0
        });

        const downloadPromise = page.waitForEvent("download");

        await page.locator("#downloadlink a").click();

        const download = await downloadPromise;

        const output = path.join(
            OUTPUT_DIR,
            file.replace(/\.mpkg$/i, ".zip")
        );

        await download.saveAs(output);

        console.log(`Saved -> ${output}`);

        await page.close();

        await new Promise(r => setTimeout(r, 500));
    }

    await browser.close();

    console.log("Done");
})();
```

---

# 7. Jalankan unpack

Input:

```text
/home/shiro/Downloads/wallpaper

1.mpkg
2.mpkg
...
13.mpkg
```

Jalankan:

```bash
cd ~/mpkg-unpacker
node unpack.js
```

Output:

```text
/home/shiro/wallpaper

1.zip
2.zip
...
13.zip
```

---

# 8. Extract semua ZIP (fish shell)

Buat folder hasil:

```fish
mkdir -p ~/wallpaper
```

Extract:

```fish
for f in ~/wallpaper/*.zip
    set name (basename $f .zip)
    mkdir -p ~/wallpaper/$name
    unzip -q $f -d ~/wallpaper/$name
end
```

Hasil:

```text
/home/shiro/wallpaper

1/
2/
3/
...
13/
```

---

# 9. (Opsional) Hapus ZIP setelah extract

```fish
for f in ~/wallpaper/*.zip
    set name (basename $f .zip)
    mkdir -p ~/wallpaper/$name
    unzip -q $f -d ~/wallpaper/$name
    rm $f
end
```

Selesai. Workflow akhirnya:

```text
.mpkg
  ↓
index.html localhost:5030
  ↓
Playwright headless
  ↓
.zip
  ↓
unzip
  ↓
folder hasil unpack
```
