# Telegram, reporting, dan insight AI

Telegram adalah kanal Regional Manager untuk menerima laporan/alert dan bertanya kepada bot. Website tidak memiliki menu Telegram. Bot memakai webhook n8n melalui ngrok ke FastAPI lokal; hanya chat regional yang dikonfigurasi lokal dapat meminta data. Tidak ada kode pairing. Semua contoh pada proyek ini memakai **data simulasi**.

## Alur pesan

| Workflow | Pemicu aktif saat dokumentasi ini dibuat (WIB) | Hasil |
| --- | --- | --- |
| 01 Data Generator | Tiap 5 menit, 08–16 Senin–Jumat | Memperbarui data simulasi |
| 02 Intraday Report | 10.00, 12.00, 14.00, 16.00 Senin–Jumat | Status DP, total operasional, rincian perhatian, insight/tindakan |
| 03 Daily Report | 17.05 Senin–Jumat | Kinerja hari ini dan bulan berjalan, rincian DP, insight/tindakan |
| 04 Critical Alert | Tiap 5 menit mulai menit 02, 08–16 Senin–Jumat | Perubahan status kritis, sebab, PIC, tindak lanjut |
| 05 Telegram AI Chat | Saat webhook menerima pesan | Jawaban berdasarkan data dalam akses regional |

Jadwal ini dicatat dari instalasi lokal yang diuji; dokumentasi tidak mengubahnya. Contoh workflow di `n8n/workflows/` tersimpan tanpa credential dan nonaktif saat impor. Instalasi baru harus mengisi credential serta placeholder sendiri. Langkah membuka Docker, ngrok, dan webhook ada di [panduan operasional](PANDUAN_MENJALANKAN_PROJECT.md).

## Bentuk laporan di chat

Laporan harian dan intraday diawali ringkasan enam DP serta total operasional. Bagian lanjutan merinci DP yang perlu perhatian: pendapatan, seller, paket di DP, usia paket, kinerja pengiriman, unit/PIC, dan tindakan. Emoji menandai jenis metrik dan tingkat status; garis pemisah memudahkan pemindaian di layar ponsel. Pesan panjang dipecah menjadi beberapa bagian berurutan.

Alert menampilkan DP dan perubahan status, komponen yang kritis atau waspada, KPI pendukung, alasan kritis, PIC unit, dan langkah tindak lanjut. Pesan uji diberi label jelas seperti `UJI FORMAT` atau `Data simulasi`; pesan pratinjau tidak boleh disalahartikan sebagai laporan terjadwal.

Sumber formatter yang dapat diedit adalah `n8n/formatters/daily.js`, `intraday.js`, dan `critical_alert.js`. Perubahan formatter pada repo tidak otomatis mengubah node Code di n8n yang aktif. `scripts/sync_report_formatters.py` menyelaraskan contoh workflow publik; pemasangan pada instalasi lain mengikuti prosedur di [panduan operasional](PANDUAN_MENJALANKAN_PROJECT.md#insight-dan-solusi-dari-laporan).

## Insight dan tanya jawab

Endpoint laporan internal menghitung status serta KPI dari database. AI memilih hingga tiga prioritas dan merumuskan tindakan dari sinyal tersebut; bila penyedia AI gagal, aturan operasional memberikan fallback. Bot dapat menjawab pertanyaan regional seperti “Beri insight dan solusi dari laporan harian” atau “Analisis laporan untuk DP Tangerang”. Jawaban dibatasi oleh grant akun regional, memakai data internal, dan tidak melakukan pencarian web.

Bot masuk melalui `POST /api/chat` dengan kunci internal dan pembatasan chat regional. Detail keamanan endpoint dan grant dijelaskan di [API dan hak akses](AUTH_DASHBOARD_API.md). Jangan menaruh token bot, internal key, chat ID, atau password dalam frontend, screenshot, atau dokumen publik.

## Bukti pengujian lokal

Pada uji format terakhir, **tujuh pratinjau** berhasil diterima di chat Telegram Regional Manager: tiga bagian laporan harian, tiga bagian intraday, dan satu alert skenario `WASPADA → KRITIS`. Pengiriman itu adalah pratinjau langsung melalui Bot API, bukan bukti bahwa jadwal n8n sudah memicu ketujuhnya. Kelima workflow tercatat aktif pada instalasi lokal saat pengujian; untuk memastikan eksekusi terjadwal tertentu, periksa riwayat eksekusi n8n pada tanggal dan jam terkait.

Chat Telegram juga memperlihatkan balasan insight AI dengan bagian temuan dan langkah. Screenshot langsung dari chat sudah ditinjau untuk memeriksa format, tetapi belum tersimpan di repositori karena alat tangkapan layar belum berhasil menyimpan berkas. Gambar [otomasi dan AI](images/PORTOFOLIO_06_Automasi_dan_AI.png) adalah visual portofolio, bukan screenshot pesan Telegram. Setelah cuplikan aman tersimpan, letakkan di `documentation/images/telegram/` dan tautkan dari bagian ini tanpa menyertakan daftar chat, chat ID, token, atau informasi pribadi.
