#!/bin/bash
# Bangun kernel A37 (arm64) dan bungkus jadi zip AnyKernel3 yang bisa di-flash.
#
# Dipakai untuk menguji SETIAP perubahan kode kernel tanpa membangun ROM penuh.
# Zip-nya mengganti Image + dt.img di dalam boot.img yang sudah ada dan
# MEMBIARKAN ramdisk apa adanya (split_boot, bukan dump_boot) — jadi zip yang
# sama bisa diuji di atas ROM 17.1, 18.1, maupun 19.1 yang sudah terpasang.
#
# Kenapa itu penting: boot.img = kernel + ramdisk + dt, dan ramdisk spesifik per
# versi Android. Mem-flash boot.img 19.1 utuh ke 18.1 menjalankan init 19.1 di
# atas /system 18.1 — gagalnya karena hal yang bukan kernel, jadi tidak menjawab
# apa pun. Mengganti kernelnya saja mengisolasi satu variabel.
#
# Pemakaian:
#   ./tools/build-kernel-zip.sh                 # build inkremental + bungkus
#   ./tools/build-kernel-zip.sh --clean         # buang out/ dulu
#   ./tools/build-kernel-zip.sh --zip-only      # bungkus ulang tanpa kompilasi
#   ./tools/build-kernel-zip.sh --check-only    # cuma verifikasi, tanpa bungkus
#   ./tools/build-kernel-zip.sh --from-rom      # bungkus kernel HASIL BUILD ROM
#
# --from-rom memakai out/target/product/A37/{kernel,dt.img} dari build ROM,
# BUKAN hasil kompilasi mandiri skrip ini. Pakai mode ini kalau yang mau diuji
# adalah kernel yang benar-benar akan dikirim di ROM: keduanya TIDAK identik
# (sha256 berbeda) karena lingkungan build berbeda — compile.h membawa timestamp
# dan CONFIG_LOCALVERSION_AUTO menempelkan hash git.
#
# Override lewat environment:
#   KDIR=/path/ke/kernel   tree kernel (default: work/a37-kernel)
#   TC=/path/ke/toolchain  direktori bin toolchain
#   JOBS=8                 paralelisme make
#   DEFCONFIG=...          default: lineageos_a37f_defconfig

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KDIR="${KDIR:-$HERE/work/a37-kernel}"
TC="${TC:-$HERE/work/tc/aarch64-4.9/bin}"
WORK="${WORK:-$HERE/work}"
OUT="$KDIR/out"
CFG="$OUT/.config"
SYSMAP="$OUT/System.map"
JOBS="${JOBS:-$(nproc --all)}"
DEFCONFIG="${DEFCONFIG:-lineageos_a37f_defconfig}"
REFCFG="$HERE/ref/evidence/kernel-config-reference.txt"
DTBTOOL_SRC="${DTBTOOL_SRC:-$HERE/research/dt-rigaz29-19.1/dtbtool/dtbtool.c}"
AK3_REPO="https://github.com/osm0sis/AnyKernel3.git"
TC_REPO="https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git"

DO_BUILD=1 DO_ZIP=1 DO_CLEAN=0 FROM_ROM=""
while [ $# -gt 0 ]; do
    case "$1" in
        --clean)      DO_CLEAN=1 ;;
        --zip-only)   DO_BUILD=0 ;;
        --check-only) DO_ZIP=0 ;;
        # Direktori opsional. `shift` tambahan HANYA kalau argumen berikutnya
        # memang ada dan bukan opsi lain — kalau tidak, shift kedua di akhir loop
        # gagal dengan "shift count out of range" dan `set -e` membunuh skrip
        # tanpa satu pun pesan.
        --from-rom)
            if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then
                FROM_ROM="$2"; shift
            else
                FROM_ROM="/root/los19/out/target/product/A37"
            fi
            ;;
        -h|--help)    sed -n '2,32p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "opsi tidak dikenal: $1" >&2; exit 2 ;;
    esac
    shift
done

