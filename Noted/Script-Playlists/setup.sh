#!/usr/bin/env bash

target="$HOME/.config/mpv/playlists"
backup="${target}.bak"

# Backup jika target ada dan bukan symlink
if [ -e "$target" ] && [ ! -L "$target" ]; then
    mv "$target" "$backup"
fi

ln -sfn "$(pwd)" "$target"
