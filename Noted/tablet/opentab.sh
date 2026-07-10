#!/usr/bin/env bash

set -euo pipefail

DEVICE_ID="13343154AH001453"

BASE_DIR="/home/tutturuu/File/Temp/tablet"
KEY_FILE="$BASE_DIR/key.txt"
PIN_FILE="$BASE_DIR/pin.age"

########################################
# ADB
########################################

adb_cmd() {
    adb -s "$DEVICE_ID" "$@"
}

check_device() {
    local state

    state=$(adb devices | awk -v id="$DEVICE_ID" '$1==id {print $2}')

    if [[ "$state" != "device" ]]; then
        echo "❌ Tablet USB tidak terhubung."
        exit 1
    fi
}

########################################
# SCREEN
########################################

screen_on() {
    adb_cmd shell dumpsys power \
        | grep -q "mHoldingDisplaySuspendBlocker=true"
}

wake_screen() {
    adb_cmd shell input keyevent KEYCODE_WAKEUP
    sleep 1
}

########################################
# LOCK
########################################

is_locked() {
    adb_cmd shell dumpsys window \
        | grep -q "mDreamingLockscreen=true"
}

dismiss_keyguard() {
    adb_cmd shell wm dismiss-keyguard
    sleep 0.5
}

decrypt_pin() {
    age -d -i "$KEY_FILE" "$PIN_FILE"
}

input_pin() {
    local pin
    pin=$(decrypt_pin)

    adb_cmd shell input text "$pin"
    adb_cmd shell input keyevent KEYCODE_ENTER
}

########################################
# ACTION
########################################

unlock_tablet() {

    check_device

    # Kalau layar mati → hidupkan
    if ! screen_on; then
        echo "Wake screen..."
        wake_screen
    fi

    # Kalau sudah unlock → selesai
    if ! is_locked; then
        echo "Tablet already unlocked."
        return
    fi

    echo "Unlocking..."

    dismiss_keyguard
    input_pin

    sleep 1

    if is_locked; then
        echo "❌ Gagal unlock."
        exit 1
    fi

    echo "✅ Tablet unlocked."
}

lock_tablet() {

    check_device

    # Sudah lock
    if is_locked; then

        # Kalau layar mati, hidupkan saja
        if ! screen_on; then
            echo "Wake screen..."
            wake_screen
        fi

        echo "✅ Tablet already locked."
        return
    fi

    echo "Locking..."

    # Matikan layar (otomatis lock)
    adb_cmd shell input keyevent KEYCODE_POWER
    sleep 1

    # Hidupkan lagi supaya berhenti di lockscreen
    wake_screen

    echo "✅ Tablet locked."
}

scrcpysetup() {

    if ! tmux has-session -t scrcpytablet 2>/dev/null; then
        echo "Starting scrcpy setup in tmux..."

        tmux new-session -d \
            -s scrcpytablet \
            "$HOME/File/Script/random/adb/scrcpymore.sh justinput"
    else
        echo "scrcpy setup already running."
    fi

    sleep 2

    echo "Starting Termux..."
    adb_cmd shell am start -n com.termux/.HomeActivity >/dev/null 2>&1
}
########################################
# MAIN
########################################

case "${1:-}" in
    unlock)
        unlock_tablet
        scrcpysetup
        ;;
    lock)
        lock_tablet
        ;;
    *)
        echo "Usage:"
        echo "  $0 unlock"
        echo "  $0 lock"
        exit 1
        ;;
esac