c_i() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
c_ok() { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
c_wr() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mGAGAL:\033[0m %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------
# 0. Prasyarat
# --------------------------------------------------------------------------
[ -d "$KDIR" ] || die "tree kernel tidak ada: $KDIR
  git clone -b lineage-19.1 https://github.com/rigaz29/kernel_oppo_msm8939.git $KDIR"

if [ ! -x "$TC/aarch64-linux-android-gcc" ]; then
    c_i "Toolchain belum ada, clone gcc 4.9 (kompiler yang sama dengan kernel ROM referensi)"
    git clone -q --depth 1 "$TC_REPO" "$(dirname "$TC")"
fi
[ -x "$TC/aarch64-linux-android-gcc" ] || die "toolchain tidak tersedia di $TC"

export ARCH=arm64
export CROSS_COMPILE="$TC/aarch64-linux-android-"

cd "$KDIR"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
DIRTY=""
git diff-index --quiet HEAD -- 2>/dev/null || DIRTY="-dirty"
c_i "Kernel $BRANCH @ $SHA$DIRTY"

# --------------------------------------------------------------------------
# 1. Kompilasi
# --------------------------------------------------------------------------
if [ "$DO_CLEAN" = 1 ]; then
    c_i "Membuang $OUT"
    rm -rf "$OUT"
fi

if [ -n "$FROM_ROM" ]; then
    DO_BUILD=0
    [ -s "$FROM_ROM/kernel" ] || die "kernel hasil build ROM tidak ada: $FROM_ROM/kernel"
    [ -s "$FROM_ROM/dt.img" ] || die "dt.img hasil build ROM tidak ada: $FROM_ROM/dt.img"
    # System.map dan .config kernel build ROM ada di obj/KERNEL_OBJ, bukan di
    # out/ milik skrip ini.
    # Ditulis if/then, BUKAN `[ ... ] && VAR=...`: di bawah `set -e`, bentuk &&
    # yang tesnya gagal menjadikan seluruh perintah bernilai non-zero dan skrip
    # mati diam-diam tanpa satu pun pesan.
    K="$FROM_ROM/obj/KERNEL_OBJ"
    if [ -s "$K/System.map" ]; then SYSMAP="$K/System.map"; fi
    if [ -s "$K/.config" ];    then CFG="$K/.config"; fi
    c_i "Memakai artefak build ROM dari $FROM_ROM"
fi

if [ "$DO_BUILD" = 1 ]; then
    # Kernel 3.10 tidak membuat direktori O= sendiri. Modul soong
    # generated_kernel_includes menghapusnya lebih dulu, dan itulah cacat #4 di
    # percobaan 19.1 yang lama — lolos dari empat build manual karena skrip
    # membuatkan direktorinya. Kita buat eksplisit di sini juga.
    mkdir -p "$OUT"

    [ -f "$CFG" ] || { c_i "make $DEFCONFIG"; make -s O="$OUT" "$DEFCONFIG"; }

    c_i "make Image dtbs -j$JOBS"
    make -s O="$OUT" -j"$JOBS" Image dtbs
fi

if [ -n "$FROM_ROM" ]; then
    IMAGE="$FROM_ROM/kernel"
else
    IMAGE="$OUT/arch/arm64/boot/Image"
fi
[ -s "$IMAGE" ] || die "Image tidak terbentuk: $IMAGE"

# --------------------------------------------------------------------------
# 2. dt.img (QCDT) — A37 memakai DT terpisah di dalam header boot.img
# --------------------------------------------------------------------------
if [ -n "$FROM_ROM" ]; then
    cp "$FROM_ROM/dt.img" "$WORK/dt.img"
    c_i "dt.img disalin dari build ROM"
else
DTBTOOL="$WORK/dtbToolOppo"
if [ ! -x "$DTBTOOL" ]; then
    [ -f "$DTBTOOL_SRC" ] || die "sumber dtbtool tidak ada: $DTBTOOL_SRC
  Ambil dari device tree: device/oppo/A37/dtbtool/dtbtool.c
  (catatan: /root/los18 sudah dipangkas, device/ dan prebuilts/ hilang)"
    c_i "Kompilasi dtbToolOppo"
    g++ -w -O2 -o "$DTBTOOL" "$DTBTOOL_SRC"
fi

c_i "Membuat dt.img"
"$DTBTOOL" -o "$WORK/dt.img" -s 2048 -p "$OUT/scripts/dtc/" "$OUT/arch/arm64/boot/dts/" >/dev/null
fi
[ -s "$WORK/dt.img" ] || die "dt.img gagal dibuat"

# --------------------------------------------------------------------------
# 3. Verifikasi — murah, dan menangkap kelas kegagalan yang mahal kalau lolos
# --------------------------------------------------------------------------
fail=0

# Catatan: skrip ini jalan dengan `set -o pipefail`, jadi JANGAN memakai
# `cmd | grep -q`. grep -q keluar begitu ketemu match pertama, cmd di hulu kena
# SIGPIPE (exit 141), dan pipefail menjadikan seluruh pipeline gagal — hasilnya
# verifikasi yang lolos malah dilaporkan gagal. grep -c membaca sampai habis,
# jadi aman.
count_in() { grep -cF -- "$2" < <(strings -a "$1") 2>/dev/null || true; }

[ "$(head -c4 "$WORK/dt.img")" = "QCDT" ] || { c_wr "dt.img bukan QCDT"; fail=1; }

dtsz=$(stat -c%s "$WORK/dt.img")
if [ "$dtsz" -eq 210944 ]; then
    c_ok "dt.img $dtsz byte — sama dengan ROM referensi"
else
    c_wr "dt.img $dtsz byte, ROM referensi 210944. Beda ukuran belum tentu salah,"
    c_wr "  tapi periksa apakah jumlah DTS yang terkompilasi berubah."
fi

IMGDESC=$(file -b "$IMAGE")
case "$IMGDESC" in
    *ARM64*) c_ok "Image $(stat -c%s "$IMAGE") byte, ${IMGDESC%%,*}" ;;
    *)       c_wr "Image BUKAN ARM64 ($IMGDESC) — jangan di-flash"; fail=1 ;;
