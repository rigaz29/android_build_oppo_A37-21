#!/bin/bash
# resolve-union-conflicts.sh — selesaikan HANYA konflik yang terbukti aditif.
#
# Dipakai saat memindahkan seri patch UL ke basis official. Pola yang berulang:
# hulu official menambah entri baru ke sebuah DAFTAR (mis. SOONG_CONFIG_* di
# vendor/lineage, atau label di file_contexts), sementara revert UL mengembalikan
# entri lain ke daftar yang sama. Keduanya benar dan keduanya harus ada.
#
# ATURAN KEAMANAN: berkas di-checkout ulang dengan --conflict=diff3 sehingga sisi
# BASIS ikut terlihat. Blok hanya digabung kalau sisi basisnya KOSONG — itu bukti
# kedua pihak sama-sama hanya MENAMBAH, tidak ada yang menghapus atau mengubah.
# Kalau ada satu saja blok yang basisnya tidak kosong, skrip BERHENTI tanpa
# menyentuh apa pun dan meminta penyelesaian manual. Lebih baik berhenti daripada
# menghasilkan resolusi diam-diam yang tak terlihat siapa pun.
#
# Pakai:  tools/resolve-union-conflicts.sh <repo-dir> [berkas ...]
#         tanpa daftar berkas = semua berkas yang sedang konflik
set -u
D="${1:?repo-dir}"; shift
cd "$D" || exit 1
files="${*:-$(git diff --name-only --diff-filter=U)}"
[ -n "$files" ] || { echo "  tidak ada berkas konflik"; exit 0; }

for f in $files; do
    git checkout --conflict=diff3 -- "$f" 2>/dev/null || { echo "  !! $f: gagal checkout diff3"; exit 1; }
    # Tolak lebih dulu kalau ada blok yang sisi basisnya tidak kosong.
    bad=$(awk '
        /^<<<<<<< /{inb=0; base=0; next}
        /^\|\|\|\|\|\|\| /{inb=1; base=0; next}
        /^=======$/{if(inb && base>0) n++; inb=0; next}
        /^>>>>>>> /{next}
        inb{base++}
        END{print n+0}' "$f")
    if [ "$bad" != "0" ]; then
        echo "  !! $f: $bad blok BUKAN penambahan murni — selesaikan manual"; exit 1
    fi
    awk '
        /^<<<<<<< /{next}
        /^\|\|\|\|\|\|\| /{skip=1; next}
        /^=======$/{skip=0; next}
        /^>>>>>>> /{next}
        !skip{print}' "$f" > "$f.union" && mv "$f.union" "$f"
    git add "$f"
    echo "  ok $f: digabung (semua blok terbukti aditif)"
done
