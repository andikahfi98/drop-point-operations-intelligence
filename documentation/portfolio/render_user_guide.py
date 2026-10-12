"""Render the public, credential-free user guide PDF from tracked images."""

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfgen import canvas


DOCS = Path(__file__).resolve().parents[1]
OUT = DOCS / "PANDUAN_PENGGUNA_STEP_BY_STEP.pdf"
W, H = 960, 540
RED = colors.HexColor("#D80F20")
NAVY = colors.HexColor("#1B263A")
MUTED = colors.HexColor("#64748B")
LIGHT = colors.HexColor("#F3F5F8")
LINE = colors.HexColor("#D9E0E8")
WHITE = colors.white


def txt(c, value, x, y, size=12, color=NAVY, bold=False):
    c.setFont("Helvetica-Bold" if bold else "Helvetica", size)
    c.setFillColor(color)
    c.drawString(x, y, value)


def wrap(value, width, size=11, bold=False):
    font = "Helvetica-Bold" if bold else "Helvetica"
    words = value.split()
    lines, current = [], ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if pdfmetrics.stringWidth(candidate, font, size) <= width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def paragraph(c, value, x, y, width, size=11, leading=15, color=NAVY, bold=False):
    for line in wrap(value, width, size, bold):
        txt(c, line, x, y, size, color, bold)
        y -= leading
    return y


def card(c, x, y, width, height, fill=WHITE, stroke=LINE, radius=14):
    c.setFillColor(fill)
    c.setStrokeColor(stroke)
    c.roundRect(x, y, width, height, radius, fill=1, stroke=1)


def image_fit(c, path, x, y, width, height):
    reader = ImageReader(str(path))
    iw, ih = reader.getSize()
    scale = min(width / iw, height / ih)
    dw, dh = iw * scale, ih * scale
    c.drawImage(reader, x + (width - dw) / 2, y + (height - dh) / 2, dw, dh, mask="auto")


def base(c, number, eyebrow, title, subtitle=None):
    c.setFillColor(LIGHT)
    c.rect(0, 0, W, H, fill=1, stroke=0)
    c.setFillColor(RED)
    c.rect(0, H - 7, W, 7, fill=1, stroke=0)
    txt(c, "J&T EXPRESS", 50, 505, 14, RED, True)
    txt(c, "OPERATIONS INTELLIGENCE", 165, 505, 9, MUTED, True)
    txt(c, eyebrow.upper(), 50, 470, 10, RED, True)
    txt(c, title, 50, 438, 27, NAVY, True)
    if subtitle:
        paragraph(c, subtitle, 50, 413, 855, 11, 15, MUTED)
    c.setStrokeColor(LINE)
    c.line(50, 42, 910, 42)
    txt(c, "Panduan pengguna  |  data simulasi  |  tanpa password di PDF", 50, 24, 9, MUTED)
    txt(c, f"{number:02d} / 07", 867, 24, 9, RED, True)


def step(c, number, title, body, x, y, width, size=11):
    c.setFillColor(RED)
    c.roundRect(x, y - 5, 24, 24, 6, fill=1, stroke=0)
    txt(c, str(number), x + 8, y + 2, 11, WHITE, True)
    txt(c, title, x + 34, y + 2, 12, NAVY, True)
    return paragraph(c, body, x + 34, y - 20, width - 36, size, 15, NAVY) - 15


c = canvas.Canvas(str(OUT), pagesize=(W, H), pageCompression=1)
c.setTitle("Panduan Pengguna Drop Point Operations Intelligence")
c.setAuthor("Drop Point Operations Intelligence")
c.setSubject("Panduan langkah demi langkah untuk website dan Telegram dengan data simulasi")

# 1. Cover
c.setFillColor(WHITE)
c.rect(0, 0, W, H, fill=1, stroke=0)
c.setFillColor(RED)
c.rect(0, H - 8, W, 8, fill=1, stroke=0)
txt(c, "J&T EXPRESS  /  OPERATIONS INTELLIGENCE", 50, 488, 13, RED, True)
txt(c, "Panduan pengguna", 50, 411, 35, NAVY, True)
txt(c, "Drop Point Operations", 50, 371, 29, NAVY, True)
txt(c, "Intelligence", 50, 334, 29, RED, True)
paragraph(c, "Mulai dari login website, baca akses Regional dan DP Manager, lalu gunakan laporan serta bot Telegram.", 50, 285, 395, 14, 20, MUTED)
card(c, 50, 103, 395, 92, LIGHT, LIGHT, 14)
txt(c, "01  Login", 68, 160, 11, RED, True)
txt(c, "02  Dashboard sesuai peran", 68, 139, 11, NAVY, True)
txt(c, "03  Laporan dan Telegram", 68, 118, 11, NAVY, True)
card(c, 505, 98, 405, 338, WHITE, LINE, 14)
image_fit(c, DOCS / "images/PORTOFOLIO_04_Dashboard_Regional.png", 515, 108, 385, 318)
txt(c, "Demo lokal  |  enam Drop Point  |  data simulasi", 50, 35, 10, MUTED)
txt(c, "01 / 07", 866, 35, 10, RED, True)
c.showPage()