esac

# Binder modern harus benar-benar ikut ter-link, bukan cuma ada di source.
# Diperiksa lewat System.map, bukan string __FILE__ di dalam Image: __FILE__
# hanya tertanam kalau CONFIG_DEBUG_BUGVERBOSE menyala, jadi cek berbasis
# string rapuh terhadap perubahan defconfig. Simbol selalu ada.
nsym=$(grep -c " [Tt] binder_alloc" "$SYSMAP" 2>/dev/null || true)
if [ "${nsym:-0}" -gt 0 ]; then
    c_ok "binder_alloc ter-link ($nsym simbol di System.map)"
else
    c_wr "binder_alloc TIDAK ter-link — CONFIG_ANDROID_BINDER_IPC mati?"
    fail=1
fi

# Fitur binder yang justru jadi alasan backport: security context untuk keystore2.
if [ "$(count_in "$IMAGE" BINDER_SET_CONTEXT_MGR)" -gt 0 ]; then
    c_ok "binder membawa jalur BINDER_SET_CONTEXT_MGR (security context A12)"
else
    c_wr "jalur security context tidak terdeteksi di Image"
fi

# Simbol yang menentukan boot Android 12. Dibandingkan ke .config hasil build,
# bukan ke defconfig: di arm64 sebagian di-select lewat Kconfig dan tidak
# pernah tertulis di defconfig.
check_cfg() {
    local sym="$1" want="$2"
    if grep -qx "CONFIG_$sym=$want" "$CFG"; then
        c_ok "CONFIG_$sym=$want"
    else
        c_wr "CONFIG_$sym bukan '$want' (ada: $(grep -E "^(# )?CONFIG_$sym[ =]" "$CFG" || echo tidak-ada))"
        fail=1
    fi
}
check_cfg SECCOMP_FILTER y            # zygote A12 memasang filter seccomp
check_cfg ANDROID_BINDER_IPC y
check_cfg PSTORE_RAM y                # ramoops = tulang punggung diagnosis
check_cfg IKCONFIG_PROC y             # /proc/config.gz untuk verifikasi di device

# lmkd butuh SATU sumber tekanan memori. Keduanya mati = lmkd tanpa masukan.
if grep -qx "CONFIG_MEMCG=y" "$CFG" || grep -qx "CONFIG_ANDROID_LOW_MEMORY_KILLER=y" "$CFG"; then
    c_ok "jalur LMK punya sumber tekanan (MEMCG atau LMK in-kernel)"
else
    c_wr "MEMCG dan ANDROID_LOW_MEMORY_KILLER dua-duanya mati — lmkd tidak punya masukan"
    fail=1
fi

# Bandingkan dengan kernel ROM referensi yang terbukti boot Android 12.
if [ -f "$REFCFG" ]; then
    for sym in ARM64 COMPAT ANDROID_BINDER_IPC SECCOMP_FILTER PSTORE_RAM FUSE_FS; do
        r=$(grep -E "^(# )?CONFIG_$sym[ =]" "$REFCFG" | head -1 || true)
        o=$(grep -E "^(# )?CONFIG_$sym[ =]" "$CFG" | head -1 || true)
        [ "$r" = "$o" ] || c_wr "beda dari referensi: [$sym] referensi='$r' kita='$o'"
    done
fi

[ "$fail" = 0 ] || die "verifikasi gagal — lihat tanda ! di atas"
c_ok "semua verifikasi lolos"

[ "$DO_ZIP" = 1 ] || exit 0

# --------------------------------------------------------------------------
# 4. Bungkus AnyKernel3
# --------------------------------------------------------------------------
AK3="$WORK/ak3" ZIPDIR="$WORK/zip"
[ -d "$AK3/.git" ] || { c_i "Clone AnyKernel3"; git clone -q --depth 1 "$AK3_REPO" "$AK3"; }

rm -rf "$ZIPDIR"
cp -r "$AK3" "$ZIPDIR"
rm -rf "$ZIPDIR/.git" "$ZIPDIR/.github" "$ZIPDIR/README.md" "$ZIPDIR/modules" "$ZIPDIR/patch"

cp "$IMAGE" "$ZIPDIR/Image"
cp "$WORK/dt.img" "$ZIPDIR/dt.img"
chmod 644 "$ZIPDIR/Image" "$ZIPDIR/dt.img"

KVER=$(make -s O="$OUT" kernelrelease 2>/dev/null | tail -1 || echo 3.10.108)
# CONFIG_LOCALVERSION_AUTO menempelkan "-g<sha>" ke kernelrelease. Buang di sini
# supaya nama zip tidak memuat SHA dua kali (kita tambahkan branch+sha sendiri).
KVER_SHORT="${KVER%-g*}"

# Konfigurasi ini sudah terbukti mem-flash di A37 lewat build-kernel.sh proyek
# 17.1/18.1 — block, nama device, dan split_boot/flash_boot jangan diubah tanpa
# alasan. AnyKernel3 memungut dt.img di root zip dan memakainya sebagai --dt
# saat repack.
cat > "$ZIPDIR/anykernel.sh" <<AKEOF
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
properties() { '
kernel.string=Kernel ${KVER} (${BRANCH} ${SHA}${DIRTY}) untuk OPPO A37/A37f/A37fw
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=A37
device.name2=A37f
device.name3=A37fw
device.name4=a37f
device.name5=a37fw
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
boot_attributes() {
set_perm_recursive 0 0 755 644 \$RAMDISK/*;
set_perm_recursive 0 0 750 750 \$RAMDISK/init* \$RAMDISK/sbin;
} # end attributes

BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

# split_boot (bukan dump_boot) karena ramdisk tidak disentuh sama sekali:
# hanya Image dan dt yang diganti, sisa boot.img dipakai ulang apa adanya.
# Inilah yang membuat zip ini aman diuji di atas 17.1 / 18.1 / 19.1.
split_boot;
flash_boot;
AKEOF

ZIP="$WORK/A37-kernel-${KVER_SHORT}-${BRANCH}-${SHA}${DIRTY}-$(date +%Y%m%d-%H%M).zip"
rm -f "$ZIP"
( cd "$ZIPDIR" && zip -qr9 "$ZIP" . -x ".git*" )

ZIPLIST=$(unzip -l "$ZIP")
case "$ZIPLIST" in *" Image"*) ;; *) die "Image tidak masuk zip" ;; esac
case "$ZIPLIST" in *"dt.img"*) ;; *) die "dt.img tidak masuk zip" ;; esac

echo
c_ok "Zip siap"
ls -lh "$ZIP"
sha256sum "$ZIP"
echo
cat <<'NOTE'
Cara uji (urutan ini disengaja):
  1. Backup boot.img yang sekarang lewat recovery, atau siapkan zip kernel lama
     sebagai jalan pulang.
  2. Flash zip ini dari recovery di atas ROM yang SUDAH terpasang (18.1 paling
     dekat ke 19.1, dan itu baseline yang terbukti).
  3. Boot normal  -> binder tidak regresi di userspace Android nyata.
     Bootloop      -> tahan Power sampai reboot, masuk recovery, ambil:
                      adb shell cat /sys/fs/pstore/console-ramoops-0
     Lalu flash balik kernel lama.

Yang TIDAK dibuktikan tes ini: jalur security context Android 12. keystore2
hanya ada di A12; A11 memakai keystore1 dan tidak pernah menyetel
FLAT_BINDER_FLAG_TXN_SECURITY_CTX. Boot mulus di 18.1 = tidak ada regresi,
bukan fitur A12-nya benar.
NOTE
