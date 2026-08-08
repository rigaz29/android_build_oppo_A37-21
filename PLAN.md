# Rencana Porting LineageOS 21 — OPPO A37f (MSM8916)

> **Status:** Rencana. Belum ada fase yang dikerjakan.
> **Target:** LineageOS 21 (Android 14, SDK 34) untuk OPPO A37 / A37f / A37fw
> **Basis:** `LineageOS/android` `lineage-21.0` **official** (ASB 2026-06) + seri patch legacy
> **Baseline:** LineageOS 20 — proyek `/root/a37-20`, **ROM terpasang dan dipakai di perangkat**;
> boot, Wi-Fi, Bluetooth, dan RIL (telepon/SMS/LTE) berfungsi
> **Chipset:** Qualcomm MSM8916 (Snapdragon 410), kernel 3.10.108 arm64, 2 GB RAM, Adreno 306
> **Jangkar bukti:** ROM LineageOS 21 **a6000/a6010** (msm8916, Android 14) yang dibedah utuh — §1.1
> Terakhir diperbarui: 8 Agustus 2026

Dokumen ini **melanjutkan** `/root/a37-20/PLAN-LOS21.md` (studi kelayakan, 7 Agustus). Studi itu
menyimpulkan kamera adalah pemblokir yang belum ada jalan keluarnya. **Pembedahan ROM a6000
membalik kesimpulan itu** — jalannya ada, terukur, dan sudah terbukti berjalan di Android 14.

---

## 0. Ringkasan eksekutif

| # | Pertanyaan | Jawaban | Bukti |
|---|---|---|---|
| 1 | Kamera HAL1 — masih pemblokir? | **Tidak lagi.** ROM a6000 LOS 21 **mengirim** `libcameraservice.so` yang memuat `CameraHardwareInterface` dan `DeviceInfo1`. Jalur HAL1 **terbukti bisa dipulihkan dan berjalan di Android 14** | §1.1, §2 |
| 2 | Berapa besar pekerjaan kameranya? | **Kecil dan terukur: 2 berkas, 46 KB** (`device1/CameraHardwareInterface.{cpp,h}`) + hunk `case 1:` di `CameraProviderManager.cpp` + entri `Android.bp`. Sumbernya ada: fork UL `lineage-20.0` | §2.2 |
| 3 | `hal3on1` jadi dipakai? | **Tidak.** Studi kelayakan menduga itu satu-satunya jalan. ROM a6000 membuktikan sebaliknya: `camera.msm8916.so` yang dikirim adalah **QCamera2 HAL1 murni** (189 rujukan `QCamera2HardwareInterface`, **nol** QCamera3), dan VINTF-nya `@2.5::ICameraProvider/legacy/0` | §2.1 |
| 4 | Basis: UL 21 atau official 21? | **Official** — manifest `2ea6537` (19 Mei 2026) melacak **ASB 2026-06**. UL beku 2025-04. Sama seperti keputusan migrasi di proyek 20 | §3.1 |
| 5 | Kernel perlu kerja baru? | **Tidak wajib.** A14 tidak menambah syarat kernel keras di atas A13; `TXN_SECURITY_CTX` sudah ada di kernel kita sejak `8cc1519` | `PLAN-LOS21.md` §1 |
| 5b | Ada pemblokir kedua? | **Ya, dan sudah teridentifikasi.** AOSP 14 juga mencabut **RenderEngine GLES**; official 21 tidak punya `libs/renderengine/gl/`. Tanpa pemulihan UL 21, Adreno 306 dipaksa Skia → SurfaceFlinger crash (kelas 10.B). Bedanya dengan kamera: **UL 21 sudah menyediakannya** | §4 |
| 6 | Yang justru jadi lebih mudah dari 20 | UL 21 menyediakan **`lineage-21.0-caf-msm8916`** untuk `hardware_qcom_display` dan `hardware_qcom_audio`. Di 20 kita harus mem-pin `lineage-19.0-caf-msm8916` karena msm8916 dicabut hulu | §3.2 |

