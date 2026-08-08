#!/bin/bash
# Verifikasi ROM LOS 20 A37 SEBELUM di-flash.
#
# Memeriksa hal-hal yang kalau salah baru ketahuan sebagai "stuck di logo OPPO" —
# yaitu persis cara percobaan 19.1 lama gagal tanpa bisa didiagnosis.
#
# Pakai: ./tools/verify-rom.sh [OUT_DIR]
#        default OUT_DIR = /root/los20/out/target/product/A37

set -o pipefail
OUT="${1:-/root/los20/out/target/product/A37}"
REF="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ref"

ok()  { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
bad() { printf '\033[1;31m  X\033[0m %s\n' "$*"; fail=1; }
inf() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
fail=0

[ -d "$OUT" ] || { echo "OUT_DIR tidak ada: $OUT" >&2; exit 1; }

# ---------------------------------------------------------------- properti ---
# Dicari di SELURUH build.prop, bukan hanya system/. Dengan
# BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED := true (dipasang untuk memperbaiki
# /vendor/ueventd.rc yang tidak terbaca), 146 properti PINDAH ke
# vendor/build.prop — termasuk ro.zygote. Versi pertama skrip ini hanya membaca
# system/build.prop dan melaporkan ro.zygote hilang padahal cuma berpindah.
BPS=""
for f in "$OUT/system/build.prop" "$OUT/system/vendor/build.prop" \
         "$OUT/system/system_ext/etc/build.prop" "$OUT/system/product/etc/build.prop"; do
    [ -f "$f" ] && BPS="$BPS $f"
done
BP=$(echo $BPS | awk '{print $1}')
if [ -n "$BPS" ]; then
    inf "build.prop (dicari di $(echo $BPS | wc -w) berkas)"
    # nilai yang WAJIB dan alasannya masing-masing
    check_prop() {
        local key="$1" want="$2" why="$3"
        local got
        got=$(grep -hE "^$key=" $BPS 2>/dev/null | head -1 | cut -d= -f2-)
        if [ "$got" = "$want" ]; then ok "$key=$got"
        else bad "$key='$got', diharapkan '$want' — $why"; fi
    }
    check_prop ro.build.version.sdk 33            "LOS 20 itu Android 13, bukan 12L"
    check_prop ro.kernel.ebpf.supported false     "gerbang W1/W2; tanpa false, bpfloader menggagalkan boot"
    check_prop ro.config.low_ram true             "perangkat 2 GB, sama dengan ROM referensi"
    check_prop external_storage.casefold.enabled 0 "ext4 kernel 3.10 tidak punya casefold"
    check_prop external_storage.sdcardfs.enabled 0 "A13 memakai FUSE"
    check_prop ro.treble.enabled false            "perangkat non-treble"
    check_prop ro.zygote zygote32                 "userspace 32-bit murni"
    check_prop ro.vndk.version current            "tanpa snapshot VNDK, sama dengan ROM gt58wifi"
else
    bad "tidak ada build.prop sama sekali — build belum sampai tahap pengemasan?"
fi

# ------------------------------------------------------------------ blob ---
# Semua blob yang didaftarkan A37-vendor.mk harus benar-benar ada di image.
# Blob yang "hilang" biasanya tertelan aturan build (mis. kena filter image),
# dan baru ketahuan saat HAL-nya gagal dlopen di perangkat.
inf "blob vendor (A37-vendor.mk)"
VMK="$(cd "$OUT" && pwd)/../../../../vendor/oppo/A37/A37-vendor.mk"
# Fallback: tree yang umum dipakai
[ -f "$VMK" ] || VMK=/root/los20/vendor/oppo/A37/A37-vendor.mk
if [ -f "$VMK" ]; then
    missing=0; total=0
    # Peta partisi -> direktori di image. Non-treble: VENDOR = system/vendor.
    # Perhatian: ganti SYSTEM_EXT dulu, karena polanya mengandung SYSTEM.
    while read -r src dst; do
        [ -z "$src" ] && continue
        total=$((total+1))
        [ -f "$OUT/$dst" ] || { bad "blob hilang di image: $dst"; missing=$((missing+1)); }
    done < <(grep -oE 'vendor/oppo/A37/proprietary/[^:]+:\$\(TARGET_COPY_OUT_[A-Z]+\)/[^ \\]+' "$VMK" \
             | sed -E 's#\$\(TARGET_COPY_OUT_SYSTEM_EXT\)#system/system_ext#; s#\$\(TARGET_COPY_OUT_SYSTEM\)#system#; s#\$\(TARGET_COPY_OUT_VENDOR\)#system/vendor#; s#\$\(TARGET_COPY_OUT_PRODUCT\)#system/product#; s#\$\(TARGET_COPY_OUT_ODM\)#system/vendor/odm#' \
             | sed -E 's#vendor/oppo/A37/proprietary/([^:]+):(.*)#\1 \2#')
    [ "$missing" = 0 ] && ok "$total blob lengkap di image"
else
    bad "A37-vendor.mk tidak ditemukan ($VMK)"
fi

# ----------------------------------------------------------------- sepolicy ---
# Lokasi sepolicy hasil build harus sama dengan ROM yang boot (PLAN §5.3).
# Device ini NON-system-as-root: /sepolicy monolitik berada di RAMDISK
# (out/.../root/sepolicy), bukan di root system.img — sama seperti 19.1.
# Yang dibandingkan dengan ROM gt58wifi: keberadaan monolitik + *.cil.
inf "lokasi sepolicy"
[ -f "$OUT/root/sepolicy" ] && ok "/sepolicy monolitik di ramdisk (root/sepolicy)" \
    || bad "/sepolicy tidak ada di root/ (ramdisk)"
[ -f "$OUT/system/etc/selinux/plat_sepolicy.cil" ] && [ -f "$OUT/system/etc/selinux/plat_sepolicy_and_mapping.sha256" ] \
    && ok "system/etc/selinux berisi plat_sepolicy.cil + mapping" \
    || bad "system/etc/selinux tidak lengkap (lihat PLAN §5.3 / ref/evidence/selinux-list/)"
[ -f "$OUT/system/vendor/etc/selinux/precompiled_sepolicy" ] \
    && ok "vendor/etc/selinux/precompiled_sepolicy ada" \
    || bad "vendor/etc/selinux/precompiled_sepolicy hilang"

# ------------------------------------------------------------------- adbd ---
# Tanpa Gerrit 326385, adbd A12 memakai deskriptor FunctionFS v2/v3 yang tidak
# dipahami f_fs kernel 3.10 -> USB TIDAK PERNAH enumerasi, sejauh apa pun boot
# berhasil. Inilah sebabnya "adb devices kosong" di percobaan lama bukan bukti
# init mati awal.
# CATATAN: skrip ini jalan dengan `set -o pipefail`, jadi JANGAN `cmd | grep -q`.
# grep -q keluar di match pertama, `strings` di hulu kena SIGPIPE (exit 141), dan
# pipefail menggagalkan pipeline yang sebenarnya BERHASIL. Versi pertama skrip ini
# melaporkan "adbd TIDAK memuat transport_legacy.cpp" padahal binernya memuatnya —
# jebakan yang sama sudah terdokumentasi di tools/build-kernel-zip.sh, lalu
# terulang di sini. grep -c membaca sampai habis, jadi aman.
count_in() { grep -cF -- "$2" < <(strings -a "$1") 2>/dev/null || true; }

inf "adbd legacy FunctionFS (Gerrit 326385)"
ADBD=$(find "$OUT/system" -name adbd -type f 2>/dev/null | head -1)
if [ -z "$ADBD" ]; then
    bad "adbd tidak ditemukan di image"
else
    n_t=$(count_in "$ADBD" "transport_legacy.cpp")
    n_u=$(count_in "$ADBD" "daemon/usb_legacy.cpp")
    n_m=$(count_in "$ADBD" "using legacy FunctionFS")
    if [ "$n_t" -gt 0 ] && [ "$n_u" -gt 0 ] && [ "$n_m" -gt 0 ]; then
        ok "adbd memuat jalur legacy FunctionFS (transport_legacy + usb_legacy + pesan usb_init)"
    else
        bad "adbd TIDAK lengkap memuat jalur legacy (transport=$n_t usb=$n_u pesan=$n_m) — repopick 326385 hilang, adb tidak akan pernah muncul"
    fi
fi

# ------------------------------------------------------------------ kernel ---
inf "boot.img"
BOOT="$OUT/boot.img"
if [ -f "$BOOT" ]; then
    read -r _ ks ka rs ra ss sa ta ps dt _ < <(python3 - "$BOOT" <<'PY'
import struct,sys
d=open(sys.argv[1],'rb').read(1648)
print('x', *struct.unpack('<10I', d[8:48]))
PY
)
    [ "$ps" = 2048 ] && ok "pagesize $ps" || bad "pagesize $ps, diharapkan 2048"
    [ "$ka" = 2147516416 ] && ok "kernel_addr 0x80008000 (base 0x80000000)" || bad "kernel_addr $ka"
    if [ "$dt" -gt 200000 ] && [ "$dt" -lt 220000 ]; then ok "dt_size $dt (referensi 210944)"
    else bad "dt_size $dt jauh dari referensi 210944"; fi
else
    bad "boot.img tidak ada"
fi

# --------------------------------------------------------------------- zip ---
inf "paket"
ZIP=$(ls -t "$OUT"/lineage-20.0-*.zip 2>/dev/null | head -1)
if [ -n "$ZIP" ]; then
    ok "$(basename "$ZIP") ($(du -h "$ZIP" | cut -f1))"
    case "$(basename "$ZIP")" in
        *microG*|*ReSukiSU*) bad "nama ROM tercemar env sisa proyek lain — source tools/envsetup-a37.sh" ;;
    esac
else
    bad "zip ROM tidak ditemukan"
fi

echo
if [ "$fail" = 0 ]; then
    printf '\033[1;32mSEMUA VERIFIKASI LOLOS\033[0m — aman dilanjut ke protokol flash §9.1 (recovery dulu).\n'
else
    printf '\033[1;31mADA YANG GAGAL\033[0m — perbaiki sebelum flash.\n'; exit 1
fi
