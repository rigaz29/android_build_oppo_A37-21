#!/bin/bash
# Selaraskan waktu repo LineageOS official ke titik beku LineageOS-UL.
#
# MASALAH YANG DISELESAIKAN
#
# Manifest UL lineage-21.0 beku 2025-04-04, tapi `<default revision=
# "refs/heads/lineage-21.0">` membuat repo yang TIDAK di-fork UL melacak TIP
# LineageOS official. Saat UL beku, official juga di April 2025 — jadi manifest
# itu konsisten PADA WAKTUNYA. Men-sync-nya 16 bulan kemudian menarik 16 bulan
# drift official ke dalam basis yang beku, dan API di titik temunya berselisih.
#
# Gejalanya berupa kegagalan build yang tampak acak, misalnya:
#   lineage-sdk … does not override abstract method onBeforeUserSwitching(int)
#   IntentResolver … no suitable method found for resolveActivityAsUser(…,int,int)
#
# Repo AOSP TIDAK terpengaruh: remote `aosp` mem-pin
# revision="refs/tags/android-14.0.0_r67", jadi 1168 repo itu memang beku.
# Fork UL juga tidak terpengaruh — mereka beku secara alami.
#
# ⚠️⚠️ JANGAN JALANKAN INI SECARA MENYELURUH. DEFAULT-NYA DRY RUN. ⚠️⚠️
#
# Penyelarasan tanggal menyeluruh SUDAH DICOBA 11 Agustus 2026 dan HASILNYA
# BURUK. Menggulung 45 repo ke <= 2025-04-04:
#
#   memperbaiki  lineage-sdk                       onBeforeUserSwitching
#   memperbaiki  packages/modules/IntentResolver   resolveActivityAsUser
#   MERUSAK      packages/modules/Wifi             soong UL sudah cabut `pdk`
#   MERUSAK      packages/providers/MediaProvider  framework-pdf belum ada
#   41 lainnya   tidak teruji, tiap satu ranjau
#
# Asumsi yang gugur: "saat UL beku, official juga di April 2025, jadi konsisten
# pada waktunya." TIDAK. Fork UL sebagian MENDAHULUI official (soong mencabut
# `pdk` lebih dulu) dan sebagian TERTINGGAL. Basis UL bukan snapshot koheren dari
# satu titik waktu, jadi tidak ada satu tanggal yang menyelaraskan semuanya.
#
# YANG BENAR: gulung HANYA repo yang terbukti bermasalah, dibuktikan oleh
# kegagalan build nyata. Skrip ini dipertahankan untuk MENGUKUR skew (DRY=1),
# bukan untuk menerapkannya.
#
# YANG DILAKUKAN
#
# Untuk setiap repo dengan remote LineageOS official yang HEAD-nya melewati
# tanggal batas, checkout commit terakhir SEBELUM batas itu. Mekanis, dan bisa
# dibalik dengan `repo sync`.
#
# YANG SENGAJA DILEWATI
#   - repo yang punya commit lokal (pekerjaan kita) — dilaporkan, tidak disentuh
#   - repo yang tidak punya commit sebelum batas (branch-nya lahir lebih baru)
#   - repo milik proyek (rigaz29/*) dan fork UL
set -u
TREE="${TREE:-/root/los21}"
BATAS="${BATAS:-2025-04-05}"     # eksklusif: ambil commit terakhir SEBELUM ini
BRANCH="${BRANCH:-github/lineage-21.0}"
DRY="${DRY:-1}"      # default DRY RUN — lihat peringatan di atas

cd "$TREE" || exit 1
gulung=0; lewat_lokal=0; lewat_tanpa_target=0

for p in $(repo list -p 2>/dev/null); do
    [ -d "$p/.git" ] || continue
    url=$(git -C "$p" config --get remote.github.url 2>/dev/null)
    case "$url" in *LineageOS/*) ;; *) continue ;; esac

    now=$(git -C "$p" log -1 --format=%cd --date=short 2>/dev/null)
    [ "$now" \> "${BATAS%??}04" ] || continue

    tgt=$(git -C "$p" rev-list -1 --before="$BATAS" "$BRANCH" 2>/dev/null)
    if [ -z "$tgt" ]; then
        echo "  LEWAT (tanpa target)  $p"
        lewat_tanpa_target=$((lewat_tanpa_target+1)); continue
    fi

    head=$(git -C "$p" rev-parse HEAD 2>/dev/null)
    [ "$tgt" = "$head" ] && continue

    lokal=$(git -C "$p" log --oneline "$BRANCH"..HEAD 2>/dev/null | wc -l)
    if [ "$lokal" -gt 0 ]; then
        echo "  LEWAT (commit lokal: $lokal)  $p"
        lewat_lokal=$((lewat_lokal+1)); continue
    fi

    if [ "$DRY" = "1" ]; then
        echo "  akan gulung  $p  $now -> $(git -C "$p" log -1 --format=%cd --date=short "$tgt")"
    else
        git -C "$p" checkout -q --detach "$tgt" 2>/dev/null \
            && echo "  digulung  $p  $now -> $(git -C "$p" log -1 --format=%cd --date=short HEAD)" \
            || echo "  GAGAL  $p"
    fi
    gulung=$((gulung+1))
done

echo "---"
echo "digulung: $gulung | lewat karena commit lokal: $lewat_lokal | lewat tanpa target: $lewat_tanpa_target"