**Satu kalimat:** pemblokir tunggal proyek ini ternyata berukuran dua berkas, dan sebuah ROM
msm8916 Android 14 yang sudah beredar membuktikan port-nya bekerja — sehingga LOS 21 berubah
dari "belum jelas mungkin" menjadi "pekerjaan yang batasnya diketahui".

---

## 1. Jangkar bukti

### 1.1 ROM LineageOS 21 a6000/a6010 — dibedah utuh

Sumber: `ref/lineage-21.0-20240526-UNOFFICIAL-a6000.zip` (641 MB, `unzip -t` bersih).
Hasil bedah tersimpan di `ref/evidence/`.

```
post-build      Lenovo/Kraft-A6000/Kraft-A6000:5.0.2/LRX22G/...:user/release-keys
post-sdk-level  34                          ← Android 14
post-security   2024-04-05
pre-device      a6000, a6010, msm8916, wt86518, Kraft-*
```

**Kernel — memakai jalur yang sama dengan kita, dan memalsukan versinya:**

```
string di boot.img:  3.10.108-perf-g138595ce335    ← versi sebenarnya
                     4.9.337                        ← versi yang dilaporkan
```

Ini mengonfirmasi catatan studi kelayakan (§2) dengan bukti dari ROM yang dirilis, bukan dari
source: **kernel 3.10.108 menjalankan Android 14**, dengan versi dipalsukan agar lolos
pemeriksaan VTS/VINTF.

Geometri `boot.img` **identik A37** (base `0x80000000`, pagesize 2048, ramdisk_offset
`0x01000000`, tags `0x00000100`). Satu beda: `dt_size = 0` — mereka memakai DTB tertanam
(`zImage-dtb`), A37 memakai QCDT terpisah lewat `dtbToolOppo`. Bukan pemblokir, hanya beda
mekanisme paket.

**Properti yang menjawab pertanyaan arsitektur:**

```
ro.build.version.sdk=34         ro.build.version.release=14
ro.treble.enabled=false         ← masih non-treble di A14
ro.zygote=zygote32              ro.product.cpu.abi=armeabi-v7a
ro.system.product.cpu.abilist64=  (kosong)     ← userspace 32-bit murni
ro.config.low_ram=true          external_storage.casefold.enabled=0
debug.renderengine.backend=gles ← SAMA dengan perbaikan 10.B kita
ro.secure=1  ro.adb.secure=1    ← build rilis
ro.vndk.version=35              ← beda dari kita (`current`), §5.3
ro.product.first_api_level=19   ← beda dari kita (21), §5.3
```

⚠️ **Batas jangkar ini.** a6000/a6010 adalah msm8916 dengan **panel, kamera, dan blob yang
berbeda** dari A37. Ia menjawab pertanyaan level **chipset** dan level **Android 14** — bukan
level A37. RIL a6010 juga berbeda jalurnya.

### 1.2 Dua properti mati yang ikut dibawa a6000 — jangan ditiru

ROM itu menyetel `debug.hwui.renderer=opengl` dan `ro.hwui.render_ahead=20`. **Keduanya tidak
berpengaruh apa pun** sejak Android 10 dan Android 11 — sudah diverifikasi di source pada
proyek 20 (`PLAN-OFFICIAL.md` §8.3), dan `debug.hwui.renderer` sudah dibuang dari device tree
kita di `fdf400f`.

Dicatat di sini karena inilah pola yang dua kali menjebak proyek 20: **menyalin properti dari
tree rujukan tanpa memverifikasi konsumennya.** Jangan mengembalikannya hanya karena jangkar
memakainya.

### 1.3 Fork UL `lineage-21.0` — status terverifikasi 8 Agustus 2026

