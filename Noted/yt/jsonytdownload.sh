#!/usr/bin/env bash

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <json-file>"
    exit 1
fi

JSON_FILE="$1"

if [ ! -f "$JSON_FILE" ]; then
    echo "JSON tidak ditemukan:"
    echo "$JSON_FILE"
    exit 1
fi

YTDLP_SCRIPT="$HOME/File/Code/yt-dlp-script/yt-download.sh"

if [ ! -x "$YTDLP_SCRIPT" ]; then
    echo "Script tidak ditemukan atau tidak executable:"
    echo "$YTDLP_SCRIPT"
    exit 1
fi

while true
do

    TOTAL=$(jq length "$JSON_FILE")

    if [ "$TOTAL" -eq 0 ]; then
        echo
        echo "========================================"
        echo "Semua download selesai."
        echo "Queue kosong."
        echo "========================================"
        exit 0
    fi

    URL=$(jq -r '.[0].url' "$JSON_FILE")
    SUB=$(jq -r '.[0].sub' "$JSON_FILE")
    RES=$(jq -r '.[0].resolution' "$JSON_FILE")

    FORMAT=""

    case "$RES" in
        4k)
            FORMAT="251+401"
            ;;
        1080)
            FORMAT="251+399"
            ;;
        720)
            FORMAT="251+398"
            ;;
        *)
            FORMAT=""
            ;;
    esac

    echo
    echo "========================================"
    echo "Sisa Queue : $TOTAL"
    echo
    echo "URL : $URL"
    echo "RES : ${RES:-none}"
    echo "SUB : ${SUB:-none}"
    echo "========================================"
    echo

    # Download video
    if [ -n "$FORMAT" ]; then
        "$YTDLP_SCRIPT" "$FORMAT" "$URL"
    else
        "$YTDLP_SCRIPT" "$URL"
    fi

    # Download subtitle (optional)
    if [ -n "$SUB" ]; then
        "$YTDLP_SCRIPT" "$URL" "--just-sub=$SUB"
    fi

    # Download thumbnail
    "$YTDLP_SCRIPT" "$URL" "--just-thumbnail"

    while true
    do
        echo
        read -rp "[n] next  [r] retry  [e] exit : " ANSWER

        case "$ANSWER" in

            n|N)

                TMP=$(mktemp)

                jq '.[1:]' "$JSON_FILE" > "$TMP"

                mv "$TMP" "$JSON_FILE"

                echo
                echo "✓ Item selesai. Queue diperbarui."

                break
                ;;

            r|R)

                echo
                echo "↻ Mengulang item yang sama..."

                break
                ;;

            e|E)

                echo
                echo "Exit."

                exit 0
                ;;

            *)

                echo "Pilihan tidak valid."

                ;;

        esac

    done

done