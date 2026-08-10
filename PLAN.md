# LineageOS 21 (Android 14) — OPPO A37 / A37f / A37fw

Rencana kerja **v2**, ditulis ulang dari nol pada 10 Agustus 2026 setelah percobaan
pertama (basis official) berhenti di logo OPPO.

MSM8916 (Snapdragon 410) · kernel 3.10.108 arm64 · 2 GB RAM · Adreno 306 · non-Treble ·
partisi statis · `/system/vendor` (bukan partisi vendor terpisah).

---

## 0. Ringkasan eksekutif — apa yang berubah dari percobaan pertama

| | Percobaan 1 (gagal) | Rencana ini |
|---|---|---|
| Basis source | LineageOS **official** `lineage-21.0` | **LineageOS-UL** `lineage-21.0` |
| Patch legacy | di-port sendiri, 96 patch, 17 repo | **sudah menyatu di basis** |
| ASB | 2026-06 | 2025-03 (lihat §2 — ini ongkosnya) |
| Resolusi konflik | otomatis, aturan *keep-both* buta | **tidak ada konflik untuk di-resolve** |
| Hasil | stuck di logo OPPO, nol entri USB | — |

**Satu kalimat kenapa berpindah basis:** percobaan pertama menghabiskan sebagian besar
usahanya untuk memindahkan patch yang UL sudah punya, dan justru di proses pemindahan itu
kerusakan terjadi — resolver konflik otomatis saya menyimpan dua blok `mFunctionCalls.push`
di `RenderEngineThreaded.cpp` (satu 6 argumen, satu 5) dan itu hanya ketahuan karena
compiler menolaknya. Yang tidak ketahuan compiler tidak akan pernah ketahuan.

**Yang TIDAK dibuang dari percobaan pertama:** seluruh temuan device-tree, VINTF, sepolicy,
kamera, dan batas mesin build. Itu semua tetap berlaku dan dibawa ke §4. Percobaan pertama
mahal, tapi tidak sia-sia — ia memetakan medan.

---

## 1. Jangkar bukti

Setiap klaim di bawah punya perintah verifikasinya. Kalau sebuah klaim tidak bisa
diverifikasi ulang, ia tidak masuk dokumen ini.

### 1.1 Jangkar A — retiredtab: resep LOS 21 untuk QCOM legacy, memakai UL

Ini **pembenaran langsung** untuk pivot basis, dan bukan dari saya:

```
21/msm8974/21-msm8974-build-instructions:
  1. We are using LineageOS-UL for the repos.
     repo init -u https://github.com/LineageOS-UL/android.git -b lineage-21.0 --git-lfs --depth=1
```

msm8974 memakai **kernel 3.4** — lebih tua dari kita — dan retiredtab mengirim build LOS 21
untuknya. Jadi "Android 14 di QCOM legacy dengan basis UL" bukan hipotesis.

Resep itu juga yang menyingkap perbedaan yang percobaan pertama tidak pernah sadari:

```
21/UL-patches-2024/build-aug-2024.patch
  target/product/updatable_apex.mk
  -PRODUCT_COMPRESSED_APEX := true
  +PRODUCT_COMPRESSED_APEX := false
```

ROM percobaan pertama mengirim **20 berkas `.capex`** yang harus didekompresi apexd ke
`/data` saat boot pada perangkat 2 GB. Basis UL sudah membawa commit itu, jadi ini bukan
pekerjaan kita — tapi tetap salah satu variabel yang berubah. Lihat §4.8.

### 1.2 Jangkar B — acroreiser: msm8916 + kernel 3.10 menjalankan Android 14

ROM LineageOS 21 untuk Lenovo a6000/a6010 sudah dibedah di `ref/evidence/`. Device berbeda,
**chipset dan versi kernel sama persis**.

```
post-sdk-level  34                            ← Android 14
kernel          3.10.108-perf-g138595ce335    ← versi sebenarnya
                4.9.337                       ← yang dilaporkan (spoof, lolos VTS)
```

Dan yang membalik studi kelayakan lama — biner ROM-nya membuktikan HAL1 kamera dipulihkan,
bukan dihindari lewat `hal3on1`:

```
$ strings libcameraservice.so | grep CameraHardwareInterface
_ZN7android23CameraHardwareInterface10initializeENS_2spINS_21CameraProviderManagerEEE
$ strings camera.msm8916.so | grep -oE "QCamera[23][A-Za-z]*" | sort | uniq -c
    189 QCamera2HardwareInterface      ← HAL1 murni
      0 QCamera3*
```

