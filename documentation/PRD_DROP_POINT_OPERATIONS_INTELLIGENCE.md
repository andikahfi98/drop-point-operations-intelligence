# PRD — Drop Point Operations Intelligence

**Versi:** 0.3 (baseline prototipe yang berjalan)  
**Status:** Implementasi lokal; data simulasi  
**Pengguna utama:** Regional Manager dan DP Manager  
**Cakupan wilayah demo:** enam Drop Point Jabodetabek

## 1. Ringkasan produk

Drop Point Operations Intelligence adalah sistem pemantauan ekspedisi yang menggabungkan model data PostgreSQL, API FastAPI, dashboard React, otomasi n8n, serta bot Telegram. Tujuannya adalah membuat kondisi setiap Drop Point mudah dibaca, masalah operasional cepat ditemukan, dan laporan rutin terkirim tanpa menunggu manager membuka dashboard.

KPI dihitung dari SQL/Python dan disajikan melalui API. AI membantu menjelaskan data terstruktur dan menjawab pertanyaan Regional Manager; AI bukan sumber angka KPI. Implementasi saat ini berjalan lokal. Semua angka pada demo dan gambar portofolio adalah data simulasi, bukan hasil bisnis produksi.

## 2. Masalah yang diselesaikan

- Pemantauan manual mengharuskan manager membuka beberapa laporan dan membandingkan DP sendiri.
- Masalah paket, SLA, seller, dan pendapatan dapat tersebar di tampilan yang berbeda.
- Ringkasan periodik dan alert perlu hadir otomatis, bahkan saat dashboard tidak dibuka.
- DP Manager membutuhkan detail lokasi sendiri tanpa dapat membaca data DP lain.
- Regional Manager membutuhkan pembacaan lintas DP sekaligus jalur investigasi yang cepat.

## 3. Tujuan dan batas produk

### Tujuan

1. Menampilkan status regional dan detail tiap DP dari sumber data yang sama.
2. Memberi prioritas operasional berdasarkan KPI dan aturan yang dapat ditelusuri.
3. Mengirim laporan intraday, laporan harian, dan alert melalui n8n ke Telegram.
4. Menjawab pertanyaan Regional Manager di Telegram dengan akses yang dibatasi.
5. Menguji alur secara lokal sebelum mempertimbangkan hosting publik.

### Di luar cakupan prototipe saat ini

- Aplikasi produksi publik atau integrasi langsung dengan sistem resmi J&T.
- Login Telegram untuk DP Manager atau kode penghubung akun Telegram–website.
- Reset password mandiri, SSO, dan provisioning akun melalui UI.
- Penyimpanan FastAPI/PostgreSQL di GitHub Pages. Pages hanya dapat menayangkan frontend statis.
- Klaim dampak bisnis berdasarkan data nyata.

## 4. Persona dan hak akses

| Persona | Akses | Pengalaman utama |
| --- | --- | --- |
| Regional Manager | DP dalam grant region; enam DP pada demo | Overview lintas DP, daftar perbandingan, detail DP, laporan, bot Telegram |
| DP Manager | Hanya DP yang tercatat pada grant akun | Masuk ke `DP Saya`, enam tab detail, paket/isu setempat, laporan yang terfilter |

Backend memeriksa grant region/DP pada setiap endpoint dashboard. Permintaan DP di luar grant ditolak meskipun URL diubah secara manual. Telegram hanya menerima chat ID Regional Manager yang dikonfigurasi lokal.

## 5. Alur pengguna

1. Pengguna membuka website lokal dan masuk dengan email/password.
2. Jika `must_change_password` aktif, pengguna mengganti password dan masuk ulang.
3. Regional Manager membuka overview, memilih prioritas atau baris DP, lalu menyelidiki tab detail.
4. DP Manager langsung melihat DP miliknya, mencari resi/isu dan penanggung jawab.
5. Pengguna membuka laporan harian dan dapat mengunduh CSV sesuai aksesnya.
6. Regional Manager menerima laporan/alert dari n8n dan dapat bertanya ke bot Telegram.

Telegram tidak menjadi menu atau halaman di website.

## 6. Kebutuhan fungsional

### Dashboard

| ID | Kebutuhan | Status prototipe |
| --- | --- | --- |
| FR-01 | Login, logout, sesi 8 jam, ganti password wajib pada akun seed | Tersedia |
| FR-02 | Overview regional: tren 7/14 hari, KPI paket, SLA, pendapatan, usia paket | Tersedia |
| FR-03 | Prioritas operasional dan perbandingan enam DP dengan pencarian/filter/urut | Tersedia |
| FR-04 | Detail DP pada enam tab: Operasi, Paket, Pengiriman, Seller & Pendapatan, PIC Seller, Tim & Tanggung Jawab | Tersedia |
| FR-05 | Antrean paket dan isu dengan asal/tujuan, usia, alasan, PIC/unit penanggung jawab | Tersedia |
| FR-06 | Laporan harian terfilter dan ekspor CSV | Tersedia |
| FR-07 | Tampilan desktop dan ponsel, termasuk loading/empty/error state | Tersedia pada frontend |

### Data, otomasi, dan AI

