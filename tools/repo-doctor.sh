#!/bin/bash
# repo-doctor.sh — perbaiki dua kegagalan `repo sync` yang benar-benar dialami
# saat menyiapkan tree LineageOS 20 untuk A37 (PLAN.md §0.3).
#
#   1. Sync yang terputus meninggalkan berkas UNTRACKED di direktori project yang
#      HEAD-nya belum pernah di-set. `git checkout` menolak menimpanya, dan
#      `repo sync --force-sync` TIDAK membersihkannya. Gejalanya: sync berikutnya
#      tetap gagal dengan pesan
#          error: Checking out local projects failed.
#          platform/<x> checkout <sha>
#      yang menyesatkan — <sha> itu sering objek TAG, bukan commit, sehingga
#      dugaan pertama biasanya salah alamat.
#
#   2. Penyebab awalnya: `repo sync --no-tags`. Remote `aosp` di manifest
#      LineageOS-UL dipin ke refs/tags/android-13.0.0_r75. JANGAN pakai --no-tags.
#
# Aman dijalankan berulang. Hanya menyentuh project yang HEAD-nya KOSONG —
# artinya belum pernah ada checkout berhasil, jadi tidak ada yang bisa hilang.
#
# Pakai:
#   tools/repo-doctor.sh [/path/ke/tree]     # default: /root/los20
#   tools/repo-doctor.sh --dry-run [path]

set -u

DRY=0
[ "${1:-}" = "--dry-run" ] && { DRY=1; shift; }
TREE="${1:-/root/los20}"

[ -d "$TREE/.repo" ] || { echo "bukan tree repo: $TREE" >&2; exit 1; }
cd "$TREE" || exit 1

echo "== repo-doctor: $TREE =="

mapfile -t PATHS < <(python3 - <<'PY'
import xml.etree.ElementTree as ET, glob, os
paths = set()
for f in ['.repo/manifests/default.xml'] + glob.glob('.repo/manifests/snippets/*.xml') \
         + glob.glob('.repo/local_manifests/*.xml'):
    try:
        root = ET.parse(f).getroot()
    except Exception:
        continue
    for p in root.findall('project'):
        pa = p.get('path') or p.get('name')
        if pa:
            paths.add(pa)
for p in sorted(paths):
    if os.path.isdir(p):
        print(p)
PY
)

echo "project terdeteksi : ${#PATHS[@]}"

broken=()
for p in "${PATHS[@]}"; do
    git -C "$p" rev-parse --verify HEAD >/dev/null 2>&1 || broken+=("$p")
done

echo "HEAD kosong        : ${#broken[@]}"

if [ "${#broken[@]}" -eq 0 ]; then
    echo "Tree sehat. Tidak ada yang perlu dibersihkan."
    exit 0
fi

if [ "$DRY" -eq 1 ]; then
    printf '  %s\n' "${broken[@]}" | head -40
    [ "${#broken[@]}" -gt 40 ] && echo "  ... dan $(( ${#broken[@]} - 40 )) lagi"
    echo
    echo "(dry-run — tidak ada yang diubah)"
    exit 0
fi

n=0
for p in "${broken[@]}"; do
    git -C "$p" clean -xdff >/dev/null 2>&1 && n=$((n+1))
done
echo "dibersihkan        : $n"

echo
echo "Sekarang jalankan — PERHATIKAN: tanpa --no-tags:"
echo "  cd $TREE && repo sync -c -j8 --force-sync --no-clone-bundle"
