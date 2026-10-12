# Panduan menjalankan Drop Point Operations Intelligence

Panduan ini untuk **instalasi lokal yang sudah ada di laptop proyek**. Database demo dan credential lokal tersimpan di luar Git. Jika memulai dari clone GitHub yang masih kosong, baca bagian “Instalasi baru” di akhir sebelum berharap dashboard menampilkan data.

Untuk urutan penggunaan setelah layanan menyala, mulai dari [panduan pengguna langkah demi langkah](PANDUAN_PENGGUNA_STEP_BY_STEP.pdf): isi email dan password, lihat akses Regional/DP Manager, lalu gunakan Telegram.

## Peta layanan

| Layanan | Alamat lokal | Fungsi |
| --- | --- | --- |
| PostgreSQL | `localhost:5433` | Data operasional dan sesi |
| FastAPI | `http://127.0.0.1:8000` | KPI, autentikasi, batas akses, chat |
| n8n | `http://127.0.0.1:5678` | Simulator, laporan, alert, webhook |
| Dashboard React/Vite | `http://127.0.0.1:5173` | Website Regional/DP Manager |
| ngrok | Domain HTTPS milik akun | Meneruskan webhook Telegram ke n8n lokal |

Gunakan PowerShell. Semua perintah berikut dijalankan dari folder utama proyek kecuali jika disebutkan lain.

```powershell
cd 'D:\BISMILLAH DATA\Project\Data Analyst\Drop Point Operations Intelligence'
```

## 1. Nyalakan layanan inti

1. Buka Docker Desktop dan tunggu sampai mesinnya siap.
2. Jalankan container. `--build` memastikan perubahan FastAPI lokal ikut dipakai.

```powershell
docker compose up -d --build
docker compose ps
```

3. Periksa API dan n8n:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
Invoke-RestMethod http://127.0.0.1:5678/healthz
```

Keduanya seharusnya menampilkan status `ok`. PostgreSQL harus bertanda `healthy` pada `docker compose ps`. Bila baru saja dimulai ulang, tunggu beberapa detik lalu ulangi pemeriksaan.

## 2. Buka jalur Telegram

Bot memakai webhook, sehingga Telegram memerlukan HTTPS publik. Ngrok meneruskan HTTPS ke port n8n lokal `5678`; alamat ngrok yang dipakai tercatat pada `N8N_WEBHOOK_URL` di `.env` lokal.

1. Buka **PowerShell kedua**. Jalankan ngrok dengan domain akun Anda, misalnya:

```powershell
ngrok http 5678 --url https://DOMAIN-ANDA.ngrok-free.dev
```

Ganti `DOMAIN-ANDA.ngrok-free.dev` dengan domain yang sama persis seperti `N8N_WEBHOOK_URL` di `.env` (tanpa `/` di akhir perintah). Biarkan jendela ngrok terbuka. Jika muncul `ERR_NGROK_334`, endpoint sudah aktif; jangan membuat tunnel kedua. Setelah laptop restart, jalankan lagi perintah ini.

2. Pastikan URL publik tersebut dapat membuka `/healthz`, misalnya `https://DOMAIN-ANDA.ngrok-free.dev/healthz` dan menampilkan `{"status":"ok"}`.
3. Jika domain baru atau webhook belum terpasang, jalankan helper ini. Ia membaca token dari `.env` tanpa mencetaknya:

```powershell
.\.venv\Scripts\python.exe scripts\configure_webhook.py
.\.venv\Scripts\python.exe scripts\configure_webhook.py --check
```

Hasil yang diharapkan: `Webhook URL matches .env: True` dan `Pending updates: 0`. Kolom `Last error` dapat menyimpan kegagalan lama meskipun webhook terbaru berhasil; periksa eksekusi webhook di n8n bila ada keraguan. Untuk penggunaan rutin, `--check` saja cukup.

4. Dari akun Telegram **Regional Manager yang telah didaftarkan**, buka `https://t.me/drop_point_ops_bot` dan kirim pertanyaan seperti “Ringkas kondisi semua DP hari ini”. Bot tidak diperuntukkan bagi akun DP Manager dan tidak memakai kode penghubung.

**Jangan menyalin authtoken ngrok, token bot, atau chat ID pribadi ke dokumentasi publik maupun screenshot.**

