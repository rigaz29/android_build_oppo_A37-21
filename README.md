# android_build_oppo_A37-21

Rencana porting **LineageOS 21 (Android 14, SDK 34)** untuk **OPPO A37 / A37f / A37fw** —
Qualcomm MSM8916 (Snapdragon 410), kernel 3.10.108 arm64, 2 GB RAM, Adreno 306.

> ## Status: **memulai ulang dengan basis LineageOS-UL** (10 Agustus 2026)
>
> Percobaan pertama memakai LineageOS **official** sebagai basis. ROM-nya jadi dan lolos
> seluruh gerbang build — tapi **tidak pernah boot**: berhenti di logo OPPO tanpa satu pun
> entri USB. Rencana kerja baru ada di **[`PLAN.md`](PLAN.md)**; percobaan pertama diarsipkan
> lengkap di [`PLAN-ATTEMPT-OFFICIAL.md`](PLAN-ATTEMPT-OFFICIAL.md).
>
> **Apa yang berubah:** basis pindah ke `LineageOS-UL/android` `lineage-21.0`, sehingga 96
> patch legacy yang sebelumnya di-port tangan lewat 17 repo **sudah menyatu di basis**.
> Alasan lengkap dan ongkosnya (UL beku di **ASB 2025-03**) ada di §2 `PLAN.md`.
> Preseden eksternal: retiredtab membangun LOS 21 untuk msm8974 (kernel 3.4) dengan
> `repo init -u https://github.com/LineageOS-UL/android.git -b lineage-21.0`.
>
> **Fase 0 selesai.** Tree UL ter-sync bersih pada percobaan pertama: 1453 project,
> 0 HEAD kosong, 174 GB. Local manifest menyusut dari delapan project jadi **tiga** (device
> tree, kernel, vendor) — UL menyediakan sisanya lewat `snippets/losul.xml`.
>
> **Yang tetap wajib meski basis UL** — diverifikasi ke tree, bukan diasumsikan:
> Camera HAL1 `device1/`, `zip -y` di `non_ab_ota.py`, dan `String8::string()` di qcom-caf.
>
> Enam asumsi lain ternyata **sudah beres di basis**, termasuk dua yang percobaan pertama
> harus tambal sendiri dari device tree: `QCOM_BOARD_PLATFORMS += msm8916`
> (`qcom_boards.mk:22`) dan `PRODUCT_COMPRESSED_APEX := false` (`updatable_apex.mk:26`).
> Yang terakhir berarti ROM berikutnya tidak lagi mengirim 20 berkas `.capex` untuk
> didekompresi apexd saat boot.
>
> **Yang tidak hilang dari percobaan pertama:** seluruh temuan device tree, VINTF, sepolicy,
> kamera, dan batas mesin build — dibawa utuh ke §4 `PLAN.md`.
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
| **[`PLAN.md`](PLAN.md)** | Dokumen utama (v2, basis UL). 7 fase, setiap klaim diikat ke sumber yang bisa diverifikasi |
| [`PLAN-ATTEMPT-OFFICIAL.md`](PLAN-ATTEMPT-OFFICIAL.md) | Arsip percobaan pertama (basis official). Dipertahankan karena temuannya masih berlaku |
| [`ref/evidence/`](ref/evidence/) | Hasil bedah ROM jangkar — `build.prop`, VINTF, simbol HAL1 kamera |
| `tools/` | Dibawa dari proyek 20: `qbootimg.py`, `sdat2img.py`, `repo-doctor.sh`, `check-drift.sh`, `verify-rom.sh`, `build-kernel-zip.sh`, `triage.sh` |

Dokumen pendahulu yang masih berlaku dan **wajib dibaca**:
[`PLAN-LOS21.md`](https://github.com/rigaz29/android_build_oppo_A37-20/blob/main/PLAN-LOS21.md)
(studi kelayakan: kernel, status fork UL, delta defconfig a6010) dan
[`HANDOFF.md`](https://github.com/rigaz29/android_build_oppo_A37-20/blob/main/HANDOFF.md)
(jebakan yang sudah pernah menjebak, cara kerja yang diharapkan).

---

## Urutan pengerjaan

**Dibalik dari percobaan pertama.** Di sana kamera didahulukan karena dianggap risiko paling
tak berbatas. Ternyata kamera bukan yang menggagalkan — boot yang gagal, dan kamera bahkan
tidak pernah sempat diuji. Kali ini **diagnosis boot didahulukan**, dan tidak ada fitur
dikerjakan sebelum ada homescreen.

```
Fase 0  Basis bersih + hipotesis boot   ✅ selesai
Fase 1  Device tree
Fase 2  Patch yang tetap wajib
Fase 3  VINTF & SEPolicy
Fase 4  Build
Fase 5  Boot
Fase 6  Fungsi — hanya setelah homescreen
```

Kernel tidak punya fase sendiri — A14 tidak menuntut pekerjaan wajib di atas A13.

---

## Komponen

| | |
|---|---|
| Device tree | [`rb_device_oppo_A37`](https://github.com/rigaz29/rb_device_oppo_A37) — branch **`lineage-21`** (14 Agustus 2026, dari `lineage-21-ul` @ `2941d27`); `lineage-21-ul` beku untuk rollback UL. Branch `lineage-21` lama percobaan pertama diarsipkan sebagai tag `archive/lineage-21-percobaan1` |
| Kernel | [`kernel_oppo_msm8939`](https://github.com/rigaz29/kernel_oppo_msm8939) — branch `lineage-21` (dari `lineage-20` @ `8cc1519`, tanpa perubahan wajib) |
| Vendor blobs | [`rb-vendor_oppo_A37`](https://github.com/rigaz29/rb-vendor_oppo_A37) @ `2e5c6f7` |

---

## Lisensi

Dokumentasi dan skrip: bebas dipakai.

Berkas di `ref/evidence/` adalah potongan konfigurasi dan daftar simbol hasil ekstraksi dari
ROM LineageOS pihak ketiga (a6000/a6010, acroreiser), disimpan untuk keperluan analisis dan
interoperabilitas. ROM-nya sendiri tidak di-redistribusi.