| Repo | Branch 21 |
|---|---|
| `android_packages_modules_adb` | ✅ `lineage-21.0` (+ `-qpr1`) |
| `android_system_bpf`, `android_system_netd` | ✅ |
| `android_art`, `android_external_perfetto` | ✅ |
| `android_frameworks_av` / `_base` / `_native` | ✅ (+ `-old`) |
| `android_system_core`, `android_system_sepolicy` | ✅ |
| `android_vendor_lineage`, `android_hardware_ril`, `android_bionic` | ✅ |
| `android_device_qcom_sepolicy` | ✅ `lineage-21.0-legacy` |
| **`android_hardware_qcom_display` / `_audio`** | ✅ **termasuk `lineage-21.0-caf-msm8916`** |

### 1.4 Basis kita sendiri — LOS 20 yang berjalan di perangkat

Device tree `15f7975`, kernel `8cc1519`, vendor `2e5c6f7`. Boot, Wi-Fi, Bluetooth, dan RIL
terverifikasi. Seluruh perbaikan 10.A–10.F proyek 19.1 dan perbaikan M4–M6 proyek 20 dibawa.

---

## 2. Kamera — pemblokir tunggal, dan jalan keluarnya

### 2.1 Apa yang sebenarnya dilakukan a6000

Tiga fakta dari ROM-nya, saling menguatkan:

| Bukti | Nilai |
|---|---|
| `vendor/lib/hw/camera.msm8916.so` | **QCamera2** dari source: 189 rujukan `QCamera2HardwareInterface`, `QCamera2Factory`, menaut `libmmcamera_interface.so`. **Nol** jejak QCamera3 |
| VINTF | `android.hardware.camera.provider@2.5::ICameraProvider/**legacy/0**` |
| `system/lib/libcameraservice.so` | memuat `_ZN7android23CameraHardwareInterface10initializeE...` dan `..ProviderInfo11DeviceInfo115cacheCameraInfoE..ICameraDeviceE` |

Simbol terakhir itu menentukan: `DeviceInfo1::cacheCameraInfo(sp<camera::device::V1_0::ICameraDevice>)`
adalah **jalur HAL1 sisi framework** yang dihapus AOSP di Android 14. Ia ada di biner yang
dikirim. Jadi acroreiser **memulihkannya**, bukan menghindarinya.

`camera/hal3on1` memang ada di device tree a6010 `lineage-21.0`, tapi **bukan itu yang dikirim
sebagai HAL kamera** — yang dikirim QCamera2 HAL1.

### 2.2 Peta ketersediaan `device1/`

| Sumber | `services/camera/libcameraservice/device1/` |
|---|---|
| AOSP 14 | dihapus |
| LineageOS official `lineage-21.0` | **tidak ada** (diverifikasi: `Android.bp` hanya punya `api1/Camera2Client.cpp`) |
| **LineageOS-UL `lineage-21.0`** | **tidak ada** — hanya 2 commit kamera, keduanya helper (`custom CameraParameter code`, `32-bit cameraserver`) |
| **LineageOS-UL `lineage-20.0`** | **ADA** ← sumber port |
| ROM a6000 LOS 21 (biner) | **ADA** ← bukti port bekerja di A14 |

### 2.3 Rencana kerja kamera

Isi port dari UL `lineage-20.0`:

```
services/camera/libcameraservice/device1/CameraHardwareInterface.cpp   28.151 byte
services/camera/libcameraservice/device1/CameraHardwareInterface.h     18.493 byte
                                                              total   46.644 byte
```

plus, di `common/CameraProviderManager.{cpp,h}`: kelas `DeviceInfo1` dan cabang
`case 1: initializeDeviceInfo<DeviceInfo1>(...)` yang di A14 diganti `return BAD_VALUE`;
plus entri sumber di `libcameraservice/Android.bp`.

**Urutan yang dianjurkan** — kamera dikerjakan **paling awal**, bukan paling akhir seperti di
proyek 20. Alasannya: ini satu-satunya bagian yang risikonya belum berbatas. Kalau port gagal,
seluruh rencana berubah, dan lebih baik tahu di minggu pertama.

Langkah uji tanpa membangun ROM penuh: `m libcameraservice` harus rc=0, lalu periksa simbol
hasil build dengan `nm`/`strings` — persis metode yang dipakai memverifikasi patch binder di
proyek 20 (Fase 1.2).

