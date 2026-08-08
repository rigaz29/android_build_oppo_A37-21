#!/bin/bash
# apply-a37-patches.sh — LineageOS 21 / OPPO A37
#
# WAJIB dijalankan ulang setiap habis `repo sync`.
#
# Pemakaian: tools/apply-a37-patches.sh [--check] [/path/ke/tree]   default /root/los21
set -u
CHECK=0; [ "${1:-}" = "--check" ] && { CHECK=1; shift; }
TREE="${1:-/root/los21}"
ok(){ printf '\033[1;32m ok\033[0m %s\n' "$1"; }; do_(){ printf '\033[1;34m ::\033[0m %s\n' "$1"; }
no(){ printf '\033[1;31m !!\033[0m %s\n' "$1"; }
[ -d "$TREE/.repo" ] || { no "bukan tree repo: $TREE"; exit 1; }
cd "$TREE" || exit 1
echo "== apply-a37-patches (LineageOS 21) : $TREE =="; rc=0

# --- 1. guard hardware/qcom-caf/msm8916/Android.mk -------------------------
# Tanpa berkas ini, first-makefiles-under tidak pernah dipanggil untuk
# qcom-caf/msm8916, sehingga libOmxCore/libmm-omxcore/libstagefrighthw dan
# seluruh modul audio/display/media msm8916 dilaporkan "tidak ada" oleh
# enforce-product-packages-exist. Terbukti di Fase 2 (8 Agustus 2026):
# memasang guard ini menurunkan modul hilang dari 11 jadi 0.
SRC=hardware/qcom-caf/common/os_pickup.mk
DST=hardware/qcom-caf/msm8916/Android.mk
if [ ! -d hardware/qcom-caf/msm8916 ]; then
    no "hardware/qcom-caf/msm8916 tidak ada -- periksa A37-21.xml lalu repo sync"; rc=1
elif [ -f "$DST" ] && cmp -s "$SRC" "$DST"; then ok "guard qcom-caf/msm8916/Android.mk: sudah terpasang"
elif [ "$CHECK" = 1 ]; then do_ "guard qcom-caf/msm8916/Android.mk: PERLU dipasang"
elif [ -f "$SRC" ]; then cp "$SRC" "$DST" && ok "guard qcom-caf/msm8916/Android.mk: dipasang" || { no "gagal menyalin"; rc=1; }
else no "$SRC tidak ada"; rc=1; fi

# --- 2. seri patch frameworks/av (kamera HAL1) -----------------------------
P=/root/a37-21/patches/frameworks_av
if [ ! -d frameworks/av ]; then no "frameworks/av tidak ada"; rc=1
elif git -C frameworks/av log --oneline -1 --grep="restore HAL1 support" | grep -q .; then
    ok "kamera: patch HAL1 sudah terpasang"
elif [ "$CHECK" = 1 ]; then do_ "kamera: PERLU terapkan $P/0001-*.patch"
else
    do_ "kamera: terapkan seri $P"
    if git -C frameworks/av am "$P"/*.patch >/dev/null 2>&1; then ok "kamera: seri terpasang"
    else git -C frameworks/av am --abort >/dev/null 2>&1; no "kamera: git am GAGAL -- selesaikan manual"; rc=1; fi
fi

# --- 3. penjaga regresi ----------------------------------------------------
echo; echo "-- penjaga regresi --"
c(){ if [ -e "$1" ]; then ok "$2"; else no "$2 -- HILANG"; rc=1; fi; }
c frameworks/native/libs/renderengine/gl \
  "RenderEngine GLES ada (tanpa ini Adreno 306 dipaksa Skia -> SF crash, bug 10.B)"
c frameworks/av/services/camera/libcameraservice/device1 \
  "camera device1/ ada (jalur HAL1)"
c hardware/interfaces/camera/device/1.0/ICameraDevice.hal \
  "HIDL camera device 1.0 masih ada di A14"
echo
[ "$rc" = 0 ] && ok "selesai" || no "selesai dengan peringatan (rc=$rc)"
exit $rc
