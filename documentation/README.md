# Dokumentasi Drop Point Operations Intelligence

Semua angka dan tanggal operasional pada proyek ini adalah **data simulasi**. Implementasi berjalan lokal di laptop proyek; repositori publik berisi kode, contoh workflow yang disanitasi, panduan, dan gambar portofolio, tetapi tidak berisi database terisi, file `.env`, credential, atau password.

| Mulai dari | Isi |
| --- | --- |
| [Panduan menjalankan proyek](PANDUAN_MENJALANKAN_PROJECT.md) | Urutan Docker, API, ngrok, Telegram, dashboard, n8n, pengujian, dan pemecahan masalah |
| [Sistem dan alur operasional](SISTEM_DAN_ALUR.md) | Proses parcel, peran, arsitektur, dashboard, dan hubungan antar-komponen |
| [Telegram dan reporting](TELEGRAM_DAN_REPORTING.md) | Bot regional, laporan harian, intraday, alert, insight AI, format, dan batas pengujian |
| [PRD](PRD_DROP_POINT_OPERATIONS_INTELLIGENCE.md) | Tujuan produk, kebutuhan, persona, keamanan, serta kriteria penerimaan |
| [Model database](DATABASE_MODEL.md) | Entitas, lifecycle shipment, origin/destination, kepemilikan isu, dan migrasi |
| [API dan hak akses](AUTH_DASHBOARD_API.md) | Endpoint dashboard, autentikasi, pembatasan DP/region, dan endpoint internal |
| [Frontend](FRONTEND.md) | Halaman dashboard, perilaku sesi, QA, dan batas publikasi statis |
| [Akun demo](DEMO_ACCOUNTS.md) | Email demo; password hanya di file lokal yang diabaikan Git |

## Gambar portofolio

[Studi kasus](images/PORTOFOLIO_01_Studi_Kasus.png) · [Proses operasional](images/PORTOFOLIO_02_Proses_Operasional.png) · [Arsitektur](images/PORTOFOLIO_03_Arsitektur_Sistem.png) · [Dashboard regional](images/PORTOFOLIO_04_Dashboard_Regional.png) · [Detail Drop Point](images/PORTOFOLIO_05_Detail_Drop_Point.png) · [Otomasi dan AI](images/PORTOFOLIO_06_Automasi_dan_AI.png).

Sumber gambar yang dapat diedit berada di [`portfolio/portfolio.html`](portfolio/portfolio.html). `portfolio/render.mjs` membuat ulang keenam PNG di `images/`; halaman dashboard pada gambar adalah data simulasi. Gambar Telegram dari chat asli belum disimpan sebagai berkas di repo; dokumentasi Telegram menjelaskan format pesan yang sudah diperiksa di chat lokal tanpa mempublikasikan identitas penerima.

Catatan pribadi, riwayat instruksi lama, dan cara masuk ke layanan lokal ada di `documentation/local/` pada laptop proyek dan diabaikan Git. Berkas kredensial demo tetap di folder utama laptop sesuai kebutuhan pemilik proyek.