⚠️ **Yang belum diketahui.** Blob kamera A37 (`camera.vendor.msm8916.so` + shim
`libshim_camera`) berbeda dari a6010 yang membangun QCamera2 dari source. Port `device1/`
memulihkan **jalur framework**; apakah blob A37 cocok dengan jalur itu di A14 baru terbukti
saat diuji di perangkat. Di LOS 20 kombinasi ini bekerja, jadi peluangnya baik — tapi bukan
jaminan.

---

## 3. Basis dan manifest

### 3.1 Official, bukan UL

| | LineageOS-UL `lineage-21.0` | LineageOS **official** `lineage-21.0` |
|---|---|---|
| Manifest terakhir | 2025-04-04 (seluruh lini UL beku) | **2026-05-19 (`2ea6537`)** |
| ASB terakhir | 2025-03 | **2026-06** |

Sama seperti keputusan migrasi proyek 20 (`PLAN-OFFICIAL.md`): fungsi legacy UL dibawa sebagai
**seri patch** hasil `git format-patch`, bukan dengan mem-pin fork UL — mem-pin akan mengunci
`frameworks/av` dan `frameworks/base` di ASB lama dan menggugurkan tujuan memakai official.

### 3.2 Yang lebih mudah dari proyek 20

Di 20, `hardware/qcom-caf/msm8916` dicabut hulu dan kita mem-pin `lineage-19.0-caf-msm8916`
milik LineageOS. Di 21, **UL menyediakan `lineage-21.0-caf-msm8916`** untuk display dan audio —
sezaman dengan basisnya, bukan dua versi di belakang.

⚠️ Verifikasi dulu isinya sebelum dipakai: nama branch bukan jaminan. Bandingkan terhadap
`lineage-19.0-caf-msm8916` yang terbukti jalan di 20.

### 3.3 Draf manifest lokal

Mengikuti pola `A37-20.xml`:

| path | sumber | catatan |
|---|---|---|
| `device/oppo/A37` | `rigaz29/rb_device_oppo_A37` branch `lineage-21` (baru, dari `15f7975`) | |
| `kernel/oppo/msm8939` | `rigaz29/kernel_oppo_msm8939` branch `lineage-21` (baru, dari `8cc1519`) | tanpa perubahan wajib |
| `vendor/oppo` | `rigaz29/rb-vendor_oppo_A37` @ `2e5c6f7` | tidak berubah sejak 18.1 |
| `hardware/qcom-caf/msm8916/{audio,display}` | UL `lineage-21.0-caf-msm8916` | **verifikasi isi dulu** (§3.2) |
| `hardware/qcom-caf/msm8916/media` | belum ada padanan 21 di UL — periksa; kalau tidak ada, pin `lineage-19.0-caf-msm8916` seperti di 20 | |
| `device/qcom/sepolicy-legacy` | UL `lineage-21.0-legacy` | |

---

## 4. Delta 20 → 21 yang harus diverifikasi di tree

Daftar ini **belum diverifikasi** — sync `/root/los21` baru selesai saat rencana ini ditulis.
Kerjakan sebagai Fase 2, dengan metode yang sama seperti proyek 20:

- [ ] Variabel build usang: `grep KATI_obsolete_var build/make/core/*.mk` lalu silang-periksa
      terhadap device tree kita. Di 20 hasilnya cuma 1.
- [ ] `PRODUCT_SHIPPING_API_LEVEL := 21` — apakah gerbang
      `PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS` (≥29) dan `PRODUCT_SET_DEBUGFS_RESTRICTIONS`
      (≥31) masih bekerja sama di A14.
