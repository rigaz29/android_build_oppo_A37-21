#!/bin/bash
# extract-ul21-patches.sh — ekstraksi delta LineageOS-UL lineage-21.0 terhadap
# official lineage-21.0, per repo.
#
# Diadaptasi dari tools/extract-official-patches.sh proyek 20. Perbedaannya:
# proyek 20 mengekstrak dari checkout UL yang utuh di /root/los20; di sini
# tidak ada checkout UL, jadi tiap repo diklon sendiri secara BLOBLESS
# (--filter=blob:none). Blobless, bukan --depth: mencari merge-base menuntut
# riwayat penuh, dan shallow clone akan menggagalkannya.
#
# Pemakaian:
#   tools/extract-ul21-patches.sh <repo> [repo...]
#   tools/extract-ul21-patches.sh --t0        # tier boot-critical saja
#
# Nama repo = nama repo GitHub tanpa awalan "android_".
set -u
WORK="${WORK:-/root/a37-21/research/ul21}"
OUT="${OUT:-/root/a37-21/patches/ul21}"
UL=https://github.com/LineageOS-UL
OFF=https://github.com/LineageOS
mkdir -p "$WORK" "$OUT"
SUM="$OUT/_ringkasan.txt"

T0="art system_bpf external_perfetto packages_modules_NetworkStack"
# T1/T2 mengikuti tier PLAN-OFFICIAL proyek 20 (patches/official/MANIFEST.md).
# Tidak termasuk: frameworks_libs_net dan packages_modules_Wifi -- keduanya TIDAK
# punya branch lineage-21.0 di UL (diverifikasi lewat API GitHub), jadi ditangani
# terpisah, bukan lewat ekstraksi ini.
T1="vendor_lineage system_core system_netd packages_modules_Connectivity system_sepolicy device_lineage_sepolicy hardware_interfaces frameworks_native packages_modules_Bluetooth"
T2="frameworks_av frameworks_base"

case "${1:-}" in
  --t0) set -- $T0 ;;
  --t1) set -- $T1 ;;
  --t2) set -- $T2 ;;
  --all) set -- $T0 $T1 $T2 ;;
esac

for name in "$@"; do
    repo="android_$name"
    dir="$WORK/$name"
    out="$OUT/$name"
    if [ -d "$out" ] && ls "$out"/*.patch >/dev/null 2>&1; then
        echo "lewat (sudah ada): $name — $(ls "$out"/*.patch | wc -l) patch"; continue
    fi
    if [ ! -d "$dir/.git" ]; then
        echo ":: klon $name (blobless)"
        git clone --filter=blob:none --branch lineage-21.0 --single-branch -q \
            "$UL/$repo.git" "$dir" 2>/dev/null || { echo "!! $name: klon UL gagal"; continue; }
    fi
    cd "$dir" || continue
    git fetch -q "$OFF/$repo.git" lineage-21.0 2>/dev/null || { echo "!! $name: fetch official gagal"; continue; }
    mb=$(git merge-base HEAD FETCH_HEAD 2>/dev/null || echo "")
    [ -z "$mb" ] && { echo "!! $name: tidak ada merge-base"; continue; }
    mkdir -p "$out"
    git format-patch -q --no-merges "$mb..HEAD" -o "$out" >/dev/null 2>&1
    n=$(ls "$out"/*.patch 2>/dev/null | wc -l)
    {
        echo "repo: $name"
        echo "ul-head: $(git rev-parse HEAD)"
        echo "ul-head-tanggal: $(git log -1 --format=%ad --date=short)"
        echo "official-head: $(git rev-parse FETCH_HEAD)"
        echo "merge-base: $mb"
        echo "merge-base-tanggal: $(git log -1 --format=%ad --date=short "$mb")"
        echo "jumlah-patch: $n"
        echo "tanggal-ekstraksi: $(date -u +%FT%TZ)"
    } > "$out/.meta"
    printf "%s\t%s\n" "$name" "$n" >> "$SUM"
    echo "ok: $name — $n patch (merge-base ${mb:0:12})"
done