⚠️ **Batasnya:** a6000/a6010 punya panel, kamera, blob, dan jalur RIL berbeda. Jangkar ini
menjawab pertanyaan level **chipset** dan **Android 14** — bukan level A37.

### 1.3 Jangkar C — ROM LineageOS 20 A37 kita sendiri

Satu-satunya jangkar level-A37. Terpasang, boot, dan **masih normal per 10 Agustus 2026**
(dikonfirmasi ulang setelah percobaan 21 gagal). Boot, Wi-Fi, Bluetooth, RIL berfungsi.

Nilainya bukan nostalgia: ia **alat ukur**. Sepanjang dokumen ini, kalau ada pertanyaan
"seharusnya bagaimana di A37", jawabannya diambil dengan membedah ROM ini atau membaca
perangkat yang menjalankannya — bukan dari dokumentasi.

Contoh yang sudah terpakai: `/linkerconfig/ld.config.txt` membuktikan
`namespace.default.isolated = false`, yang menjadi dasar keputusan shim di §4.1.

### 1.4 Jangkar D — fork UL `lineage-21.0`, status terverifikasi

```
$ curl -s api.github.com/repos/LineageOS-UL/android/commits?sha=lineage-21.0
  a156f537  2025-04-04  Merge remote-tracking branch 'LineageOS/lineage-21.0'
  9ce03f4e  2025-03-05  Track our own forks for 2025-03 ASB patching
```

**Beku sejak April 2025, ASB 2025-03.** Ini fakta, bukan tuduhan — dan §2 membahas
konsekuensinya secara terbuka.

Manifest UL punya **tiga** berkas, dan yang ketiga menentukan:

```
default.xml           1287 project   AOSP
snippets/lineage.xml   149 project   LineageOS
snippets/losul.xml      61 project   fork UL  ← inilah isinya
```

`losul.xml` menyediakan justru yang kita kira harus dibawa sendiri:

```
losul.xml   device/qcom/sepolicy-legacy          lineage-21.0-legacy
losul.xml   hardware/qcom-caf/msm8916/audio      lineage-21.0-caf-msm8916
losul.xml   hardware/qcom-caf/msm8916/display    lineage-21.0-caf-msm8916
losul.xml   hardware/qcom-caf/msm8916/media      lineage-21.0-caf-msm8916
```

61 repo di `losul.xml` mencakup hampir semua yang percobaan pertama tambal tangan —
`frameworks/av`, `frameworks/base`, `frameworks/native`, `packages/modules/adb`,
`system/core`, `system/sepolicy`, `system/bpf`, `hardware/qcom-caf/common`, `hardware/ril`,
`frameworks/opt/telephony`, `bionic`, `art`.

⚠️ **Dua koreksi terhadap draf pertama dokumen ini, dari kesalahan yang sama diulang dua
kali.**

Draf pertama menyatakan UL tidak menyediakan msm8916, dari `grep msm8916
snippets/lineage.xml` yang memang nol — `losul.xml` tidak ikut diperiksa. Setelah itu
diperbaiki, draf berikutnya menyatakan `build/make` bukan fork UL, karena `losul.xml` tidak
memuatnya. Itu pun salah:

```
.repo/manifests/default.xml:32
  <project path="build/make" name="LineageOS-UL/android_build" …/>
```

UL mem-fork `build/make` lewat **override di `default.xml`**, bukan lewat snippet.

**Aturan yang lahir dari dua kekeliruan ini — dan yang benar-benar menutup celahnya:**
jangan pernah menyimpulkan dari berkas manifest sumber. Baca hasil **resolve**-nya:

```bash
repo manifest | grep 'path="build/make"'      # jawaban yang mengikat
```

Menggrep berkas sumber gagal dua arah sekaligus: snippet bisa menambah, dan `default.xml`
bisa meng-override. Hanya manifest hasil resolve yang tahu keduanya.

Akibat nyata dari koreksi ini: local manifest menyusut dari delapan project jadi **tiga**,
dan dua butir yang §2 daftarkan sebagai pekerjaan kita ternyata sudah beres di basis.

### 1.5 Jangkar E — percobaan pertama (basis official), dan apa yang ia buktikan

Diarsipkan lengkap di [`PLAN-ATTEMPT-OFFICIAL.md`](PLAN-ATTEMPT-OFFICIAL.md) dan
[`NOTES-boot-failure.md`](NOTES-boot-failure.md). Yang **terbukti** di sana dan tidak perlu
diulang:

