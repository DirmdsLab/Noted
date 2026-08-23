#!/bin/bash

set -e

if [ "$#" -lt 3 ]; then
    echo "Usage:"
    echo "  $0 \"old_path\" \"new_path\" file1.m3u [file2.m3u ...]"
    echo "  $0 \"old_path\" \"new_path\" allfile"
    exit 1
fi

OLD_PATH="$1"
NEW_PATH="$2"
shift 2

# Escape karakter khusus untuk replacement sed
OLD_ESCAPED=$(printf '%s' "$OLD_PATH" | sed 's/[\/&]/\\&/g')
NEW_ESCAPED=$(printf '%s' "$NEW_PATH" | sed 's/[\/&]/\\&/g')

# Mode allfile
if [ "$1" = "allfile" ]; then
    echo "Mencari semua file .m3u secara recursive..."
    echo

    mapfile -d '' FILES < <(find . -type f -iname "*.m3u" -print0)

    if [ "${#FILES[@]}" -eq 0 ]; then
        echo "Tidak ada file .m3u ditemukan."
        exit 0
    fi
else
    # Mode file tertentu
    FILES=("$@")
fi

COUNT=0

for FILE in "${FILES[@]}"; do
    if [ ! -f "$FILE" ]; then
        echo "WARNING: file tidak ditemukan: $FILE"
        continue
    fi

    echo "Mengubah: $FILE"

    sed -i "s|$OLD_ESCAPED|$NEW_ESCAPED|g" "$FILE"

    COUNT=$((COUNT + 1))
done

echo
echo "Selesai."
echo "Total file diubah: $COUNT"