| ID | Kebutuhan | Status prototipe |
| --- | --- | --- |
| FR-08 | Model shipment dengan origin DP, destination DP, seller, receiver, courier, dan revenue ongkir | Tersedia |
| FR-09 | Simulator memperbarui aktivitas operasional lokal | Workflow 01 aktif |
| FR-10 | Laporan intraday dan harian dari endpoint internal, dengan insight serta saran tindakan berbasis data | Tersedia pada workflow lokal 02–03 |
| FR-11 | Critical alert berdasarkan aturan operasional | Workflow 04 aktif |
| FR-12 | Bot Telegram menerima webhook dan memanggil chat API yang memakai data berizin | Workflow 05 aktif |
| FR-13 | KPI utama dihitung deterministik; AI menjelaskan hasil terstruktur | Tersedia |
| FR-14 | Regional Manager meminta insight dan solusi atas laporan terbaru lewat bot Telegram | Tersedia; API chat lokal telah diuji |

Jadwal workflow 01–04 mengikuti konfigurasi n8n yang sudah ada dan tidak diubah oleh dokumentasi ini. Contoh workflow publik di `n8n/workflows/` dinonaktifkan saat impor sampai credential dan placeholder diisi.

Insight laporan dibangun dari status DP, paket tertahan, SLA pengiriman, pace pendapatan, dan seller yang perlu perhatian. AI memprioritaskan sinyal dan menyusun tindak lanjut singkat tanpa menghitung ulang KPI. Jika AI tidak tersedia, saran berbasis aturan tetap dikirim. Laporan dan jawaban bot hanya menggunakan DP dalam lingkup akses yang berlaku.

Alur pesan, format terbaru, dan cakupan uji lokal didokumentasikan di [Telegram dan reporting](TELEGRAM_DAN_REPORTING.md).

## 7. Domain data dan definisi

Entitas inti mencakup Drop Point, unit, staf/PIC, seller, kurir, shipment, revenue ongkir, serta target seller dan pengiriman. `core.fact_revenue` merekam biaya kirim per invoice, bukan nilai barang atau COD. Seller adalah pengirim; receiver adalah pihak penerima. Origin DP menangani titik masuk paket, destination DP menangani sisi tujuan/last mile.

Alur normal shipment: `RECEIVED → SORTING → READY → IN_TRANSIT → ARRIVED_DESTINATION → OUT_FOR_DELIVERY → DELIVERED`. Akhir pengecualian: `FAILED` atau `RETURN_TO_SELLER`. Tanggung jawab ditentukan per unit lalu PIC; DP Manager adalah pemilik eskalasi lokasi. Rincian tabel dan view terdapat pada [DATABASE_MODEL.md](DATABASE_MODEL.md).

## 8. Arsitektur

```text
Simulator / data contoh → PostgreSQL (core + analytics) → FastAPI
                                                     ├→ React/Vite dashboard
                                                     └← n8n → Telegram
Telegram → HTTPS tunnel ngrok → webhook n8n → FastAPI chat → PostgreSQL/LLM API
```

PostgreSQL, FastAPI, dan n8n berjalan melalui Docker Compose lokal. Frontend Vite berjalan pada host lokal saat pengembangan. Tunnel ngrok hanya membuka alamat HTTPS agar Telegram dapat mengirim webhook ke n8n; laptop dan proses lokal harus tetap hidup. Untuk publikasi frontend di GitHub Pages, API dan database perlu hosting HTTPS terpisah, konfigurasi CORS eksplisit, dan penguatan login sebelum diluncurkan.

## 9. Keamanan dan privasi

- Password disimpan sebagai hash bcrypt-kompatibel; plaintext hanya ada pada berkas kredensial demo lokal yang diabaikan Git.
- Bearer token berlaku 8 jam; database menyimpan digest SHA-256, sedangkan frontend menyimpan token hanya di memori browser.
- API dashboard memeriksa sesi dan grant DP/region; endpoint otomasi memakai `X-Internal-Key`.
- Bot membatasi chat ID regional yang diizinkan; tidak ada kode pairing Telegram.
- `.env`, data lokal, backup, credential n8n, dan ekspor mentah workflow tidak masuk repositori publik.
- Sebelum produksi: tambahkan rate limiting login, manajemen secret terpusat, reset password, observabilitas, dan review keamanan deployment.

## 10. Kriteria penerimaan dan verifikasi

- Login regional dan DP Manager berhasil; akun seed yang wajib ganti password diarahkan dengan benar.
- DP Manager tidak dapat membaca detail DP lain melalui API.
- Overview menampilkan data dan chart; enam tab detail serta laporan dapat dibuka.
- n8n memuat lima workflow; laporan/alert menggunakan endpoint internal yang benar.
- Webhook Telegram menunjuk ke domain HTTPS aktif dan bot hanya mengizinkan akun regional yang didaftarkan.
- `tests/test_auth_integration.py` serta `frontend/tests/live_browser.py` menjadi smoke test untuk sesi, batas akses, grafik, filter, detail, dan tampilan ponsel.
- Gambar portofolio menandai angka/tanggal sebagai data simulasi dan tidak mengandung kredensial.

## 11. Dependensi, batasan, dan langkah berikutnya

Dependensi lokal: Docker Desktop, Python, Node.js, ngrok, akun Telegram bot, dan penyedia LLM kompatibel API. Repositori publik tidak menyertakan workbook sumber dan volume PostgreSQL yang sudah terisi; instalasi bersih memerlukan data sumber/seed serta migrasi SQL. Prototipe belum menjadi layanan dengan uptime publik: bila laptop atau tunnel berhenti, webhook bot tidak menerima pesan. Tahap berikutnya adalah bootstrap data demo yang dapat dipublikasikan, pipeline deployment terpisah untuk frontend/API/database, serta pengujian keamanan sebelum penggunaan nyata.