| Sudah tersingkir | Bukti |
|---|---|
| kernel biner | 46 byte beda dari kernel LOS 20 yang boot, seluruhnya stempel waktu build |
| `dt.img` | byte-identik dengan LOS 20 (sha `459a2a6d…`) |
| `system.img` kebesaran | 1434 MB di partisi 2727 MB |
| init **crash** | `init_fatal_reboot_target=recovery` aktif; init crash akan ke recovery — tidak terjadi |
| partisi / perangkat / proses flash | LOS 20 di-flash balik dan **boot normal** |

Sisa kelas penyebab: **kernel panic/hang sangat awal**, atau **init menggantung** (hang, bukan
crash — hang tidak memicu `InitFatalReboot`). Tidak ada `panic=` di cmdline, jadi panic akan
diam selamanya, bukan reboot. `boot-panic5.img` dibuat untuk memisahkan keduanya.

---

## 2. Kenapa UL sebagai basis — dan ongkos yang harus diterima

**Ongkosnya nyata dan harus dinyatakan:** ASB 2025-03 vs 2026-06 official. Sekitar 15 bulan
patch keamanan tidak ada. Proyek 20 justru bermigrasi ke arah sebaliknya (UL → official)
demi ini.

**Kenapa untuk 21 keputusannya dibalik:**

1. **Yang dibeli dengan basis official tidak terpakai.** ASB hanya bernilai kalau ROM-nya
   boot. Percobaan pertama tidak pernah boot.
2. **Ongkos pemindahannya terbukti mahal dan rawan.** 96 patch, 17 repo, dan tiga pemblokir
   build yang semuanya lahir dari proses pemindahan itu sendiri
   (`frameworks_base/0014`+`0015` berpasangan dengan telephony, `RenderEngineThreaded.cpp`
   rusak oleh resolver otomatis).
3. **Perangkat ini bukan perangkat harian bersertifikat.** `/data` tidak terenkripsi (fstab
   tanpa `encryptable=`), SELinux permissive, dan ROM ditandatangani testkey. Menuntut ASB
   terbaru di atas fondasi itu tidak konsisten.
4. **Preseden eksternal.** retiredtab (§1.1) memakai UL untuk LOS 21 di QCOM legacy.

**Yang harus tetap dilakukan meski memakai UL** — UL bukan peluru perak:

| Item | Status di UL 21 | Verifikasi |
|---|---|---|
| RenderEngine GLES | ✅ ada | `libs/renderengine/gl/` ada di UL, tidak di official |
| adbd FunctionFS legacy | ✅ ada | `daemon/usb_legacy.cpp` ada di UL |
| eBPF non-fatal, memfd gate | ✅ ada | seri T0 menyatu di basis |
| **Camera HAL1 `device1/`** | ❌ **tidak ada** | API GitHub: `device1` TIDAK ADA di UL 21 |
| **`zip -y` saat kemas OTA** | ❌ **tidak ada** | `build/make/tools/releasetools/non_ab_ota.py:608` masih `["zip", tmpfile, "-r", ".", "-0"]` |
| **`String8::string()` di qcom-caf msm8916** | ❌ masih dipakai | audio 1 berkas, display 3 berkas |
| `PRODUCT_COMPRESSED_APEX` | ✅ **sudah `false`** | `updatable_apex.mk:26`, commit `1d10d6898b` — persis commit yang retiredtab kirim sebagai patch |
| `QCOM_BOARD_PLATFORMS += msm8916` | ✅ **sudah ada** | `hardware/qcom-caf/common/qcom_boards.mk:22` |
| `hardware/qcom-caf/msm8916` | ✅ ada | `snippets/losul.xml` |
| `device/qcom/sepolicy-legacy` | ✅ ada | `snippets/losul.xml`, lengkap dengan direktori `msm8916/` |
| RenderEngine GLES | ✅ ada | `frameworks/native/libs/renderengine/gl/` |
| adbd FunctionFS legacy | ✅ ada | `packages/modules/adb/daemon/usb_legacy.cpp` |
| `sysfs_disk_stat` dideklarasikan platform | ✅ ada | `system/sepolicy/public/file.te:22` |

Tinggal **tiga** baris ❌ — turun dari empat di draf pertama — dan seluruhnya diverifikasi
di tree yang sudah ter-sync, bukan lewat API GitHub.

Dua yang berpindah dari ❌ ke ✅ layak dicatat, karena keduanya sekaligus **perbedaan nyata
antara percobaan pertama dan sekarang**: ROM percobaan pertama mengirim 20 `.capex` dan
device tree-nya memaksa `QCOM_BOARD_PLATFORMS`. Di basis ini keduanya sudah benar tanpa kita
sentuh.

