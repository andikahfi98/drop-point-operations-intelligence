# Drop Point Operations Intelligence — Web

Website internal J&T Express untuk pemantauan Drop Point. Antarmuka ini memakai API FastAPI lokal yang sudah ada; akses data tetap ditentukan oleh grant DP dan region di backend.

Rancangan layar overview dan detail DP yang bisa diedit tersedia di [Figma J&T Operations Intelligence](https://www.figma.com/design/IXMuveVYrGq41skubzCxwl). Angka dan tanggal di rancangan adalah cuplikan data simulasi; website mengambil data terbaru dari API lokal.

## Menjalankan secara lokal

Jalankan layanan Docker project (`postgres` dan `api`), lalu di folder `frontend`:

```powershell
npm install
npm run dev
```

Buka `http://127.0.0.1:5173/`. Vite meneruskan permintaan `/api` ke `http://127.0.0.1:8000`. Gunakan akun demo yang sudah disiapkan di database. Akun dengan `must_change_password` akan diarahkan ke formulir ganti password sebelum dashboard dibuka. Token sesi hanya disimpan di memori browser; memuat ulang halaman mengharuskan login kembali.

Daftar email akun demo ada di [DEMO_ACCOUNTS.md](DEMO_ACCOUNTS.md). Email dan password yang diuji tersimpan dalam `AKUN_DAN_PASSWORD_DEMO.txt` di folder utama project lokal.

## Yang tersedia

- Login, ganti password wajib, dan logout.
- Overview Regional Manager dengan ringkasan enam DP, tren harian 7/14 hari, prioritas operasional, umur paket, dan tabel DP yang bisa dicari serta diurutkan.
- Halaman Drop Points untuk perbandingan dan akses ke detail tiap DP.
- Enam halaman detail DP: Operasi, Paket, Pengiriman, Seller & Pendapatan, PIC Seller, serta Tim & Tanggung Jawab. Akun DP Manager langsung membuka DP miliknya; daftar paket dan isu hanya memuat data DP yang diizinkan backend.
- Chatbot dipakai langsung di Telegram oleh Regional Manager; website tidak menampilkan halaman Telegram.
- Laporan harian dengan filter dan unduhan CSV.
- Layout desktop dan ponsel. Data yang tampil berasal dari endpoint yang sudah membatasi akses pengguna.

Untuk QA otomatis saat API dan PostgreSQL Docker berjalan, jalankan dari root project:

```powershell
.\.venv\Scripts\python.exe frontend\tests\live_browser.py
```

Skrip membuat akun sementara, menguji login regional dan DP Manager, ganti password, akses lintas DP, grafik, pencarian/filter, enam halaman detail, tidak adanya menu Telegram, laporan, dan tampilan ponsel, lalu menghapus akun sementara. Hasil visual ada di `frontend/preview/`.

Frontend dapat dipublikasikan sebagai file statis kelak. Untuk GitHub Pages, FastAPI dan PostgreSQL tetap memerlukan hosting terpisah dengan HTTPS; atur `VITE_API_BASE_URL` ke alamat API tersebut dan tambahkan origin frontend ke CORS allowlist backend. Terapkan pembatasan percobaan login sebelum akses publik. Konfigurasi sekarang ditujukan untuk penggunaan lokal.

Logo J&T Express bersumber dari [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:J%26T_Express_logo.svg) untuk prototype internal ini.
