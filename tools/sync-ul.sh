#!/bin/bash
# Sync tree LineageOS-UL 21 dengan retry.
#
# repo sync pada 1453 project hampir selalu kena kegagalan transien (reset by peer,
# HTTP 429, objek korup). Skrip ini mengulang sampai bersih, bukan sampai lelah.
#
# -c        : hanya branch yang dipakai manifest — memangkas ukuran & waktu drastis
# -j8       : sync terikat jaringan, bukan CPU; 8 aman untuk 12 core
# --force-sync : timpa checkout yang menyimpang (aman di percobaan pertama, semua repo
#                milik kita ada di local manifest dan di-pin)
set -u
TREE="${TREE:-/root/los21}"
LOG="${LOG:-$TREE/sync.log}"
MAX="${MAX:-8}"

cd "$TREE" || exit 1

for i in $(seq 1 "$MAX"); do
    echo "=== percobaan $i/$MAX — $(date '+%H:%M:%S') ===" | tee -a "$LOG"
    repo sync -c -j8 --force-sync --no-clone-bundle --optimized-fetch >>"$LOG" 2>&1
    rc=$?
    if [ $rc -eq 0 ]; then
        echo "=== sync BERSIH pada percobaan $i — $(date '+%H:%M:%S') ===" | tee -a "$LOG"
        exit 0
    fi
    echo "--- percobaan $i gagal (rc=$rc), ulangi dalam 30 detik ---" | tee -a "$LOG"
    sleep 30
done

echo "=== MENYERAH setelah $MAX percobaan ===" | tee -a "$LOG"
exit 1