---

## 3. Sumber daya

### 3.1 Repo milik proyek

| | |
|---|---|
| Device tree | `rigaz29/rb_device_oppo_A37` — branch **baru** `lineage-21-ul`, dibuat dari `lineage-20` @ `15f7975` |
| Kernel | `rigaz29/kernel_oppo_msm8939` — branch `lineage-21` @ `8cc1519` (tanpa perubahan wajib) |
| Vendor blobs | `rigaz29/rb-vendor_oppo_A37` @ `2e5c6f7` — 320 blob, tidak berubah sejak 18.1 |

**Kenapa branch device tree BARU, bukan melanjutkan `lineage-21`:** branch itu memuat
sembilan commit yang sebagian dibuat untuk mengakali basis official — workaround
`BOARD_SEPOLICY_M4DEFS`, deklarasi `sysfs_disk_stat`, dan `target-level` 5. Sebagian akan
tetap perlu, sebagian tidak. Memulai dari `lineage-20` yang terbukti boot lalu memasang
ulang secara sadar lebih jujur daripada mewarisi tumpukan yang alasannya sudah berubah.

### 3.2 Basis dan referensi

```
repo init -u https://github.com/LineageOS-UL/android.git -b lineage-21.0
```

| Referensi | Dipakai untuk |
|---|---|
| `LineageOS-UL/*` | basis + branch `lineage-21.0-caf-msm8916`, `lineage-21.0-legacy` |
| `acroreiser/android_device_lenovo_a6010` `lineage-21.0` | pembanding device tree msm8916 A14 |
| `acroreiser/android_kernel_lenovo_a6010` | pembanding defconfig kernel 3.10 untuk A14 |
| `retiredtab/LineageOS-build-manifests` `21/` | resep + `UL-patches-2024` |
| ROM LOS 20 A37 kita | alat ukur level-A37 (§1.3) |

---

## 4. Temuan yang dibawa dari percobaan pertama

Ini bagian paling bernilai dari dokumen ini. Semuanya sudah **diverifikasi dengan build atau
dengan perangkat**, dan berlaku tanpa memandang basis.

### 4.1 Shim: bukan modul vendor

`libshim_camera` dan `libcamera_shim` harus **tidak** ber-`LOCAL_VENDOR_MODULE`. A14
(`binary.mk:1328`) hanya mengizinkan modul vendor menaut `native:vendor|vndk|platform_vndk`,
sementara shim kamera menaut `libsensor`, `libandroid`, `libstagefright`, `libmedia`,
`libgui`.

Dasar memindahkannya ke system, dari perangkat yang berjalan:

```
/linkerconfig/ld.config.txt   namespace.default.isolated = false
                              search.paths = /system/${LIB} … /vendor/${LIB}
llvm-readelf -d /system/vendor/lib/libshim_camera.so
                              DT_NEEDED libsensor/libandroid/libstagefright/libmedia
                              — kelimanya HANYA ada di /system/lib
```

Blob tetap menemukan shim: `TARGET_LD_SHIM_LIBS` bukan injeksi DT_NEEDED saat build,
melainkan cppflag ke linker, dan `bionic/linker/linker.cpp:1368` memuatnya **by name ke
namespace yang sama** dengan blob.

`libril_shim` **jangan disentuh** — lolos apa adanya, dan RIL subsistem yang terbukti.

### 4.2 `QCOM_BOARD_PLATFORMS += msm8916` — TIDAK diperlukan lagi

Di basis official, msm8916 dicabut dari `hardware/qcom-caf/common/qcom_boards.mk`, sehingga
gerbang `is-board-platform-in-list` di `media/Android.mk:5` false dan `mm-core/` +
`libstagefrighthw/` tak pernah di-include. Percobaan pertama menambalnya dari device tree.

**Di basis UL sudah ada:**

```
hardware/qcom-caf/common/qcom_boards.mk:22   QCOM_BOARD_PLATFORMS += msm8916
```

Jangan bawa tambalan device tree-nya. Efek samping yang dulu jadi bonus (`libbt-vendor`
ikut pulih) datang sendiri.

### 4.3 Empat modul yang hulu cabut di A14

