# Kegagalan boot LOS 21 — catatan diagnosis (10 Agustus 2026)

Status: **belum terpecahkan.** Berkas ini merekam apa yang sudah TERSINGKIR dan
apa yang masih terbuka, supaya siklus flash berikutnya tidak mengulang jalan yang
sudah buntu.

## Gejala, berurutan

| Build | Gejala |
|---|---|
| `20260809_105532` (96 patch UL belum ada) | setelah logo OPPO → **masuk fastboot** |
| `20260809_133142` (96 patch UL) | **stuck di logo OPPO**, adb tidak terdeteksi |
| `20260809_233640` (+ `/adb_keys` diperbaiki) | stuck di logo, **tidak ada entri USB sama sekali** |

Perpindahan dari "masuk fastboot" ke "stuck di logo" terjadi setelah 96 patch UL
dipasang. Itu perubahan perilaku nyata: bootloader kini menerima boot.img dan
menyerahkannya ke kernel.

## Sudah tersingkir — jangan diperiksa ulang tanpa alasan baru

| Dugaan | Bukti penyingkirannya |
|---|---|
| dt.img tidak cocok | byte-identik dengan LOS 20 (sha `459a2a6d…`) |
| boot.img melebihi partisi | 20,2 MB vs partisi 32 MB |
| kernel berbeda | **46 byte** berbeda dari LOS 20, seluruhnya stempel waktu build ("Sat Aug 8 13:10:00" vs "Sun Aug 9 23:39:31") — fungsional identik |
| ramdisk eng lebih rentan | ramdisk eng justru **560 byte lebih kecil** dari userdebug |
| `/adb_keys` menjelaskan "tidak terdeteksi" | tidak — itu soal otorisasi, bukan deteksi. (Cacatnya nyata dan sudah diperbaiki, tapi bukan penyebab ini) |
| varian build | eng menyetel `ro.secure=0`/`ro.adb.secure=0`; keduanya bekerja SETELAH adbd hidup |

## Hipotesis yang masih hidup: tumpang tindih kernel ↔ ramdisk

```
kernel  dimuat 0x80008000 .. 0x8117e678   (18.310.776 B)
ramdisk dimuat 0x81000000                 ← 1,5 MB di dalam kernel
```

Ekor kernel yang tertimpa berisi **31% byte bukan-nol** — data nyata.

| | ramdisk | ekor kernel yang selamat |
|---|---|---|
| LOS 20 (boot) | 1.352.145 B | 214.183 B utuh |
| LOS 21 (mati) | 1.664.219 B | nol |

⚠️ **Hipotesis ini internally inconsistent dan BELUM terbukti.** Kalau LK memakai
alamat header apa adanya, LOS 20 pun mestinya rusak — ia menimpa 1,35 MB data
kernel nyata dan tetap boot mulus berhari-hari. Kemungkinan besar LK merelokasi,
dan angka 214 KB itu kebetulan. LK OPPO tertutup, jadi tidak bisa dibaca.

Ujinya murah dan sudah disiapkan: `boot-eng-ramdisk-32m.img` — identik dengan
`boot-eng.img` kecuali `--ramdisk_offset 0x02000000` (jarak jadi 15 MB).

## Kompatibilitas kernel dengan Android 14 — DIPERIKSA, kernel bukan penyebabnya

Diperiksa 10 Agustus 2026 atas hipotesis: *adbd tidak hidup karena boot belum
pernah mencapai `on early-init`, akibat kegagalan di level kernel.*

Hipotesisnya masuk akal — kalau kernel gagal sebelum menjalankan init, tidak ada
yang bisa memicu `androidboot.init_fatal_reboot_target=recovery`, sehingga
perangkat memang akan diam di logo tanpa USB. Tapi setiap jalur kernel yang bisa
menghasilkan gejala itu dapat ditutup:

| Jalur kegagalan level kernel | Hasil pemeriksaan |
|---|---|
| kernel tidak bisa membuka ramdisk | ramdisk **gzip** (`1f8b 08`), didukung kernel 3.10 tanpa syarat |
| A14 menuntut fitur kernel baru | **tidak** — lihat pembandingan defconfig di bawah |
| kernel tidak menemukan `/init` | `/init` ada di akar ramdisk, 2.962.772 B, mode `rwxr-x---` |
| kernel tidak bisa meng-exec `/init` | ELF **statis**, nol `DT_NEEDED`, nol `PT_INTERP` |
| arsitektur init salah | ELF ARM **32-bit** — benar untuk userspace 32-bit device ini |
| kernel arm64 tak bisa jalankan userspace 32-bit | `CONFIG_COMPAT=y` |