- [x] `RenderEngineType::GLES` — **SUDAH DIVERIFIKASI 8 Agustus 2026, dan hasilnya penting.**
      AOSP 14 mencabut RenderEngine GLES seluruhnya:

      | | `libs/renderengine/gl/` | enum `RenderEngineType` |
      |---|---|---|
      | LineageOS **official** `lineage-21.0` | **404 — tidak ada** | tanpa `GLES` |
      | **LineageOS-UL** `lineage-21.0` | **ada** | `GLES = 1, THREADED = 2, SKIA_GL = 3, ...` |

      Artinya **perbaikan 10.B kita tidak akan berfungsi di atas official 21 apa adanya** —
      Adreno 306 dipaksa ke Skia dan SurfaceFlinger crash seperti dulu. `frameworks/native`
      **wajib** memakai pemulihan UL 21. Ini bukan opsi kenyamanan; ini pemblokir boot.
- [ ] Lokasi sepolicy dan `sepolicy` version (33.0 → 34.0).
- [ ] `system/sepolicy` `sysfs_disk_stat` — di 20 harus dibuang untuk lolos `sepolicy_freeze_test`.

---

## 5. Device tree

### 5.1 Yang dibawa dari 20 — jangan diutak-atik

Setiap baris punya bug bernomor di belakangnya:

```make
BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED := true   # 10.A
PRODUCT_SHIPPING_API_LEVEL := 21                 # 10.A (pasangannya)
debug.renderengine.backend=gles                  # 10.B  — verifikasi ulang di A14 (§4)
# tanpa IPictureAdjustment di manifest.xml       # 10.C
# tanpa servis ppd & livedisplay legacymm        # 10.C
TARGET_HAS_LEGACY_CAMERA_HAL1 := true            # 10.D
TARGET_USES_QTI_CAMERA_DEVICE := true            # 10.D
vendor.rild.libpath=...                          # M6 — RIL, satu baris
# 12 prop gating profil Bluetooth Android 13     # M5-BT1
# include bluetooth_audio_policy_configuration   # M5-BT2
TARGET_PROVIDES_WCNSS_QMI := true                # Fase 3.1b
```

### 5.2 Yang sudah terbukti MATI — jangan dikembalikan

```make
debug.hwui.renderer=opengl     # mati sejak A10; dibuang di fdf400f
ro.hwui.render_ahead           # getter tak pernah dipanggil; jangan ditambahkan
mixPort deep_buffer            # primary output SUDAH deep buffer; di-revert di 8dad618
```

### 5.3 Keputusan baru yang muncul dari jangkar

| Hal | a6000 | Kita di 20 | Sikap |
|---|---|---|---|
| `ro.vndk.version` | `35` | `current` | Periksa apakah A14 menuntut angka; `current` bekerja di 20 |
| `ro.product.first_api_level` | `19` | **21** | **Pertahankan 21** — nilai 19 mereproduksi 10.A di perangkat kita |
| FBE | belum diperiksa | `/data` polos | Tetap polos kecuali ada alasan baru |

---

## 6. Urutan pengerjaan

Berbeda dari proyek 20: **kamera didahulukan**, karena ia satu-satunya risiko tak berbatas.

```
Fase 0  Persiapan        ── disk, branch kerja lineage-21, envsetup
Fase 1  KAMERA           ── port device1/ dari UL 20 → official 21; m libcameraservice rc=0
                            Kalau ini gagal, seluruh rencana ditinjau ulang
Fase 2  Manifest & sync  ── official 21 + A37-21.xml + seri patch UL 21
Fase 3  Delta 20→21      ── §4, diverifikasi di tree, bukan diperkirakan
Fase 4  Device tree      ── rebase 15f7975 → lineage-21, bawa §5.1, hindari §5.2
Fase 5  VINTF & SEPolicy ── sepolicy 34.0
Fase 6  Vendor blobs     ── set 320 blob dipertahankan
Fase 7  Build            ── m bacon + verify-rom.sh
Fase 8  Boot & uji       ── AnyKernel3 dulu, lalu ROM; matriks paritas terhadap ROM 20
```

Kernel tidak punya fase sendiri: tidak ada pekerjaan wajib (`PLAN-LOS21.md` §1). Spoof versi
kernel (`4.9.337`) dan `CONFIG_PSI` bersifat opsional — kerjakan hanya kalau ada pemeriksaan
yang benar-benar menolak, bukan preventif.

