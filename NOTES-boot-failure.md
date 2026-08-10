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

## Yang akan menghentikan tebak-tebakan

`ramoops` aktif di cmdline (`ramoops.mem_address=0x9ff00000`). Recovery masih
LOS 20 dan tidak tersentuh flash mana pun, jadi masih bisa dimasuki:

```
adb shell "cat /sys/fs/pstore/console-ramoops" > lastboot.txt
adb shell "cat /proc/last_kmsg" > lastkmsg.txt
```

Kalau kernel sempat jalan sedetik pun, jejaknya di situ. Kalau adb di RECOVERY
juga tidak terdeteksi, itu temuan besar tersendiri — berarti masalahnya di sisi
USB/PC, bukan di ROM.

## Jalan pulang

`lineage-20.0-20260808_130815-UNOFFICIAL-A37.zip` (615 MB) ada di GitHub Releases
proyek 20. ROM LOS 20 sudah TIDAK ada lagi di mesin build (terhapus saat cleanup),
jadi itu satu-satunya sumber pemulihan — unduh SEBELUM eksperimen berikutnya.