### Pembandingan defconfig terhadap kernel yang BENAR-BENAR menjalankan LOS 21

Pembandingnya `acroreiser/android_kernel_lenovo_a6010` branch `lineage-21` —
msm8916, kernel 3.10.108, dan ROM-nya sudah dibedah di `ref/evidence/`. Branch
`lineage-21`-nya memang menambahkan seri **Incremental FS** (± 20 commit) dan
`FROMLIST: security: selinux: allow per-file labelling for binderfs` di atas
`lineage-20.0`. Tapi defconfig-nya **tidak mengaktifkan** satu pun:

```
                      a6010 lineage-21   A37
INCREMENTAL_FS            tidak diset    tidak diset
ANDROID_BINDERFS          tidak diset    tidak diset
FS_VERITY                 tidak diset    tidak diset
BPF_SYSCALL               tidak diset    tidak diset
CGROUP_BPF                tidak diset    tidak diset
OVERLAY_FS                tidak diset    tidak diset
PSI                       tidak diset    tidak diset
MEMCG                     tidak diset    y          ← kita punya LEBIH
SDCARD_FS / DM_VERITY / TMPFS_POSIX_ACL      y = y
```

Jadi kernel 3.10.108 menjalankan Android 14 **tanpa** fitur era-A14 satu pun.
Commit incfs/binderfs itu dibawa tapi tidak dipakai.

### Apa yang ini TIDAK buktikan

Bahwa init benar-benar berjalan. Yang terbukti hanya: semua yang kernel butuhkan
untuk menjalankan init sudah benar secara struktural. Dua kelas masih hidup —
kernel hang sebelum exec init (bukan karena hal-hal di tabel atas), atau init
jalan lalu **menggantung** (hang tidak memicu `InitFatalReboot`; crash akan).

Pembedanya sudah siap dan sudah diverifikasi isinya:
`/root/a37-21-archive/boot-panic5.img` — kernel dan ramdisk byte-identik dengan
`boot-21-userdebug.img`, hanya `panic=5` ditambahkan di cmdline.

```
flash boot-panic5.img  →  REBOOT BERULANG  = kernel panic, penyebab di kernel
                       →  tetap diam       = tidak ada panic, kernel hidup,
                                             macetnya di init atau setelahnya
```

## ⚠️ ramoops TIDAK PERNAH BERFUNGSI — dan sekarang sudah diperbaiki

Ditemukan 10 Agustus 2026. Ini membatalkan saran diagnosis yang diulang beberapa
kali di dokumen ini: membaca `console-ramoops` tidak akan pernah menghasilkan
apa pun, karena berkasnya tidak ada.

**Bukti dari perangkat nyata** yang menjalankan LOS 20 dengan `ramoops.*` lengkap
di cmdline (`report/bugreport.zip`):

```
incidentd: GZipSection failed to open file /sys/fs/pstore/console-ramoops
incidentd: GZipSection failed to open file /sys/fs/pstore/console-ramoops-0
incidentd: [gzip …] can't open all the files
```

**Akarnya** di `fs/pstore/ram.c` kernel ini. Konfigurasinya sudah benar
(`PSTORE=y`, `PSTORE_RAM=y`, `PSTORE_CONSOLE=y`, `PSTORE_PMSG=y`), tapi:

```c
pdata = devm_kzalloc(dev, sizeof(*pdata), GFP_KERNEL);   /* pdata baru, semua nol */
if (pdev->dev.of_node)
        ramoops_of_init(pdev);                           /* HANYA dari device tree */
if (!pdata->mem_size || …) {
        pr_err("The memory size and the record/console size must be non-zero");
        goto fail_out;
}
```

Upstream memakai `pdata = pdev->dev.platform_data` — struct yang dikirim
`ramoops_register_dummy()` dari parameter modul di cmdline. Backport dukungan DT
di kernel ini menghapus jalur itu, dan **tidak ada node `ramoops` di DTS mana
pun**. Jadi `pdata->mem_size` selalu nol dan probe selalu gagal.

**Perbaikan:** `patches/kernel/0001-pstore-ram-*.patch` (kernel commit
`6fa5298755d`) memulihkan jalur `platform_data`, aktif hanya bila `of_node` NULL
sehingga jalur DT tidak tersentuh. Sengaja BUKAN lewat node DT, supaya `dt.img`
tetap byte-identik dengan LOS 20 yang boot.

Ditambah ke cmdline — default `console_size`/`pmsg_size` cuma 4096:

```
ramoops.console_size=0x100000   1 MB   -> console-ramoops
ramoops.pmsg_size=0x40000     256 KB   -> pmsg-ramoops-0 (logcat terakhir)
ramoops.dump_oops=1
```

## Yang membatasi diagnosis — dan penggantinya

`ramoops` hanya bertahan pada reboot **hangat**. Cabut baterai = RAM hilang =
nol jejak. Jadi kegagalan boot yang berakhir dengan pencabutan baterai tidak
pernah bisa didiagnosis, dan itulah yang selama ini terjadi.

Karena itu **pengaman boot** ditambahkan (`rootdir/etc/bootwatchdog.sh`, device
tree commit `b871bcc`): kalau `sys.boot_completed` tidak muncul dalam 120 detik,
jejak disimpan ke `/data/bootfail` lalu perangkat reboot ke recovery. `/data`
tidak terenkripsi, jadi berkasnya terbaca dari recovery:

```
adb shell ls -l /data/bootfail
adb pull /data/bootfail
```

Empat kelas kegagalan dan penanganannya sekarang:

| Kelas | Penanganan | Status |
|---|---|---|
| kernel panic | `CONFIG_PANIC_TIMEOUT=5`, tidak ditimpa (`kernel/panic.c:45`) | sudah ada |
| CPU hang | `CONFIG_MSM_WATCHDOG_V2=y` | sudah ada |
| init FATAL | `androidboot.init_fatal_reboot_target=recovery` | sudah ada |
| **userspace menggantung** | `bootwatchdog.sh` | **BARU** |

⚠️ Konsekuensi penting dari tabel itu: karena panic **sudah** auto-reboot dan CPU
hang **sudah** memicu watchdog bite, kenyataan bahwa perangkat diam tanpa reboot
sudah membuktikan **tidak ada panic dan tidak ada CPU hang**. `boot-panic5.img`
dengan demikian redundan — `panic=5` hanya menyetel nilai yang sudah 5.

## Tiga lapis penyebab, semuanya ditemukan setelah ramoops hidup

Begitu ramoops berfungsi, "stuck di logo OPPO" ternyata bukan satu bug melainkan
tiga, bertumpuk. Masing-masing baru terlihat setelah yang di atasnya dibereskan.
Ketiganya regresi Android 14 — LOS 20 boot tanpa satu pun perbaikan ini.

| Lapis | Akar | Perbaikan | Bukti |
|---|---|---|---|
| 1 | `ro.vndk.version=current` padahal nol apex VNDK | properti DIBUANG dari `device.mk` | `report/1/pmsg-ramoops-0` |
| 2 | `ro.hardware.egl` tidak diset → `libEGL_msm8916.so` dicari, ROM punya `libEGL_adreno.so` | `ro.hardware.egl=adreno` | `report/bootfail/` |
| 3 | netd menggantung menunggu `bpf.progs_loaded` | dua tambalan di `packages/modules/Connectivity` | `report/bootfail2/` |

### Lapis 1 — linkerconfig SIGABRT, jadi tidak ada dynamic linking sama sekali

`ro.vndk.version=current` dengan nol apex VNDK membuat `variableloader.cc:84`
keluar dini sehingga `SANITIZER_DEFAULT_VENDOR` tidak pernah terdefinisi, tapi
`environment.cc:46 IsVendorVndkVersionDefined()` hanya memeriksa `has_value()` →
`vendordefault.cc:57 Var("SANITIZER_DEFAULT_VENDOR")` → `context.cc:101
CHECK(!"undefined var")` → SIGABRT. Tanpa `/linkerconfig/ld.config.txt`, SETIAP
biner dinamis gagal dimuat dan zygote tidak pernah jalan.

### Lapis 2 — SurfaceFlinger SIGABRT tiap 5 detik

`Loader.cpp:291-304` menelusuri kandidat suffix driver; karena `ro.hardware.egl`
kosong ia jatuh ke `ro.board.platform=msm8916`, mencoba `libEGL_msm8916.so`, lalu
`break` — tidak mencoba kandidat lain. ROM mengirim `libEGL_adreno.so`.

### Lapis 3 — netd menggantung selamanya, dan ini BUG DI PATCH UL SENDIRI

Rantai lengkapnya, dari `report/bootfail2/`:

```
netbpfload (t=15,17s) keluar 1 di NetBpfLoad.cpp:377
  -> execve ke /system/bin/bpfloader TIDAK PERNAH terjadi
  -> bpf.progs_loaded tidak pernah tersetel oleh siapa pun
netd -> libnetd_updatable_init -> kondisi ebpf TERBALIK -> BpfHandler::init()
  -> BpfHandler.cpp:166 waitForProgsLoaded() menunggu SELAMANYA (5/10/20/40/60s)
  -> netd tidak pernah mendaftarkan servis binder-nya
system_server -> StartNetworkManagementService -> "null INetd instance" -> macet
  -> sys.boot_completed tidak pernah datang -> bootwatchdog reboot ke recovery @120s
```

