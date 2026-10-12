# Dokumentasi Drop Point Operations Intelligence

Semua angka dan tanggal operasional pada proyek ini adalah **data simulasi**. Implementasi berjalan lokal di laptop proyek; repositori publik berisi kode, contoh workflow yang disanitasi, panduan, dan gambar portofolio, tetapi tidak berisi database terisi, file `.env`, credential, atau password.

## Urutan membaca

| Urutan | Dokumen | Isi |
| --- | --- | --- |
| 1 | [Panduan pengguna langkah demi langkah (PDF)](PANDUAN_PENGGUNA_STEP_BY_STEP.pdf) | Login, email demo, password lokal, tampilan Regional/DP Manager, laporan, dan Telegram |
| 2 | [Versi teks panduan pengguna](PANDUAN_PENGGUNA_STEP_BY_STEP.md) | Isi PDF dalam format yang mudah diedit dan ditelusuri |
| 3 | [Panduan menjalankan proyek](PANDUAN_MENJALANKAN_PROJECT.md) | Menyalakan Docker, API, ngrok, n8n, dashboard, serta pemecahan masalah |
| 4 | [Sistem dan alur operasional](SISTEM_DAN_ALUR.md) | Proses parcel, peran, arsitektur, dashboard, dan hubungan antar-komponen |
| 5 | [Telegram dan reporting](TELEGRAM_DAN_REPORTING.md) | Bot regional, laporan harian, intraday, alert, insight AI, format, dan batas pengujian |

## Referensi teknis

| Dokumen | Isi |
| --- | --- |
| [PRD](PRD_DROP_POINT_OPERATIONS_INTELLIGENCE.md) | Tujuan produk, kebutuhan, persona, keamanan, serta kriteria penerimaan |
| [Model database](DATABASE_MODEL.md) | Entitas, lifecycle shipment, origin/destination, kepemilikan isu, dan migrasi |
| [API dan hak akses](AUTH_DASHBOARD_API.md) | Endpoint dashboard, autentikasi, pembatasan DP/region, dan endpoint internal |
| [Frontend](FRONTEND.md) | Halaman dashboard, perilaku sesi, QA, dan batas publikasi statis |
| [Akun demo](DEMO_ACCOUNTS.md) | Daftar email demo; password hanya di file lokal yang diabaikan Git |

## Gambar portofolio

[Studi kasus](images/PORTOFOLIO_01_Studi_Kasus.png) · [Proses operasional](images/PORTOFOLIO_02_Proses_Operasional.png) · [Arsitektur](images/PORTOFOLIO_03_Arsitektur_Sistem.png) · [Dashboard regional](images/PORTOFOLIO_04_Dashboard_Regional.png) · [Detail Drop Point](images/PORTOFOLIO_05_Detail_Drop_Point.png) · [Otomasi dan AI](images/PORTOFOLIO_06_Automasi_dan_AI.png).

Contoh pesan Telegram dari chat uji disimpan bersama gambar website: [laporan harian](images/telegram/TELEGRAM_01_Laporan_Harian.png), [intraday](images/telegram/TELEGRAM_02_Intraday.png), dan [alert](images/telegram/TELEGRAM_03_Alert.png). Ketiganya adalah pratinjau format dengan data simulasi, bukan bukti pemicu terjadwal. Penjelasan tiap pesan ada di [Telegram dan reporting](TELEGRAM_DAN_REPORTING.md).

Sumber gambar portofolio website yang dapat diedit berada di [`portfolio/portfolio.html`](portfolio/portfolio.html). `portfolio/render.mjs` membuat ulang keenam PNG website di `images/`; tiga screenshot Telegram diambil langsung dari chat uji dan tidak dibuat ulang oleh skrip itu.

Catatan pribadi, riwayat instruksi lama, dan cara masuk ke layanan lokal ada di `documentation/local/` pada laptop proyek dan diabaikan Git. Berkas kredensial demo tetap di folder utama laptop sesuai kebutuhan pemilik proyek.
