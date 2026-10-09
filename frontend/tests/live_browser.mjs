import { chromium } from 'playwright';
import { mkdir } from 'node:fs/promises';

const browser = await chromium.launch({ headless: true, executablePath: 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe' });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1, acceptDownloads: true });
const errors = [];
page.on('pageerror', (error) => errors.push(error.message));

try {
  await page.goto('http://127.0.0.1:5173/', { waitUntil: 'networkidle' });
  await page.getByLabel('Email').fill(process.env.TEST_EMAIL);
  await page.getByLabel('Password', { exact: true }).fill(process.env.TEST_PASSWORD);
  await page.getByRole('button', { name: 'Masuk', exact: true }).click();
  await page.getByRole('heading', { name: /Operasional/ }).waitFor();
  await page.locator('.v2-performance tbody tr').first().waitFor();
  const before = await page.locator('.v2-performance tbody tr').count();
  if (before !== 6) throw new Error(`Regional dashboard shows ${before} Drop Points instead of 6`);
  await page.locator('.v2-chart-point').last().locator('circle').first().hover();
  await page.getByText('DATA TERPILIH').waitFor();
  await mkdir('preview', { recursive: true });
  await page.screenshot({ path: 'preview/overview-v2-live.png', fullPage: true });

  const firstName = await page.locator('.v2-performance tbody tr').first().locator('td').first().locator('strong').innerText();
  await page.getByPlaceholder('Cari Drop Point').fill(firstName);
  if (await page.locator('.v2-performance tbody tr').count() !== 1) throw new Error('Drop Point search did not filter');
  await page.getByPlaceholder('Cari Drop Point').fill('');
  await page.getByRole('combobox', { name: 'Filter status' }).selectOption('NORMAL');
  const filteredCount = await page.locator('.v2-performance tbody tr').count();
  if (filteredCount > before) throw new Error('Status filter expanded results');
  await page.getByRole('combobox', { name: 'Filter status' }).selectOption('ALL');

  await page.locator('.v2-performance tbody tr').first().locator('button').click();
  await page.locator('.v2-detail-title h1').waitFor();
  await page.getByRole('heading', { name: 'Arus paket Drop Point' }).waitFor();
  await page.locator('.v2-data-loading').waitFor({ state: 'hidden' });
  await page.screenshot({ path: 'preview/detail-v2-live.png', fullPage: true });
  await page.getByRole('button', { name: 'Paket', exact: true }).click();
  await page.getByRole('heading', { name: 'Paket saat ini di DP' }).waitFor();
  if (await page.locator('.v2-data-table tbody tr').count() === 0) throw new Error('Parcel queue missing');
  await page.getByRole('button', { name: 'Pengiriman', exact: true }).click();
  await page.getByRole('heading', { name: 'Ketepatan pengiriman' }).waitFor();
  await page.getByRole('button', { name: 'Seller & Pendapatan' }).click();
  await page.getByRole('heading', { name: 'Daftar seller' }).waitFor();
  await page.getByRole('button', { name: 'PIC Seller' }).click();
  await page.getByRole('heading', { name: 'Performa PIC Seller' }).waitFor();
  await page.getByRole('button', { name: 'Tim & Tanggung Jawab' }).click();
  await page.getByRole('heading', { name: 'Struktur tim' }).waitFor();

  if (await page.getByRole('button', { name: 'Telegram', exact: true }).count()) throw new Error('Website still shows Telegram navigation');
  await page.getByRole('button', { name: 'Laporan', exact: true }).click();
  await page.getByRole('heading', { name: 'Laporan harian' }).waitFor();
  const [download] = await Promise.all([page.waitForEvent('download'), page.getByRole('button', { name: 'Unduh CSV' }).click()]);
  if (!download.suggestedFilename().endsWith('.csv')) throw new Error('Report export is not CSV');

  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole('button', { name: 'Buka menu' }).click();
  await page.getByRole('button', { name: 'Overview' }).click();
  await page.getByRole('heading', { name: /Operasional/ }).waitFor();
  await page.locator('.v2-chart-point').first().waitFor();
  await page.screenshot({ path: 'preview/overview-v2-mobile-live.png', fullPage: true });
  const rootOverflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
  if (rootOverflow > 2) {
    const offenders = await page.evaluate(() => [...document.querySelectorAll('*')].map((element) => ({ name: element.tagName.toLowerCase(), className: typeof element.className === 'string' ? element.className : '', right: Math.round(element.getBoundingClientRect().right) })).filter((item) => item.right > innerWidth + 2).slice(0, 12));
    const chain = await page.evaluate(() => { let node = document.querySelector('.v2-performance table'); const items = []; while (node && items.length < 9) { const style = getComputedStyle(node); items.push({ className: node.className, width: Math.round(node.getBoundingClientRect().width), scrollWidth: node.scrollWidth, overflowX: style.overflowX, minWidth: style.minWidth }); node = node.parentElement; } return items; });
    throw new Error(`Mobile root overflows by ${rootOverflow}px: ${JSON.stringify(offenders)}; chain=${JSON.stringify(chain)}`);
  }

  const dpPage = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  dpPage.on('pageerror', (error) => errors.push(error.message));
  await dpPage.goto('http://127.0.0.1:5173/', { waitUntil: 'networkidle' });
  await dpPage.getByLabel('Email').fill(process.env.TEST_DP_EMAIL);
  await dpPage.getByLabel('Password', { exact: true }).fill(process.env.TEST_DP_PASSWORD);
  await dpPage.getByRole('button', { name: 'Masuk', exact: true }).click();
  await dpPage.getByRole('heading', { name: 'Amankan akun Anda' }).waitFor();
  await dpPage.getByLabel('Password saat ini').fill(process.env.TEST_DP_PASSWORD);
  await dpPage.getByLabel('Password baru', { exact: true }).fill(process.env.TEST_DP_NEW_PASSWORD);
  await dpPage.getByLabel('Ulangi password baru').fill(process.env.TEST_DP_NEW_PASSWORD);
  await dpPage.getByRole('button', { name: /Simpan password baru/ }).click();
  await dpPage.getByText('Password berhasil diperbarui.').waitFor();
  await dpPage.getByLabel('Email').fill(process.env.TEST_DP_EMAIL);
  await dpPage.getByLabel('Password', { exact: true }).fill(process.env.TEST_DP_NEW_PASSWORD);
  const loginResponse = dpPage.waitForResponse((response) => response.url().endsWith('/api/auth/login') && response.status() === 200);
  await dpPage.getByRole('button', { name: 'Masuk', exact: true }).click();
  const token = (await (await loginResponse).json()).access_token;
  await dpPage.locator('.v2-detail-title h1').waitFor();
  await dpPage.locator('.v2-data-loading').waitFor({ state: 'hidden' });
  if (await dpPage.getByRole('button', { name: 'Overview', exact: true }).count()) throw new Error('DP Manager saw regional overview navigation');
  await dpPage.getByRole('button', { name: 'Paket', exact: true }).click();
  await dpPage.getByRole('heading', { name: 'Paket saat ini di DP' }).waitFor();
  await dpPage.screenshot({ path: 'preview/dp-manager-v2-live.png', fullPage: true });
  for (const suffix of ['', '/pulse', '/parcel-queue']) {
    const forbidden = await dpPage.request.get(`http://127.0.0.1:5173/api/drop-points/${process.env.TEST_OTHER_DP}${suffix}`, { headers: { Authorization: `Bearer ${token}` } });
    if (forbidden.status() !== 403) throw new Error(`Cross-DP ${suffix || 'detail'} request was not denied`);
  }
  if (errors.length) throw new Error(`Browser errors: ${errors.join(' | ')}`);
  console.log(`PASS: regional ${before} DPs, chart hover, search/filter, six detail pages, no Telegram menu, CSV, mobile; DP landing, parcel queue and cross-DP denial`);
} finally {
  await browser.close();
}
