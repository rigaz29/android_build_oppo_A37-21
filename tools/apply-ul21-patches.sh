#!/bin/bash
# apply-ul21-patches.sh — terapkan seri patch UL 21 (patches/ul21/<repo>/) ke tree.
#
# Idempoten: repo yang commit terakhirnya sudah cocok dengan patch terakhir
# dilewati. Konflik TIDAK diselesaikan otomatis -- di-abort dan dilaporkan,
# supaya tidak ada resolusi diam-diam yang tak terlihat.
set -u
TREE="${TREE:-/root/los21}"
P="${P:-/root/a37-21/patches/ul21}"
ok(){ printf '\033[1;32m ok\033[0m %s\n' "$1"; }
no(){ printf '\033[1;31m !!\033[0m %s\n' "$1"; }
sk(){ printf '\033[1;34m ::\033[0m %s\n' "$1"; }
rc=0

# repo-patches : path-di-tree : rentang-patch (kosong = semua)
MAP="
art:art:
external_perfetto:external/perfetto:
system_bpf:system/bpf:
packages_modules_NetworkStack:packages/modules/NetworkStack:
vendor_lineage:vendor/lineage:
system_core:system/core:
system_netd:system/netd:
packages_modules_Connectivity:packages/modules/Connectivity:
system_sepolicy:system/sepolicy:
device_lineage_sepolicy:device/lineage/sepolicy:
hardware_interfaces:hardware/interfaces:
packages_modules_Bluetooth:packages/modules/Bluetooth:
frameworks_av:frameworks/av:
frameworks_base:frameworks/base:
frameworks_native:frameworks/native:000[1-6]
"

for line in $MAP; do
    name=${line%%:*}; rest=${line#*:}; path=${rest%%:*}; glob=${rest#*:}
    d="$TREE/$path"; src="$P/$name"
    [ -d "$src" ] || { sk "$name: belum diekstrak"; continue; }
    [ -d "$d/.git" ] || { no "$path: bukan repo git"; rc=1; continue; }
    pats=$(ls "$src"/${glob:-}*.patch 2>/dev/null)
    [ -n "$pats" ] || { sk "$name: tidak ada patch"; continue; }
    last=$(basename "$(echo "$pats" | tail -1)" .patch | sed 's/^[0-9]*-//')
    subj=$(echo "$last" | tr '-' ' ')
    if git -C "$d" log --oneline -40 | grep -qiF "$(echo "$subj" | cut -c1-28)"; then
        ok "$path: sudah terpasang ($(echo "$pats" | wc -l) patch)"; continue
    fi
    git -C "$d" checkout -q -B lineage-21-a37 2>/dev/null
    git -C "$d" am --abort >/dev/null 2>&1
    if git -C "$d" am $pats >/dev/null 2>&1; then
        ok "$path: $(echo "$pats" | wc -l) patch terpasang"
    else
        git -C "$d" am --abort >/dev/null 2>&1
        if git -C "$d" am -3 $pats >/dev/null 2>&1; then
            ok "$path: $(echo "$pats" | wc -l) patch terpasang (3-way)"
        else
            f=$(git -C "$d" diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')
            git -C "$d" am --abort >/dev/null 2>&1
            no "$path: KONFLIK -- ${f:-lihat git am}"; rc=1
        fi
    fi
done
exit $rc