## 3. Buka dashboard website

Buka **PowerShell ketiga**:

```powershell
cd 'D:\BISMILLAH DATA\Project\Data Analyst\Drop Point Operations Intelligence\frontend'
npm ci
npm run dev
```

`npm ci` cukup saat pertama kali atau setelah dependensi berubah. Selanjutnya `npm run dev` saja. Buka `http://127.0.0.1:5173/` di browser. Vite mengirim permintaan `/api` ke FastAPI lokal.

Gunakan email demo pada [DEMO_ACCOUNTS.md](DEMO_ACCOUNTS.md). Password hanya tersimpan pada `AKUN_DAN_PASSWORD_DEMO.txt` di folder utama **laptop lokal**; file itu tidak ada di GitHub. Jika diminta mengganti password pada login pertama, selesaikan lalu masuk kembali. Sesi browser tersimpan di memori dan hilang saat halaman dimuat ulang.

- **Regional Manager:** `Overview`, `Drop Points`, `Laporan`; dapat membuka detail DP sesuai grant region.
- **DP Manager:** `DP Saya`, `Laporan`; hanya melihat DP miliknya. Pada detail DP terdapat tab Operasi, Paket, Pengiriman, Seller & Pendapatan, PIC Seller, serta Tim & Tanggung Jawab.
- Laporan dapat difilter dan diunduh sebagai CSV. Bot Telegram dipakai di aplikasi Telegram, bukan sebagai menu website.

## 4. Periksa otomasi n8n

Buka `http://127.0.0.1:5678` dan masuk dengan akun n8n lokal. Pada instalasi saat ini ada lima workflow aktif:

| No. | Workflow | Pemicu saat ini (Asia/Jakarta) |
| --- | --- | --- |
| 01 | Data Generator | Setiap 5 menit, pukul 08–16, Senin–Jumat |
| 02 | Intraday Report | Pukul 10.00, 12.00, 14.00, 16.00, Senin–Jumat |
| 03 | Daily Report | Pukul 17.05, Senin–Jumat |
| 04 | Critical Alert | Setiap 5 menit mulai menit 02, pukul 08–16, Senin–Jumat |
| 05 | Telegram AI Chat | Webhook saat Regional Manager mengirim pesan |

Jadwal tersebut didokumentasikan dari workflow aktif dan tidak perlu diubah untuk membuka dashboard atau menguji bot. Contoh workflow di `n8n/workflows/` untuk GitHub **tidak** memuat credential dan disimpan `active: false`; sebelum dipakai pada instalasi baru, isi placeholder internal key/chat ID serta tautkan credential Telegram di n8n.

### Insight dan solusi dari laporan

Endpoint `/internal/reports/summary?include_insights=true` dan `/internal/reports/daily?include_insights=true` menambahkan maksimal tiga insight beserta saran tindakan pada data laporan. Fakta dan angka berasal dari database; AI memilih prioritas dan menyusun tindakan singkat. Jika penyedia AI gagal atau terlalu lama merespons, endpoint tetap mengembalikan saran berbasis aturan. Akses endpoint ini tetap memerlukan `X-Internal-Key`.

Pada bot Telegram, Regional Manager dapat mengetik `Beri insight dan solusi dari laporan harian` atau `Analisis laporan untuk DP [nama]`. Bot membaca laporan terbaru hanya untuk DP dalam grant regional. Kata `harian` atau `hari ini` memilih laporan harian; selain itu bot memakai ringkasan intraday. Ini memakai data simulasi lokal, bukan pencarian web.

Pesan laporan intraday dan harian diawali ringkasan seluruh DP serta total operasional, lalu rincian DP yang perlu perhatian dikirim pada bagian berikutnya. Alert menampilkan komponen kritis, angka pendukung, PIC, dan tindak lanjut. Setiap pesan diberi label data simulasi; ikon menunjukkan status dan jenis metrik. Format sumber berada di `n8n/formatters/`, dan `scripts/sync_report_formatters.py` menyalinnya ke contoh workflow publik. Lihat [Telegram dan reporting](TELEGRAM_DAN_REPORTING.md) untuk alur, contoh, dan batas pengujian.

