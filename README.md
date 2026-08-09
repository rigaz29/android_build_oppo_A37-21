# android_build_oppo_A37-21

Rencana porting **LineageOS 21 (Android 14, SDK 34)** untuk **OPPO A37 / A37f / A37fw** —
Qualcomm MSM8916 (Snapdragon 410), kernel 3.10.108 arm64, 2 GB RAM, Adreno 306.

> ## Status: **Fase 1, 2, 3, 4, dan 5 selesai**
>
> Tree LineageOS 21 official sudah tersedia dan terverifikasi: **1430 project, 0 HEAD kosong,
> 169 GB**, manifest `2ea6537` melacak **ASB 2026-06**.
>
> Dengan `lunch lineage_A37-ap2a-userdebug`:
>
> ```
> m nothing            rc=0   nol pelanggaran link-type, nol modul hilang
> m libcameraservice   rc=0   jalur kamera HAL1 tersambung penuh
> m cameraserver       rc=0
> m librenderengine surfaceflinger   rc=0   backend GLES kembali dikenali
> m sepolicy_freeze_test selinux_policy rc=0
> m check-vintf-all                      rc=0   COMPATIBLE
> ```
>
> Rinciannya di [`PLAN.md`](PLAN.md) §Fase 1 dan §Fase 4.
>
> ⚠️ Semua ini **bukti kompilasi**, bukan bukti fungsi. Kamera, tethering, Wi-Fi AIDL, dan
> clearkey baru terbukti saat boot di Fase 8.
>
> Pendahulunya: [`android_build_oppo_A37-20`](https://github.com/rigaz29/android_build_oppo_A37-20)
> — LineageOS 20, **ROM terpasang dan dipakai di perangkat**: boot, Wi-Fi, Bluetooth, dan
> **RIL (telepon/SMS/LTE)** berfungsi.

---

## Dua pemblokir, keduanya sudah dipetakan

Android 14 mencabut dua hal yang A37 butuhkan. Keduanya **bukan dugaan** — diverifikasi
langsung di tree hasil sync:

```
official 21 punya libs/renderengine/gl/           : TIDAK ADA
official 21 punya libcameraservice/device1/       : TIDAK ADA
```

| Komponen | official 21 | UL 21 | Sumber patch |
|---|---|---|---|
| **RenderEngine GLES** — tanpa ini Adreno 306 dipaksa Skia dan SurfaceFlinger crash (bug 10.B) | ❌ | ✅ | **UL 21** |
| **Camera HAL1 `device1/`** — kamera A37 hanya jalan lewat HAL1 | ❌ | ❌ | **UL 20**, forward-port |

Kamera: **4 berkas, ± 98 KB** (`device1/CameraHardwareInterface.{cpp,h}` **dan**
`api1/CameraClient.{cpp,h}`) plus ± 200 baris adaptasi — entri `Android.bp`, `case 1:` di
`CameraProviderManager.cpp`, serta `DeviceInfo1`/`HidlDeviceInfo1` dan wiring `CameraService`.

RenderEngine GLES: **9 patch, 14.464 baris**, di [`patches/frameworks_native/`](patches/frameworks_native/).
Bahwa perangkat ini benar-benar memakai GLESRenderEngine dibuktikan dari ROM proyek 20 yang
berjalan — `dumpsys SurfaceFlinger` mencetak string yang hanya ada di `gl/GLESRenderEngine.cpp`
dan nihil di seluruh `skia/`.

---

## Jangkar bukti: ROM LineageOS 21 a6000/a6010

`ref/evidence/` berisi hasil bedah ROM **LineageOS 21 untuk Lenovo a6000/a6010** — msm8916,
Android 14, dibangun acroreiser. Device berbeda, **chipset dan versi kernel sama**.

```
post-sdk-level  34                                   ← Android 14
kernel          3.10.108-perf-g138595ce335           ← versi sebenarnya
                4.9.337                              ← versi yang dilaporkan (spoof, lolos VTS)
```

**Temuan yang membalik studi kelayakan sebelumnya.** Studi 7 Agustus menyimpulkan kamera
adalah pemblokir tanpa jalan keluar jelas, dan menduga `hal3on1` satu-satunya opsi.
Biner ROM-nya membuktikan sebaliknya:

```
$ strings libcameraservice.so | grep CameraHardwareInterface
_ZN7android23CameraHardwareInterface10initializeENS_2spINS_21CameraProviderManagerEEE
$ strings libcameraservice.so | grep DeviceInfo1
..ProviderInfo11DeviceInfo115cacheCameraInfoE..ICameraDeviceE

$ strings camera.msm8916.so | grep -oE "QCamera[23][A-Za-z]*" | sort | uniq -c
    189 QCamera2HardwareInterface      ← HAL1 murni
      0 QCamera3*                      ← nol
```

Jadi acroreiser **memulihkan jalur HAL1 di Android 14**, bukan menghindarinya lewat hal3on1.
`hal3on1` memang ada di device tree mereka, tapi bukan itu yang dikirim.

⚠️ **Batasnya:** a6000/a6010 punya panel, kamera, dan blob berbeda dari A37; RIL-nya pun
jalur lain. Jangkar ini menjawab pertanyaan level **chipset** dan level **Android 14** —
bukan level A37.

---

## Isi

| Berkas | Keterangan |
|---|---|
| **[`PLAN.md`](PLAN.md)** | Dokumen utama. 8 fase, setiap klaim diikat ke sumber yang bisa diverifikasi |
| [`ref/evidence/`](ref/evidence/) | Hasil bedah ROM jangkar — `build.prop`, VINTF, simbol HAL1 kamera |
| `tools/` | Dibawa dari proyek 20: `qbootimg.py`, `sdat2img.py`, `repo-doctor.sh`, `check-drift.sh`, `verify-rom.sh`, `build-kernel-zip.sh`, `triage.sh` |

Dokumen pendahulu yang masih berlaku dan **wajib dibaca**:
[`PLAN-LOS21.md`](https://github.com/rigaz29/android_build_oppo_A37-20/blob/main/PLAN-LOS21.md)
(studi kelayakan: kernel, status fork UL, delta defconfig a6010) dan
[`HANDOFF.md`](https://github.com/rigaz29/android_build_oppo_A37-20/blob/main/HANDOFF.md)
(jebakan yang sudah pernah menjebak, cara kerja yang diharapkan).

---

## Urutan pengerjaan

Berbeda dari proyek 20: **kamera didahulukan**, karena ia satu-satunya risiko yang belum
berbatas. Kalau port-nya gagal, seluruh rencana ditinjau ulang — dan itu lebih baik diketahui
di minggu pertama daripada di fase terakhir.

```
Fase 0  Persiapan        Fase 4  Device tree
Fase 1  KAMERA           Fase 5  VINTF & SEPolicy
Fase 2  Manifest & sync  Fase 6  Vendor blobs
Fase 3  Delta 20→21      Fase 7  Build
                         Fase 8  Boot & uji
```

Kernel tidak punya fase sendiri — A14 tidak menuntut pekerjaan wajib di atas A13.

---

## Komponen

| | |
|---|---|
| Device tree | [`rb_device_oppo_A37`](https://github.com/rigaz29/rb_device_oppo_A37) — branch `lineage-21` (dibuat dari `lineage-20` @ `15f7975`) |
| Kernel | [`kernel_oppo_msm8939`](https://github.com/rigaz29/kernel_oppo_msm8939) — branch `lineage-21` (dari `lineage-20` @ `8cc1519`, tanpa perubahan wajib) |
| Vendor blobs | [`rb-vendor_oppo_A37`](https://github.com/rigaz29/rb-vendor_oppo_A37) @ `2e5c6f7` |

---

## Lisensi

Dokumentasi dan skrip: bebas dipakai.

Berkas di `ref/evidence/` adalah potongan konfigurasi dan daftar simbol hasil ekstraksi dari
ROM LineageOS pihak ketiga (a6000/a6010, acroreiser), disimpan untuk keperluan analisis dan
interoperabilitas. ROM-nya sendiri tidak di-redistribusi.