| Lama | Baru |
|---|---|
| `android.hardware.drm@1.4-service.clearkey` | `android.hardware.drm-service.clearkey` (AIDL) |
| `android.hardware.wifi@1.0-service` | `android.hardware.wifi-service` (AIDL, `libwifi-hal` sama) |
| `vendor.lineage.trust@1.0-service` | dibuang — `hardware/lineage/interfaces/` tak punya `trust/` |
| `com.android.tethering.inprocess` + `InProcessNetworkStack` | dibuang **berpasangan** — varian in-process dicabut total di A14; memasang salah satunya sendirian mengulang ketidakcocokan sertifikat yang jadi akar bug aslinya |

### 4.4 Header yang tak lagi implisit

`hardware/*.h` dan `utils/*.h` harus diminta eksplisit:

```
LOCAL_HEADER_LIBRARIES += libhardware_headers      # gps ×5, sensors, power, camera, libcamera_shim
LOCAL_HEADER_LIBRARIES += libutils_headers          # power saja (menaut liblog+libcutils, bukan libutils)
```

### 4.5 `String8::string()` jadi privat

Ganti `c_str()`. Sebarannya: `frameworks/av` 29 titik, device tree 5 titik (`CameraWrapper`,
`libshims/android/sensor`), `qcom-caf/msm8916` audio 11 + display 4.

⚠️ Yang qcom-caf **tetap perlu** meski basis UL — branch `lineage-21.0-caf-msm8916` belum
disesuaikan untuk A14 meski namanya 21.0.

### 4.6 VINTF: `target-level` dan matrix ekstensi

`target-level="legacy"` **tidak bisa dibangun** di A14 — matrix untuk FCM legacy dicabut,
`VintfObject.cpp:1014` menolak, dan `check_vintf_compatible` ikut `droid_targets`
(`Makefile:5418`). Naikkan ke **5** (terendah yang punya matrix), lalu daftarkan sepuluh HAL
legacy/vendor sebagai `optional` di `framework_compatibility_matrix.xml`.

Jalan murahnya — mematikan `PRODUCT_ENFORCE_VINTF_MANIFEST` — **ditolak**: tanpa penegakan,
libhidl kehilangan `-DENFORCE_VINTF_MANIFEST` dan `ServiceManagement.cpp:967` menjalankan
`sleep(1)` di **setiap** `getRawServiceInternal()`.

⚠️ Terbuka: ROM jangkar a6000 tetap mengirim `target-level="legacy"` dan boot. Jadi `legacy`
sah saat **runtime**; yang menolaknya pemeriksaan saat **build**. Konsekuensi runtime dari
menaikkannya ke 5 belum pernah diuji — dan ini salah satu tersangka yang belum digugurkan.

### 4.7 sepolicy

- `sepolicy_freeze_test` **lolos** dengan tipe `sysfs_disk_stat` dideklarasikan platform
  lewat patch UL `4accd562e` — kekhawatiran proyek 20 tidak terwujud di 21 (diuji, rc=0).
- Workaround `BOARD_SEPOLICY_M4DEFS` **tidak diperlukan** kalau seri
  `device_lineage_sepolicy` UL terpasang: revert "qcom: Drop support for ultra legacy
  platforms" mengembalikan msm8916 ke dua daftar di `qcom/sepolicy.mk`. Dengan basis UL,
  patch itu sudah menyatu → workaround gugur sejak awal.
- `SELINUX_IGNORE_NEVERALLOWS` tetap wajib: 3.970 pelanggaran, 3.178 di antaranya milik
  `system/sepolicy` sendiri; hanya **satu** benar-benar dari device tree kita
  (`app_domain(timekeep_app)`).

### 4.8 `PRODUCT_COMPRESSED_APEX := false` — sudah beres di basis

Ditemukan lewat resep retiredtab (§1.1) dan sempat dicatat sebagai pekerjaan kita. Ternyata
UL sudah membawanya, lewat **commit yang sama persis** dengan yang retiredtab kirim sebagai
patch lepas:

```
build/make/target/product/updatable_apex.mk:26   PRODUCT_COMPRESSED_APEX := false
commit 1d10d6898b  "Set PRODUCT_COMPRESSED_APEX := false"
```

Nilainya tetap besar sebagai **variabel yang berubah**: ROM percobaan pertama mengirim 20
berkas `.capex` yang harus didekompresi apexd ke `/data` saat boot pada perangkat 2 GB;
build di basis ini tidak. Kalau ROM berikutnya boot, ini salah satu dari sedikit perbedaan
yang bisa menjelaskannya — jadi catat hasilnya, jangan cuma nikmati.

### 4.9 adb untuk bring-up

