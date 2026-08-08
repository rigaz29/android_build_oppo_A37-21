# ref/evidence — hasil bedah ROM LineageOS 21 a6000/a6010

Sumber: `lineage-21.0-20240526-UNOFFICIAL-a6000-ap1a-signed.zip` (609 MB, acroreiser).
Device: Lenovo a6000/a6010 — **msm8916, kernel 3.10.108, Android 14 (SDK 34)**.

⚠️ ROM-nya sendiri TIDAK di-commit (lihat `.gitignore`) dan **tidak punya URL publik yang
tercatat** — ia disediakan langsung oleh pemilik proyek. Berkas di sini adalah satu-satunya
salinan hasil bedahnya di dalam repo.

**Beda device dari A37, sama chipset dan sama versi kernel.** Menjawab pertanyaan level
chipset dan level Android 14 — bukan level A37 (panel, kamera, blob, dan RIL berbeda).

| Berkas | Isinya |
|---|---|
| `camera-hal1-symbols.txt` | **Bukti inti proyek ini.** Simbol `CameraHardwareInterface` + `DeviceInfo1` di `libcameraservice.so` Android 14 — membuktikan jalur Camera HAL1 bisa dipulihkan dan berjalan di A14 |
| `camera-hal-module.txt` | `camera.msm8916.so` = QCamera2 HAL1 murni (189 rujukan, nol QCamera3) + servis camera provider yang dikirim |
| `system-build.prop`, `vendor-build.prop` | properti ROM A14 msm8916 yang jalan |
| `vendor-vintf-manifest.xml` | matriks HAL, termasuk `camera.provider@2.5::ICameraProvider/legacy/0` |

Cara membuat ulang: `PLAN.md` Lampiran A.