# 2. Login
base(c, 2, "Langkah 01", "Masuk ke website", "Gunakan satu akun demo sesuai peran. Password hanya dibaca dari file lokal pada laptop pemilik proyek.")
card(c, 50, 105, 423, 285)
y = 360
y = step(c, 1, "Buka dashboard", "Masuk ke http://127.0.0.1:5173/ setelah Docker dan frontend aktif.", 67, y, 386)
y = step(c, 2, "Isi Email", "Pilih email Regional Manager atau salah satu DP Manager pada daftar di sebelah kanan.", 67, y, 386)
y = step(c, 3, "Isi Password", "Buka AKUN_DAN_PASSWORD_DEMO.txt di folder utama proyek pada laptop lokal. Salin password yang sesuai dengan email.", 67, y, 386)
y = step(c, 4, "Pilih Masuk", "Jika diminta mengganti password, selesaikan formulirnya lalu login ulang.", 67, y, 386)
card(c, 490, 105, 420, 285)
txt(c, "Email demo", 508, 364, 14, NAVY, True)
accounts = [
    ("Regional Jabodetabek", "regional.jabodetabek@demo.local"),
    ("DP Jakarta Barat", "manager.jakarta.barat@demo.local"),
    ("DP Jakarta Timur", "manager.jakarta.timur@demo.local"),
    ("DP Tangerang", "manager.tangerang@demo.local"),
    ("DP Bekasi", "manager.bekasi@demo.local"),
    ("DP Depok", "manager.depok@demo.local"),
    ("DP Bogor", "manager.bogor@demo.local"),
]
for i, (label, email) in enumerate(accounts):
    yy = 334 - i * 31
    if i % 2 == 0:
        c.setFillColor(LIGHT)
        c.roundRect(503, yy - 10, 394, 28, 5, fill=1, stroke=0)
    txt(c, label, 510, yy + 3, 9.4, NAVY, True)
    txt(c, email, 666, yy + 3, 9.0, MUTED)
txt(c, "Password tidak dicetak pada panduan publik ini.", 50, 82, 10, RED, True)
c.showPage()

# 3. Regional
base(c, 3, "Langkah 02", "Lihat dashboard Regional Manager", "Akun regional membaca seluruh Drop Point yang diberikan oleh grant wilayahnya.")
card(c, 50, 83, 563, 309)
image_fit(c, DOCS / "images/PORTOFOLIO_04_Dashboard_Regional.png", 58, 91, 547, 293)
card(c, 629, 83, 281, 309)
y = 359
y = step(c, 1, "Overview", "Baca tren 7 atau 14 hari, KPI, paket tertahan, SLA, dan prioritas operasional.", 646, y, 247, 10.5)
y = step(c, 2, "Drop Points", "Cari, filter, urutkan, lalu buka satu lokasi untuk menyelidiki detailnya.", 646, y, 247, 10.5)
y = step(c, 3, "Enam tab detail", "Operasi; Paket; Pengiriman; Seller & Pendapatan; PIC Seller; Tim & Tanggung Jawab.", 646, y, 247, 10.5)
y = step(c, 4, "Laporan", "Gunakan filter dan unduh CSV untuk DP dalam akses regional.", 646, y, 247, 10.5)
c.showPage()

# 4. DP Manager
base(c, 4, "Langkah 03", "Lihat dashboard DP Manager", "Setelah login, DP Manager diarahkan ke DP Saya. Detail dan laporan dibatasi pada lokasi miliknya.")
card(c, 50, 83, 563, 309)
image_fit(c, DOCS / "images/PORTOFOLIO_05_Detail_Drop_Point.png", 58, 91, 547, 293)
card(c, 629, 83, 281, 309)
y = 359
y = step(c, 1, "Masuk dengan akun DP", "Contoh: manager.bogor@demo.local membuka Drop Point Bogor.", 646, y, 247, 10.5)
y = step(c, 2, "Buka DP Saya", "Periksa status, arus paket, antrean, SLA, seller, dan PIC lokasi.", 646, y, 247, 10.5)
y = step(c, 3, "Telusuri isu", "Cari resi atau seller; baca umur paket, alasan, dan penanggung jawab.", 646, y, 247, 10.5)
y = step(c, 4, "Buka Laporan", "Data DP lain tidak muncul. API juga menolak URL detail lintas DP.", 646, y, 247, 10.5)
c.showPage()