- `WITH_ADB_INSECURE := true` **masih didukung** di LOS 21 (`common.mk:26-36`), dan
  `post_process_props.py:33-42` masih menambahkan `adb` ke `persist.sys.usb.config`.
  Diverifikasi di build 20260810_034817: ketiganya ada di `/system/build.prop`, dan juga di
  `recovery/root/prop.default`.
- Dipilih ketimbang varian `eng`: manfaat adb sama, tanpa `ro.kernel.android.checkjni=1`.
- ⚠️ `PRODUCT_ADB_KEYS` **tidak cukup sendirian** di A14 — ia memasang ke `TARGET_ROOT_OUT`
  yang bukan lagi sumber ramdisk. Harus `PRODUCT_COPY_FILES` ke `TARGET_COPY_OUT_RAMDISK`.
  Verifikasi wajib sampai ke **artefak yang dikirim** (bongkar boot.img dari dalam zip),
  bukan ke berkas antara.

### 4.10 Batas mesin build — diukur

12 core, **12 GB RAM**, ccache dipangkas ke 8 GB.

```
-j10, swap 16 GB, swappiness 10   ninja OOM di 44%
-j10, swap 32 GB, swappiness 60   lolos fase Java (swap terpakai 18 GB)
-j6,  swap 10 GB                  soong_build OOM 2× (RSS 8,4 lalu 9,0 GB)
-j6,  swap 16 GB                  LOLOS
```

Dua hal berlawanan intuisi:
- `vm.swappiness=10` adalah penyebab OOM pertama, **bukan** kurang swap — heap JVM adalah
  halaman anonim, dan kernel memilih OOM daripada memakai 16 GB swap yang menganggur.
- Untuk `soong_build` swap nyaris tak menolong: proses Go, GC menyentuh seluruh heap.
  Saat dibunuh, swap baru terpakai 800 MB. Yang menolong hanya headroom RAM.

**Setelan kerja: `-j6`, swap ≥ 16 GB, `vm.swappiness=60`.** Disk: sisakan ≥ 25 GB sebelum
tahap pengemasan (`zip` gagal dengan exit 14 saat ruang menipis).

---

## 5. Fase

Urutan berbeda dari percobaan pertama. Di sana kamera didahulukan karena dianggap risiko
paling tak berbatas; ternyata kamera **bukan** yang menggagalkan — boot yang gagal, dan
kamera bahkan tidak pernah sempat diuji. Kali ini **boot didahulukan**, dan tidak ada fitur
yang dikerjakan sebelum ada homescreen.

### Fase 0 — Basis bersih dan hipotesis boot yang belum gugur

- [x] **Tree lama dihapus.** `/root/los21` basis official (260 GB) dibuang setelah
      diverifikasi: tujuh repo yang kita ubah semuanya bersih tanpa commit tertinggal, dan
      keempat patch yang §5 Fase 2 sebut wajib sudah ada di repo yang ter-push. Disk
      31 GB → 290 GB. Diamankan ke `/root/a37-21-archive/`: ROM `20260810_034817` (693 MB,
      untuk diagnosis ramoops), `boot-panic5.img`, `boot-21-userdebug.img`.
      `/root/.ccache` (7,6 GB) di luar tree, selamat.
- [x] **`repo init`** UL `lineage-21.0` → manifest `a156f53`, cocok dengan §1.4.
- [x] **Branch device tree `lineage-21-ul`** dibuat dari `lineage-20` @ `15f7975` dan
      di-push. Sengaja BUKAN melanjutkan `lineage-21` (§3.1).
- [x] **Local manifest** — **tiga** project saja (device tree, kernel, vendor), turun dari
      delapan. Resolve bersih: 1453 project, nol path ganda. Lihat koreksi §1.4.
- [x] **`repo sync`** — **bersih pada percobaan pertama**, 25 menit, 174 GB.
      1453 project, **0 HEAD kosong**. (`tools/sync-ul.sh`)
- [x] **Asumsi §4 diverifikasi ke tree, bukan ke API GitHub.** Enam dari sembilan ternyata
      sudah beres di basis; tiga tersisa jadi pekerjaan Fase 1–2 (tabel §2). Dua asumsi
      yang gugur — `QCOM_BOARD_PLATFORMS` (§4.2) dan `PRODUCT_COMPRESSED_APEX` (§4.8) —
      menghemat perubahan device tree yang percobaan pertama harus buat sendiri.
- [ ] **Uji hipotesis yang tertinggal dari percobaan 1, sebelum apa pun dibangun:**
      `PRODUCT_COMPRESSED_APEX := false` (§4.8), dan `boot-panic5.img` untuk memisahkan
      panic vs hang
