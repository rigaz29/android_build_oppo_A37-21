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

# --- 3. seri patch frameworks/native (RenderEngine GLES) -------------------
# 9 commit dari LineageOS-UL/android_frameworks_native lineage-21.0,
# f8ba66e97fc7^..e9f7d5b89491. Android 14 mencabut backend GLES non-Skia; tanpa
# seri ini debug.renderengine.backend=gles (device.mk:129) tidak dikenali dan
# SurfaceFlinger jatuh ke SkiaGL -> bug 10.B di Adreno 306.
#
# Bahwa perangkat ini BENAR-BENAR memakai GLESRenderEngine bukan dugaan:
# `dumpsys SurfaceFlinger` pada ROM proyek 20 yang terpasang mencetak
# "RenderEngine program cache size for unprotected context" dan
# "RenderEngine framebuffer image cache size" — string yang hanya ada di
# gl/GLESRenderEngine.cpp:1584/1601 dan NIHIL di seluruh skia/.
#
# Patch 0002 (Revert "Delete (most) sf fuzzers") ikut serta bukan karena kita
# butuh fuzzer, melainkan karena 0003 dan 0004 menyunting berkas-berkas itu.
# Fuzzer tidak ada di PRODUCT_PACKAGES, jadi tidak ikut terbangun.
#
# 0004 di-resolve manual: official punya mNeedsPostRenderCleanup yang tidak
# dikenal UL, sementara revert mengembalikan useFramebufferCache. Keduanya
# dipertahankan — resolusinya sudah ikut terbawa di berkas patch ini.
P=/root/a37-21/patches/frameworks_native
if [ ! -d frameworks/native ]; then no "frameworks/native tidak ada"; rc=1
elif git -C frameworks/native log --oneline -1 --grep="renderengine, gles: convert to c_str" | grep -q .; then
    ok "renderengine: seri GLES sudah terpasang"
elif [ "$CHECK" = 1 ]; then do_ "renderengine: PERLU terapkan seri $P (9 patch)"
else
    do_ "renderengine: terapkan seri $P"
    if git -C frameworks/native am "$P"/*.patch >/dev/null 2>&1; then ok "renderengine: seri terpasang"
    else git -C frameworks/native am --abort >/dev/null 2>&1; no "renderengine: git am GAGAL -- selesaikan manual"; rc=1; fi
fi

# --- 4. penjaga regresi ----------------------------------------------------
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
