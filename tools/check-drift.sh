#!/bin/bash
# check-drift.sh — deteksi project yang HANYUT dari era LineageOS-UL.
#
# ================================ MASALAHNYA =================================
# Manifest LineageOS-UL menyematkan project ke BRANCH, bukan SHA:
#     <default revision="refs/heads/lineage-20.0" ... />
# Lini UL sendiri BEKU sejak 2025-04-04 (seluruh branch: 19.1, 20.0, 21.0),
# tapi repo LineageOS hulu TERUS BERGERAK di branch bernama sama. Jadi
# `repo sync` diam-diam menarik kode yang jauh lebih baru daripada fork UL yang
# mengelilinginya.
#
# Ini bukan teori. Fase 2 (5 Agustus 2026) memutus build karena persis ini:
#   external/dng_sdk commit 624d019 (2025-12-12) menambah sdk_version:"current"
#   pada libdng_sdk + dependensi libjpeg; libjpeg (AOSP, dipin ke tag
#   android-13.0.0_r75) tidak punya varian sdk:sdk, soong berhenti.
#
# Skrip ini melaporkan project mana saja yang bergerak melewati tanggal batas,
# supaya kandidat penyebab bisa dilihat SEBELUM menghabiskan waktu men-debug
# kode yang sebenarnya tidak salah.
#
# Yang TIDAK dilaporkan (memang stabil):
#   - remote "aosp"  -> dipin ke refs/tags/android-13.0.0_r75
#   - project yang revision-nya sudah berupa SHA 40 karakter
#
# Pemakaian:
#   tools/check-drift.sh [/path/ke/tree] [YYYY-MM-DD]
#   default: /root/los20  2025-05-01   (sebulan setelah UL beku)
#
# Kolom "dibangun?" cuma heuristik kasar: project di lineage/*, dan repo
# dokumentasi seperti wiki/website/scripts/charter/hudson/mirror/crowdin tidak
# ikut masuk ROM, jadi hanyutnya tidak berbahaya.

set -u
TREE="${1:-/root/los20}"
CUT="${2:-2025-05-01}"

[ -d "$TREE/.repo" ] || { echo "bukan tree repo: $TREE" >&2; exit 1; }
cd "$TREE" || exit 1

echo "== check-drift : $TREE (batas $CUT) =="
echo

TREE="$TREE" CUT="$CUT" python3 - <<'PY'
import xml.etree.ElementTree as ET, subprocess, os, glob, datetime, sys

cut = datetime.date.fromisoformat(os.environ['CUT'])
NOT_BUILT = ('lineage/', 'external/chromium-webview/patches')

proj = {}
for f in ['.repo/manifests/default.xml'] + glob.glob('.repo/manifests/snippets/*.xml') \
         + glob.glob('.repo/local_manifests/*.xml'):
    try:
        root = ET.parse(f).getroot()
    except Exception:
        continue
    for p in root.findall('project'):
        path = p.get('path') or p.get('name')
        if path:
            proj[path] = (p.get('name'), p.get('remote') or 'github', p.get('revision'))

drift, pinned, skipped = [], 0, 0
for path, (name, remote, rev) in proj.items():
    if not os.path.isdir(path):
        continue
    if remote == 'aosp':
        skipped += 1
        continue
    if rev and len(rev) == 40:
        pinned += 1
        continue
    r = subprocess.run(['git', '-C', path, 'log', '-1', '--format=%cs'],
                       capture_output=True, text=True)
    if r.returncode:
        continue
    try:
        d = datetime.date.fromisoformat(r.stdout.strip())
    except ValueError:
        continue
    if d > cut:
        drift.append((d, path, name))

drift.sort(reverse=True)
risky = [x for x in drift if not x[1].startswith(NOT_BUILT)]

print(f"  dipin ke SHA (aman)        : {pinned}")
print(f"  remote aosp / tag (aman)   : {skipped}")
print(f"  HANYUT melewati {cut}   : {len(drift)}  (dibangun: {len(risky)})")
print()

if risky:
    print("  -- hanyut DAN ikut dibangun (periksa ini kalau build putus) --")
    for d, path, name in risky:
        print(f"    {d}  {path:<44} {name}")
    print()

quiet = [x for x in drift if x[1].startswith(NOT_BUILT)]
if quiet:
    print(f"  -- hanyut tapi TIDAK masuk ROM ({len(quiet)}), abaikan --")
    print("    " + ", ".join(sorted(p for _, p, _ in quiet)))
    print()

print("  Cara memin sebuah project: tambahkan di A37-20.xml")
print("    <remove-project name=\"LineageOS/android_xxx\" />")
print("    <project name=\"LineageOS/android_xxx\" path=\"...\" remote=\"gh\"")
print("             revision=\"<sha 40 karakter>\" upstream=\"lineage-20.0\" />")
print()
print("  Pin HANYA yang terbukti memutus build. Memin semuanya secara preventif")
print("  ikut membekukan perbaikan keamanan aplikasi yang masih sah.")
sys.exit(0)
PY