- [ ] Ambil `console-ramoops` dari recovery setelah kegagalan berikutnya — ini masih
      satu-satunya sumber yang mengubah tebakan jadi jawaban

> ⚠️ **Jalan pulang belum ada di mesin ini.** ROM LOS 20 tidak tersimpan lokal (dicek: nol
> hasil). Sebelum mem-flash 21 lagi untuk ramoops, unduh dulu
> `lineage-20.0-20260808_130815` dari Releases proyek 20.

**Kriteria selesai:** penyebab stuck-di-logo teridentifikasi, atau tiga hipotesis di atas
tergugur dengan bukti.

### Fase 1 — Device tree ✅ SELESAI

**Kriteria selesai tercapai:** `m nothing` rc=0 (14:50 penuh, lalu 02:14 inkremental),
nol modul hilang, nol pelanggaran link-type, nol peringatan deprecated dari device tree.
Branch `lineage-21-ul` @ `a917725`.

- [x] §4.1 shim · §4.4 header (10 titik / 8 berkas) · §4.5 String8 (5 titik) ·
      §4.9 adb bring-up · buang salinan VNDK v28
- [x] §4.3 menyusut dari **empat modul jadi dua**: clearkey → AIDL, dan Trust HAL dibuang.
      Wi-Fi HIDL dan in-process tethering **tidak jadi diubah** — lihat di bawah.
- [x] **Tidak** dibawa: `BOARD_SEPOLICY_M4DEFS`, deklarasi `sysfs_disk_stat`,
      `QCOM_BOARD_PLATFORMS += msm8916` — ketiganya gugur di basis UL
- [x] `TARGET_USES_64_BIT_BINDER` dibuang (deprecated, tanpa efek)

**Dua asumsi §4.3 yang gugur saat diverifikasi ke tree.** Percobaan pertama memigrasikan
Wi-Fi ke AIDL dan membuang pasangan in-process tethering, karena official mencabut keduanya.
UL memulihkannya:

```
android.hardware.wifi@1.0-service      hardware/interfaces/wifi/1.6/default/Android.bp
InProcessNetworkStack                  packages/modules/NetworkStack/Android.bp
com.android.tethering.inprocess         packages/modules/Connectivity/Tethering/apex/Android.bp
```

Keduanya dibiarkan apa adanya. Ini menghemat perubahan **dan** menurunkan risiko: percobaan
pertama menyentuh dua subsistem yang di basis ini tidak perlu disentuh sama sekali.

#### 1.a Pemblokir baru yang tidak ada di percobaan pertama — `hardware/qcom/wlan`

```
error: dependency "libwifi-hal-qcom" of "libwifi-hal" missing variant:
         os:android,image:vendor,arch:arm_armv8-a_cortex-a53,sdk:,link:static
       available variants:
         <kosong>
```

"Available variants kosong" adalah petunjuknya — modulnya bukan salah varian, ia tidak punya
varian sama sekali. Konfigurasi sudah benar (`board_wlan_device: 'qcwcn'` ada di
`soong.lineage_A37.variables`), jadi akarnya tabrakan nama:

```
hardware/qcom/wlan/Android.bp:55            wifihal_qcom_defaults { name: "libwifi-hal-qcom" }
frameworks/opt/net/wifi/…/Android.bp:333    wifi_cc_prebuilt_library_static { name: "libwifi-hal-qcom" }
```

Keduanya tanpa `soong_namespace`. Modul `defaults` tidak punya varian build, sehingga
dependensi `libwifi-hal` jatuh ke sana. Diverifikasi dengan menyingkirkan `Android.bp`-nya
sementara: error hilang.

`hardware/qcom/wlan` melayani chip wcn6740/wcn3990; A37 memakai qcwcn, dan HAL kita dibangun
dari repo lain (`wifi_makefile_goal` mengambil hasil
`hardware/qcom-caf/wlan/qcwcn/wifi_hal/Android.mk`). Dibuang lewat `<remove-project>` di
`A37-21.xml`.

Pemblokir ini tidak muncul di percobaan pertama karena susunan repo WLAN di manifest official
berbeda — contoh konkret bahwa pindah basis memindahkan masalah, bukan hanya menghapusnya.

### Fase 2 — Patch yang tetap wajib meski basis UL
- [ ] `frameworks/av`: seri kamera HAL1 (2 patch — salin berkas + adaptasi A14). Sudah ada
      dan **terbukti kompilasi** di `patches/frameworks_av/`