---

## 7. Risiko yang diakui

| Risiko | Dampak | Mitigasi |
|---|---|---|
| **Blob kamera A37 ≠ a6010** | Port `device1/` memulihkan framework, tapi blob A37 belum tentu cocok di A14 | Fase 1 didahulukan; di 20 kombinasi ini bekerja |
| ~~`GLES` mungkin dicabut di A14~~ → **TERBUKTI DICABUT** di official 21 | Tanpa pemulihan UL, SF crash di Adreno 306 (kelas 10.B) — pemblokir boot | §4 — `frameworks/native` wajib dari UL 21 |
| Jangkar dari device lain | a6000 tidak menjawab RIL, panel, kamera A37 | Dinyatakan di §1.1; untuk hal khas A37 pakai ROM 20 kita sendiri |
| Basis official bergerak | `repo sync` bisa memutus build kapan saja | `tools/check-drift.sh`, pin hanya yang terbukti memutus |
| RIL di 21 belum terbukti | Di 20 beres satu baris; radio stack A14 bergerak | Bukan kriteria keberhasilan boot pertama |
| Disk | Tree 21 ± 170 GB + `out/` 50 GB | Sisa 109 GB saat ini — **bersihkan sebelum `m bacon`** |

---

## 8. Yang sengaja TIDAK dikerjakan

| Item | Alasan |
|---|---|
| `hal3on1` | ROM a6000 membuktikan HAL1 lewat framework yang dipulihkan sudah cukup; hal3on1 menambah lapisan tanpa kebutuhan terbukti |
| Rebase kernel / backport wajib | A14 tidak menuntutnya (`PLAN-LOS21.md` §1) |
| Basis UL 21 | ASB beku 2025-03; §3.1 |
| Spoof versi kernel & `CONFIG_PSI` preventif | Kerjakan hanya kalau ada pemeriksaan yang menolak |
| Mengembalikan properti mati dari jangkar | §1.2, §5.2 |

---

## Lampiran A — Perintah yang mereproduksi data dokumen ini

```bash
# A.1 Bedah ROM jangkar
cd ref && unzip -o -q lineage-21.0-*-a6000.zip boot.img system.new.dat.br system.transfer.list
python3 ../tools/qbootimg.py boot.img boot_out
brotli -d -o system.new.dat system.new.dat.br
python3 ../tools/sdat2img.py system.transfer.list system.new.dat system.img
truncate -s 1887436800 system.img && mount -t ext4 -o ro,loop system.img sysmnt

# A.2 Versi kernel sebenarnya vs yang dilaporkan
strings -a boot_out/kernel.img | grep -E "^3\.10\.|^4\.9\."

# A.3 BUKTI KUNCI — HAL1 dipulihkan di Android 14
strings -a sysmnt/system/lib/libcameraservice.so \
  | grep -oE "_ZN7android23CameraHardwareInterface[A-Za-z0-9_]*" | sort -u
strings -a sysmnt/system/lib/libcameraservice.so | grep DeviceInfo1

# A.4 HAL kamera yang dikirim = QCamera2 HAL1, bukan hal3on1/QCamera3
strings -a sysmnt/system/vendor/lib/hw/camera.msm8916.so \
  | grep -oE "QCamera[23][A-Za-z]*" | sort | uniq -c

# A.5 device1/ tidak ada di official 21 maupun UL 21, ADA di UL 20
for r in LineageOS/android_frameworks_av LineageOS-UL/android_frameworks_av; do
  for b in lineage-21.0 lineage-20.0; do
    printf "%s %s -> " "$r" "$b"
    curl -s -o /dev/null -w "%{http_code}\n" \
      "https://raw.githubusercontent.com/$r/$b/services/camera/libcameraservice/device1/CameraHardwareInterface.h"
  done
done

# A.6 ASB terbaru basis official 21
git -C /root/los21/.repo/manifests log -1 --format="%h %cs %s"
```
