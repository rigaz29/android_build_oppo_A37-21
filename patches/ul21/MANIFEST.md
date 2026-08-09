# MANIFEST — patches/ul21 (Fase 8, 9 Agustus 2026)

Delta **LineageOS-UL `lineage-21.0` ↔ official `lineage-21.0`**, per repo.
Ini adalah padanan LOS 21 dari `patches/official/` proyek 20 (135 patch, tier
T0–T3), dan **seharusnya dikerjakan sejak Fase 2** — bukan di Fase 8.

## Kenapa ini terlambat

Proyek 20 mengekstrak delta UL secara sistematis. Proyek 21 tidak: patch hanya
ditambahkan **ketika build gagal**. Mayoritas patch di sini memperbaiki perilaku
**runtime di kernel 3.10** dan tidak pernah memecahkan kompilasi, sehingga lolos
dari seluruh pemeriksaan Fase 2–7 — yang semuanya build-time.

Contoh paling tajam: `system/bpf`. Official lineage-21 menjadikan kegagalan
eBPF **fatal** (`sleep(20); return 2`), dan di kernel 3.10 eBPF pasti gagal.
Patch UL menjadikannya non-fatal. Tanpa itu boot terhenti, dan `m bacon` tidak
akan pernah mengeluhkan apa pun.

## Ekstraksi

`tools/extract-ul21-patches.sh` — adaptasi `extract-official-patches.sh` proyek
20. Perbedaan: proyek 20 punya checkout UL utuh; di sini tiap repo diklon
sendiri secara **blobless** (`--filter=blob:none`), bukan shallow — mencari
merge-base menuntut riwayat penuh.

Penerapan: `tools/apply-ul21-patches.sh`.

## Isi

| Tier | Repo | Patch | Catatan |
|---|---|--:|---|
| T0 | `art` | 1 | gerbang `memfd_create` |
| T0 | `external_perfetto` | 1 | gerbang `memfd_create` |
| T0 | `system_bpf` | 2 | bpfloader **non-fatal** — pemblokir boot |
| T0 | `packages_modules_NetworkStack` | 9 | netlink + TCP info opt-out |
| T1 | `vendor_lineage` | 10/12 | lihat "tidak dipasang" di bawah |
| T1 | `system_core` | 5 | |
| T1 | `system_netd` | 4 | no-bpf + direct-connect routes |
| T1 | `packages_modules_Connectivity` | 15 | jalur BPF-less |
| T1 | `system_sepolicy` | 4 | |
| T1 | `device_lineage_sepolicy` | 4 | termasuk revert "Drop support for ultra legacy platforms" |
| T1 | `hardware_interfaces` | 4 | audio 2.0 dll. |
| T1 | `frameworks_native` | 6 | hanya 0001–0006; 0007–0015 = seri GLES yang sudah dipasang Fase 4 |
| T1 | `packages_modules_Bluetooth` | 4 | |
| T2 | `frameworks_av` | 6 | libaudiohal 2.0, BT in-call CAF, SCO fallback, 2 patch kamera |
| T2 | `frameworks_base` | 21 | 0014 dan 0015 dibuang — lihat di bawah |
| | **total terpasang** | **96** | |

## TIDAK dipasang, dengan alasan

| Patch | Alasan |
|---|---|
| `vendor_lineage/0008` revert `TARGET_CAMERA_BOOTTIME_TIMESTAMP` | Flag-nya **tidak disetel** device tree kita → kode mati. Patch juga konflik. Preseden proyek 20: patch bergerbang flag tak disetel dibuang ("kode mati, hanya menambah permukaan konflik") |
| `vendor_lineage/0011` kernel clean headers uapi/asm | Isinya **sudah ada** di tree (`git apply` → "nothing to commit") |
| `frameworks_libs_net`, `packages_modules_Wifi` | UL **tidak punya** branch `lineage-21.0` untuk keduanya (diverifikasi lewat API GitHub) |
| `frameworks_base/0014` revert "Remove deprecated IRadio 1.4 APIs" **dan** `0015` revert "Removed IWLAN legacy mode support" | **Berpasangan dengan patch telephony yang sengaja tidak di-port.** Keduanya gagal dengan pola yang sama — API telephony ditambah/diubah di `frameworks/base`, sementara repo yang mengimplementasikannya tidak ikut dipatch:<br>`0015` → `ServiceStateTracker.java:674: method setOutOfService cannot be applied to given types`<br>`0014` → `PhoneInterfaceManager.java:289: does not override abstract method invokeOemRilRequestRaw(byte[],byte[]) in ITelephony`<br>Diverifikasi setelah keduanya dibuang: **nol** patch tersisa yang menyentuh `telephony/`. UL punya branch `lineage-21.0` untuk `frameworks_opt_telephony`, jadi memasang pasangannya BISA dilakukan — tapi proyek 20 sengaja menunda seluruh seri RIL ("fase M6, hanya setelah paritas tercapai"), dan RIL adalah satu-satunya subsistem yang sudah TERBUKTI berfungsi. Menyentuhnya saat sedang mengejar kegagalan boot menambah risiko tanpa keuntungan yang jelas: yang dipulihkan patch ini adalah mode IWLAN legacy (panggilan Wi-Fi). Kalau nanti IWLAN memang dibutuhkan, port `frameworks_opt_telephony` sebagai pasangannya — jangan pasang 0015 sendirian. |

## Efek samping yang menghapus workaround lama

`device_lineage_sepolicy` revert "qcom: Drop support for ultra legacy platforms"
mengembalikan msm8916 ke dua daftar di `qcom/sepolicy.mk` — penyertaan
`legacy-vendor` dan pengecualian m4def berawalan. Itu memperbaiki **di sumbernya**
apa yang Fase 3 tambal manual di `BoardConfig.mk`, sehingga workaround tersebut
**dicabut**. Diverifikasi: `BOARD_SEPOLICY_M4DEFS` kini berisi tepat
`location_domain=location`, bukan duplikat.

## Yang masih perlu ditinjau

`sysfs_disk_stat` — Fase 3 mendeklarasikan tipe ini di
`device/oppo/A37/sepolicy/file.te`. MANIFEST proyek 20 mencatat patch yang
menambah tipe itu **sengaja dibuang** karena "mengulangi pemblokir 5.1b/5.1d",
dan sisi sepolicy-legacy ditangani dengan MEMBUANG label-nya. Perlu ditinjau
apakah deklarasi kita masih diperlukan setelah seri sepolicy UL terpasang.