- [ ] `qcom-caf/msm8916` audio+display: `String8::string()` → `c_str()`
- [ ] `build/make`: `zip -y` (`non_ab_ota.py`) — UL belum punya
- [ ] `tools/apply-a37-patches.sh` disesuaikan; `--check` harus hijau

**Kriteria selesai:** `m libcameraservice`, `m cameraserver` rc=0.

### Fase 3 — VINTF & SEPolicy
- [ ] §4.6 `target-level` + `framework_compatibility_matrix.xml`
- [ ] Ukur ulang neverallow; `SELINUX_IGNORE_NEVERALLOWS` tetap

**Kriteria selesai:** `m check-vintf-all sepolicy_freeze_test selinux_policy` rc=0.

### Fase 4 — Build
- [ ] `m bacon -j6` dengan setelan §4.10
- [ ] `tools/verify-rom.sh` hijau seluruhnya

### Fase 5 — Boot
- [ ] Flash, dan **kalau gagal, ambil `console-ramoops` sebelum mencoba apa pun**
- [ ] Jalan pulang disiapkan lebih dulu: `lineage-20.0-20260808_130815` dari Releases proyek
      20 sudah diunduh (ROM LOS 20 **tidak ada lagi** di mesin build)

### Fase 6 — Fungsi, hanya setelah homescreen
Kamera · RIL · Wi-Fi · Bluetooth · audio · sensor. Matriks paritas terhadap ROM 20.

---

## 6. Risiko yang diakui

| Risiko | Dampak | Mitigasi |
|---|---|---|
| **Penyebab boot belum diketahui** | UL sebagai basis mungkin tidak menyembuhkannya | Fase 0 menaruh diagnosis SEBELUM pekerjaan lain |
| ASB 2025-03 | 15 bulan patch keamanan absen | §2 — dinyatakan, bukan disembunyikan; `/data` memang tidak terenkripsi |
| UL beku sejak April 2025 | tidak ada perbaikan hulu baru | Semua yang kita butuhkan sudah ada di dalamnya; yang kurang ada di §2 |
| `target-level=5` belum teruji runtime | bisa jadi penyebab boot | a6000 memakai `legacy` dan boot — pertimbangkan mengembalikannya kalau Fase 5 gagal |
| Blob kamera A37 ≠ a6010 | HAL1 jalan di framework, belum tentu di blob A37 | Baru diuji Fase 6; bukan kriteria boot |
| Disk | tree UL ± 170 GB + `out/` ± 60 GB | Sisakan ≥ 25 GB sebelum pengemasan |

---

## 7. Yang sengaja TIDAK dikerjakan

| Item | Alasan |
|---|---|
| Seri RIL (`frameworks/opt/telephony`, `hardware/ril`) | Proyek 20 menundanya sampai paritas tercapai. RIL satu-satunya subsistem yang terbukti berfungsi; menyentuhnya saat mengejar kegagalan boot menambah risiko tanpa keuntungan |
| SELinux enforcing | Fase tersendiri, setelah homescreen stabil |
| Spoof versi kernel (4.9.337) | Opsional — kerjakan hanya bila ada pemeriksaan yang benar-benar menolak, bukan preventif |
| Migrasi ke basis official | Sudah dicoba dan gagal; lihat §2 |

---

## Lampiran — perintah yang mereproduksi data dokumen ini

```bash
# §1.1 resep retiredtab
curl -s https://raw.githubusercontent.com/retiredtab/LineageOS-build-manifests/main/21/msm8974/21-msm8974-build-instructions

# §1.4 status beku UL
curl -s "https://api.github.com/repos/LineageOS-UL/android/commits?sha=lineage-21.0&per_page=3"

# §2 UL 21 tidak punya camera HAL1
curl -s "https://api.github.com/repos/LineageOS-UL/android_frameworks_av/contents/services/camera/libcameraservice?ref=lineage-21.0" | grep -c device1

# §2 UL 21 belum punya zip -y
curl -s https://raw.githubusercontent.com/LineageOS-UL/android_build/lineage-21.0/tools/releasetools/non_ab_ota.py | grep -n '"zip", tmpfile'

# §1.4 koreksi: losul.xml-lah yang menyediakan msm8916, BUKAN lineage.xml
grep -rn "msm8916/audio" .repo/manifests/*.xml .repo/manifests/snippets/*.xml

# §4.8 jumlah apex terkompresi
ls out/target/product/A37/system/apex/*.capex | wc -l
```
