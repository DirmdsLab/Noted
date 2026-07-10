#!/usr/bin/env bash

set -euo pipefail

TABLET="/home/tutturuu/File/Temp/tablet/opentab.sh"

case "${1:-normal}" in
    normal)
        LOCKSCRIPT="$HOME/File/Script/hyprland/hyprlock/hyprlock-script.sh"
        ;;
    idle)
        LOCKSCRIPT="$HOME/Configuration-UwU/Hyprland/user/File/Script/hyprland/hyprlock/hyprlock-idle.sh"
        ;;
    *)
        echo "Usage: $0 [normal|idle]"
        exit 1
        ;;
esac

# Lock tablet
"$TABLET" lock

# Lock PC
"$LOCKSCRIPT"

# Cek sekali saja
if pgrep -x hyprlock >/dev/null; then
    echo "Hyprlock masih berjalan, skip unlock tablet."
else
    echo "Hyprlock sudah selesai, unlock tablet."
    "$TABLET" unlock
fi