# 5. Telegram
base(c, 5, "Langkah 04", "Gunakan bot Telegram regional", "Bot dipakai langsung di Telegram oleh Regional Manager, bukan lewat menu website.")
card(c, 50, 88, 496, 304)
y = 359
y = step(c, 1, "Pastikan layanan aktif", "Docker dan n8n harus hidup. Tunnel ngrok dan webhook Telegram harus menunjuk ke n8n lokal.", 67, y, 460)
y = step(c, 2, "Buka bot", "Dari akun Telegram regional yang didaftarkan, buka t.me/drop_point_ops_bot.", 67, y, 460)
y = step(c, 3, "Tanyakan kondisi", "Contoh: Beri insight dan solusi dari laporan harian; atau Analisis laporan untuk DP Tangerang.", 67, y, 460)
y = step(c, 4, "Baca tindakan", "Jawaban memakai data internal dalam akses regional. Bot tidak melakukan pencarian web.", 67, y, 460)
card(c, 561, 88, 349, 304)
image_fit(c, DOCS / "images/telegram/TELEGRAM_01_Laporan_Harian.png", 574, 101, 323, 278)
txt(c, "Contoh laporan harian - uji format, data simulasi", 562, 67, 9, MUTED)
c.showPage()

# 6. Reports
base(c, 6, "Langkah 05", "Baca laporan dan alert", "Jadwal di bawah adalah konfigurasi lokal yang terakhir dicatat. Periksa riwayat n8n untuk memastikan pengiriman aktual.")
card(c, 50, 276, 860, 117)
rows = [
    ("Intraday", "10.00 / 12.00 / 14.00 / 16.00 WIB", "Status DP, total, isu, insight dan tindakan"),
    ("Harian", "17.05 WIB", "Hari ini, bulan berjalan, DP perlu perhatian"),
    ("Alert", "Pemeriksaan tiap 5 menit pada jam kerja", "Perubahan status, sebab, PIC, tindak lanjut"),
]
for i, (name, schedule, detail) in enumerate(rows):
    yy = 363 - i * 33
    if i:
        c.setStrokeColor(LINE)
        c.line(64, yy + 22, 896, yy + 22)
    txt(c, name, 66, yy, 10.5, RED, True)
    txt(c, schedule, 197, yy, 10, NAVY)
    txt(c, detail, 526, yy, 10, MUTED)
card(c, 50, 72, 408, 190)
card(c, 473, 72, 437, 190)
image_fit(c, DOCS / "images/telegram/TELEGRAM_02_Intraday.png", 64, 82, 380, 168)
image_fit(c, DOCS / "images/telegram/TELEGRAM_03_Alert.png", 487, 82, 409, 168)
txt(c, "Cuplikan intraday - uji format", 64, 55, 9, MUTED)
txt(c, "Cuplikan alert - skenario uji", 487, 55, 9, MUTED)
c.showPage()

# 7. Checks
base(c, 7, "Langkah 06", "Cek akses dan masalah umum", "Dua peran memakai website yang sama, tetapi melihat cakupan data yang berbeda.")
card(c, 50, 262, 860, 131)
txt(c, "Halaman / kanal", 68, 365, 10, MUTED, True)
txt(c, "Regional Manager", 398, 365, 10, MUTED, True)
txt(c, "DP Manager", 690, 365, 10, MUTED, True)
matrix = [
    ("Overview dan daftar seluruh DP yang diberi grant", "Ya", "Tidak"),
    ("Detail dan laporan DP", "Semua DP dalam grant", "Hanya DP sendiri"),
    ("Bot Telegram", "Chat regional terdaftar", "Tidak"),
]
for i, (label, regional, dp) in enumerate(matrix):
    yy = 334 - i * 31
    c.setStrokeColor(LINE)
    c.line(65, yy - 11, 896, yy - 11)
    txt(c, label, 68, yy, 10, NAVY)
    txt(c, regional, 398, yy, 10, NAVY)
    txt(c, dp, 690, yy, 10, NAVY)
card(c, 50, 84, 860, 164)
txt(c, "Jika tidak berhasil", 68, 219, 13, NAVY, True)
checks = [
    "Website tidak terbuka: periksa frontend pada 127.0.0.1:5173.",
    "Login gagal: cocokkan email dan password terbaru di file lokal; periksa API dan PostgreSQL.",
    "Dashboard kosong: periksa API /health, Docker, dan grant akun.",
    "Bot diam atau laporan tidak masuk: periksa n8n, ngrok, webhook, dan riwayat eksekusi.",
]
for i, line in enumerate(checks):
    txt(c, f"{i + 1:02d}", 69, 191 - i * 27, 10, RED, True)
    txt(c, line, 99, 191 - i * 27, 10, NAVY)
txt(c, "Rincian teknis: documentation/PANDUAN_MENJALANKAN_PROJECT.md", 50, 62, 10, MUTED)
c.showPage()

c.save()
print(OUT)
