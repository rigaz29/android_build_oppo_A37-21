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