**Bug A — `netd/NetdUpdatable.cpp:34`, logika terbalik.**

```c
bool ebpf_supported = __system_property_get("ro.kernel.ebpf.supported", value) != 0
                      || strcmp(value, "false") == 0;
```

`__system_property_get` mengembalikan **panjang** nilai, bukan status. Dengan
`ro.kernel.ebpf.supported=false` ia mengembalikan 5 → `!= 0` benar → OR
hubung-singkat → `ebpf_supported = true`. Persis kebalikan dari judul commit yang
memperkenalkannya (UL `d0ed2f82c4`, "Disable bpf initialization when eBPF is not
available"). Jadi **menyetel properti itu justru MENYEBABKAN hang yang ia
maksudkan untuk mencegah.**

**Bug B — `netbpfload/NetBpfLoad.cpp:377`, satu jalur keluar yang terlewat.**

UL (`fce09cc548`) menambal setiap pemanggilan `createSysFsBpfSubDir` /
`writeProcSysFile` di `main()` menjadi `failed = true`, termasuk baris 369 — tapi
melewatkan `if (createSysFsBpfSubDir("loader")) return 1;` di baris 377. Kernel
3.10 kita **tidak punya `CONFIG_BPF_SYSCALL` sama sekali** (diperiksa di
`lineageos_a37f_defconfig`, 613 baris terbaca sebagai kontrol), jadi bpffs tidak
terdaftar, `/sys/fs/bpf` tidak ada, mkdir gagal, dan netbpfload keluar sebelum
`execve`. Justru di `/system/bin/bpfloader` itulah jalur gagal ber-patch UL
menyetel `bpf.progs_loaded=1` (`system/bpf/bpfloader/BpfLoader.cpp:223`).

Kegagalan ini **senyap total** karena UL sudah mengomentari `reboot_on_failure`
di `netbpfload.rc`. Tambalan kita ada di
`patches/packages_modules_Connectivity/`.

Cukup Bug A saja sebenarnya untuk melepas hang — `waitForProgsLoaded()` hanya
punya SATU pemanggil (`BpfHandler.cpp:166`, diverifikasi dengan grep seluruh
`packages/modules/Connectivity`, `system/`, `frameworks/base`). Bug B ditambal
juga karena ia satu baris, memulihkan maksud desain UL, dan melindungi kalau
`reboot_on_failure` suatu saat dihidupkan kembali.

Aman melewati `BpfHandler::init()`: `tagSocket` dijaga
`if (!mCookieTagMap.isValid()) return -EPERM;` (`BpfHandler.cpp:199`), dan UL
sudah mencabut abort-on-init-fail (`0012-Revert-netdupdatable-add-back-abort-on-init-fail`).

### Pelajaran metodologi

Dua kali dalam penelusuran ini instrumen yang salah hampir menyesatkan:

- `dmesg.txt` dari `bootfail2` hanya mencakup detik **132–134** — ring buffer
  kernel habis dibanjiri audit SELinux permissive. Pesan netbpfload dari detik 15
  sudah tergusur, jadi ketiadaannya di dmesg **bukan** bukti ia tidak jalan.
- `bpf.progs_loaded` tidak muncul di `getprop.txt` **dan** ada `avc: denied` untuk
  `comm="getprop"` pada `bpf_prop`. Ketiadaan itu baru sah sebagai bukti setelah
  dipastikan `ro.boot.selinux=permissive`, yang berarti denial dicatat tapi tidak
  memblokir.
- `find system/netd -name BpfHandler.cpp` mengembalikan kosong; berkasnya ada di
  `packages/modules/Connectivity/netd/`. Dan servis `bpfloader` didefinisikan di
  `netbpfload.rc`, bukan `bpfloader.rc` yang tidak ada di ROM — sempat membuat
  saya membaca loader yang salah (`system/bpf/bpfloader/BpfLoader.cpp`).

## Jalan pulang

`lineage-20.0-20260808_130815-UNOFFICIAL-A37.zip` (615 MB) ada di GitHub Releases
proyek 20. ROM LOS 20 sudah TIDAK ada lagi di mesin build (terhapus saat cleanup),
jadi itu satu-satunya sumber pemulihan — unduh SEBELUM eksperimen berikutnya.
