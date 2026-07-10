#!/usr/bin/env fish

# Direktori tempat script ini berada
set SCRIPT_DIR (realpath (dirname (status filename)))

# File AppImage & cache selalu berada di folder yang sama dengan script
set APPIMAGE "$SCRIPT_DIR/osu.AppImage"
set CACHE_FILE "$SCRIPT_DIR/icu76_path.txt"

set ICU_DIR ""

# Gunakan cache jika masih valid
if test -f "$CACHE_FILE"
    set CACHED_PATH (string trim < "$CACHE_FILE")

    if test -f "$CACHED_PATH/libicuuc.so.76"
        set ICU_DIR "$CACHED_PATH"
    end
end

# Cache tidak ada / tidak valid → cari lagi
if test -z "$ICU_DIR"
    set ICU_LIB (find /nix/store -name "libicuuc.so.76" 2>/dev/null | head -n1)

    if test -z "$ICU_LIB"
        echo "Error: libicuuc.so.76 tidak ditemukan."
        exit 1
    end

    set ICU_DIR (dirname "$ICU_LIB")

    # Simpan cache
    echo "$ICU_DIR" > "$CACHE_FILE"
end

# Tambahkan ke LD_LIBRARY_PATH
set -gx LD_LIBRARY_PATH "$ICU_DIR" $LD_LIBRARY_PATH

# Jalankan AppImage yang ada di folder script
appimage-run "$APPIMAGE"
