import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const require = createRequire(path.join(root, 'frontend', 'package.json'));
const { chromium } = require('playwright');
const browser = await chromium.launch({ channel: 'msedge', headless: true });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, reducedMotion: 'reduce' });
await page.goto(pathToFileURL(path.join(here, 'portfolio.html')).href);
await page.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map((image) => image.decode().catch(() => {}))); });
const missing = await page.evaluate(() => [...document.images].filter((image) => !image.naturalWidth).map((image) => image.getAttribute('src')));
if (missing.length) throw new Error(`Missing images: ${missing.join(', ')}`);
const names = ['01_Studi_Kasus', '02_Proses_Operasional', '03_Arsitektur_Sistem', '04_Dashboard_Regional', '05_Detail_Drop_Point', '06_Automasi_dan_AI'];
for (let index = 0; index < names.length; index++) {
  const target = path.join(root, `PORTOFOLIO_${names[index]}.png`);
  await page.locator(`#slide-0${index + 1}`).screenshot({ path: target });
  console.log(target);
}
await browser.close();

