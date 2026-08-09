#!/bin/bash
# extract-official-patches.sh — Fase M1 PLAN-OFFICIAL.md
#
# Mengekstrak delta LineageOS-UL terhadap official lineage-20.0 sebagai seri
# patch per repo (git format-patch --no-merges merge-base..HEAD dari checkout
# UL di /root/los20). Hasil: patches/official/<repo>/ + berkas .meta per repo.
#
# Idempoten: repo yang direktorinya sudah berisi patch dilewati (hapus
# direktorinya untuk ekstraksi ulang).
#
# Daftar repo = tier T0+T1+T2+T3 PLAN-OFFICIAL §3 (RIL tidak ikut — fase M6).
# Angka pembanding: tabel §1.3 PLAN-OFFICIAL.md (kolom "UL-only fungsional").

set -u
TREE="${TREE:-/root/los20}"
OUT="${OUT:-/root/a37-20/patches/official}"
mkdir -p "$OUT"
FAIL=0
SUM="$OUT/_ringkasan-ekstraksi.txt"
: > "$SUM"

extract() { # path url ref
  local p="$1" url="$2" ref="$3" safe dir
  safe=$(echo "$p" | tr '/' '_')
  dir="$OUT/$safe"
  if [ -d "$dir" ] && ls "$dir"/*.patch >/dev/null 2>&1; then
    echo "lewat (sudah ada): $p — $(ls "$dir"/*.patch | wc -l) patch"
    return
  fi
  if [ ! -d "$TREE/$p" ]; then
    echo "!! $p: direktori tidak ada di tree"; FAIL=1; return
  fi
  cd "$TREE/$p" || { FAIL=1; return; }
  if ! git fetch -q "$url" "$ref" 2>/dev/null; then
    echo "!! $p: fetch gagal ($url $ref)"; FAIL=1; return
  fi
  local mb
  mb=$(git merge-base HEAD FETCH_HEAD 2>/dev/null || echo "")
  if [ -z "$mb" ]; then
    echo "!! $p: tidak ada merge-base"; FAIL=1; return
  fi
  mkdir -p "$dir"
  git format-patch -q --no-merges "$mb..HEAD" -o "$dir" >/dev/null 2>&1
  local n
  n=$(ls "$dir"/*.patch 2>/dev/null | wc -l)
  {
    echo "repo: $p"
    echo "ul-head: $(git rev-parse HEAD)"
    echo "ul-head-tanggal: $(git log -1 --format=%ad --date=short)"
    echo "official-url: $url"
    echo "official-ref: $ref"
    echo "official-head: $(git rev-parse FETCH_HEAD)"
    echo "merge-base: $mb"
    echo "merge-base-tanggal: $(git log -1 --format=%ad --date=short "$mb")"
    echo "jumlah-patch: $n"
    echo "tanggal-ekstraksi: $(date -u +%FT%TZ)"
  } > "$dir/.meta"
  echo -e "$p\t$n" >> "$SUM"
  echo "ok: $p — $n patch (merge-base ${mb:0:12})"
}

G=https://github.com/LineageOS
A=https://android.googlesource.com

echo "== T0 — gerbang kernel-lawas (basis AOSP beku) =="
extract packages/modules/adb          $G/android_packages_modules_adb.git      lineage-20.0
extract art                           $A/platform/art                          refs/tags/android-13.0.0_r75
extract system/bpf                    $A/platform/system/bpf                   refs/tags/android-13.0.0_r75
extract external/perfetto             $A/platform/external/perfetto            refs/tags/android-13.0.0_r75
extract frameworks/libs/net           $A/platform/frameworks/libs/net          refs/tags/android-13.0.0_r75
extract packages/modules/NetworkStack $A/platform/packages/modules/NetworkStack refs/tags/android-13.0.0_r75

echo "== T1 — fork LineageOS, wajib =="
extract vendor/lineage                $G/android_vendor_lineage.git            lineage-20.0
extract system/core                   $G/android_system_core.git               lineage-20.0
extract system/netd                   $G/android_system_netd.git               lineage-20.0
extract packages/modules/Connectivity $G/android_packages_modules_Connectivity.git lineage-20.0
extract system/sepolicy               $G/android_system_sepolicy.git           lineage-20.0
extract device/lineage/sepolicy       $G/android_device_lineage_sepolicy.git   lineage-20.0
extract hardware/interfaces           $G/android_hardware_interfaces.git       lineage-20.0
extract frameworks/native             $G/android_frameworks_native.git         lineage-20.0
extract packages/modules/Wifi         $G/android_packages_modules_Wifi.git     lineage-20.0
extract packages/modules/Bluetooth    $G/android_packages_modules_Bluetooth.git lineage-20.0

echo "== T2 — kamera =="
extract frameworks/av                 $G/android_frameworks_av.git             lineage-20.0
extract frameworks/base               $G/android_frameworks_base.git           lineage-20.0

echo "== T3 — kondisional =="
extract bionic                        $G/android_bionic.git                    lineage-20.0
extract external/jemalloc_new         $A/platform/external/jemalloc_new        refs/tags/android-13.0.0_r75
extract hardware/qcom-caf/wlan        $G/android_hardware_qcom_wlan.git        lineage-20.0-caf

echo
echo "== ringkasan =="
cat "$SUM"
[ "$FAIL" = 0 ] && echo "SEMUA BERHASIL" || echo "ADA KEGAGALAN (rc=$FAIL)"
exit "$FAIL"
