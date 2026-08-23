#!/usr/bin/env bash

# not for secure
# Change u hash | echo -n "turu" | sha256sum
HASH="1035d214489e6353fd7fcff0eeabf5a9a69358d0267500843380d247450e77f6"

if [[ "$1" == "manual" ]]; then
    read -s -p "Enter Password: " input
    echo ""
else
    input=$(printf "" | wofi --dmenu --password --prompt "Enter Password")
fi

input_hash=$(printf "%s" "$input" | sha256sum | awk '{print $1}')

if [[ "$input_hash" == "$HASH" ]]; then
    hyprctl dispatch submap reset
    ~/File/Script/log/info.sh 2
else
    notify-send "Wrong password!"
    ~/File/Script/log/info.sh 6
fi