Jika memasang format pada instalasi n8n lain, perbarui node `Code in JavaScript` pada **workflow yang sudah ada** dengan formatter yang sesuai. Simpan dan publikasikan workflow, lalu periksa pratinjau node Code tanpa menjalankan node Telegram. Pertahankan `Schedule Trigger`, URL laporan, credential, dan chat tujuan. File JSON di GitHub adalah contoh aman dan tidak memperbarui workflow aktif secara otomatis.

Untuk pembaruan lokal melalui CLI, `scripts/prepare_local_n8n_report_update.py` dapat mengambil ekspor privat workflow yang aktif dan mengganti hanya isi tiga node Code. Simpan hasilnya di `backup/` yang diabaikan Git. Pada mode n8n biasa, proses impor menonaktifkan workflow yang diimpor; publikasikan lagi workflow 02–04 dan mulai ulang n8n sebelum menganggap pembaruan selesai.

## 5. Pengujian dan pemecahan masalah

| Gejala | Periksa |
| --- | --- |
| Website tidak terbuka | `npm run dev` masih aktif; alamat `127.0.0.1:5173` benar |
| Login gagal | Email demo benar, password lokal terbaru, API dan PostgreSQL sehat |
| Dashboard kosong atau gagal memuat | `http://127.0.0.1:8000/health`, status Docker, dan grant akun |
| Bot tidak menjawab | ngrok aktif, `http://127.0.0.1:5678/healthz`, hasil `configure_webhook.py --check`, chat Telegram terdaftar |
| URL ngrok berubah | Perbarui `N8N_WEBHOOK_URL` di `.env`, jalankan `docker compose up -d --no-deps n8n`, lalu jalankan `configure_webhook.py` |
| Laporan tidak masuk | Periksa status workflow 02–04 dan eksekusi n8n; pastikan laptop/Docker menyala pada jam jadwal |
| Insight operasional memakai saran umum | Periksa koneksi penyedia AI dan konfigurasi `LLM_API_KEY`, `LLM_BASE_URL`, serta model lokal; laporan tetap memakai saran berbasis aturan |

Tes lokal yang tersedia:

```powershell
.\.venv\Scripts\python.exe scripts\run_local_tests.py
.\.venv\Scripts\python.exe scripts\run_local_tests.py --browser
```

Tes browser membuat akun sementara, menguji akses regional/DP, dan menghapus akun sementara. Cuplikan QA berada di `frontend/preview/`. Jalankan tes hanya saat API dan PostgreSQL lokal tersedia.

## 6. Menghentikan layanan

Tutup jendela Vite dan ngrok dengan `Ctrl+C`. Jika selesai memakai sistem, dari folder utama jalankan:

```powershell
docker compose stop
```

Menghentikan Docker/ngrok membuat bot tidak dapat menerima pesan, meskipun URL domain tetap sama. Volume PostgreSQL dan n8n tetap tersimpan oleh Docker Compose. Jangan gunakan `docker compose down -v` karena itu menghapus volume data lokal.

## 7. Instalasi baru dari GitHub

1. Clone repo dan salin `.env.example` menjadi `.env`; isi password/secret sendiri. Jangan commit `.env`.
2. Instal Docker Desktop, Python, Node.js, ngrok, serta buat bot Telegram dan akun penyedia LLM.
3. Repositori publik **tidak** berisi workbook sumber `data/`, backup, database Docker yang sudah terisi, atau password demo. Sediakan data contoh milik Anda dan terapkan migrasi SQL sesuai urutannya sebelum menjalankan sistem penuh. File `061_seed_manager_passwords.sql` memerlukan password sementara sebagai variabel psql dan menyimpannya hanya sebagai hash.
4. Sambungkan ulang credential Telegram serta placeholder pada contoh workflow n8n, lalu aktifkan workflow setelah API/data siap.
5. Jalankan langkah 1–5 di atas. Contoh migrasi dan model data ada di `sql/` dan [DATABASE_MODEL.md](DATABASE_MODEL.md).

Instalasi bersih belum menjadi proses satu perintah karena workbook sumber dan seed demo yang dapat dipublikasikan belum tersedia. GitHub Pages kelak dapat menayangkan frontend statis, tetapi FastAPI dan PostgreSQL tetap membutuhkan hosting HTTPS terpisah. Lihat [PRD](PRD_DROP_POINT_OPERATIONS_INTELLIGENCE.md) untuk cakupan, keamanan, dan langkah menuju produksi.
