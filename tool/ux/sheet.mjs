// Contact sheet: node sheet.mjs <dir> [columns] [cellWidth] → <dir>.sheet-N.png
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';

const dir = path.resolve(process.argv[2]);
const cols = Number(process.argv[3] || 4);
const cell = Number(process.argv[4] || 390);
const files = fs.readdirSync(dir).filter((f) => f.endsWith('.png')).sort();
const perSheet = cols * 2;
const browser = await chromium.launch({ channel: 'chrome', headless: true });
for (let s = 0; s * perSheet < files.length; s++) {
  const part = files.slice(s * perSheet, (s + 1) * perSheet);
  const html = `<body style="margin:0;background:#888;font:12px sans-serif">
  <div style="display:grid;grid-template-columns:repeat(${cols},${cell}px);gap:10px;padding:10px">
  ${part
    .map(
      (f) => `<div><div style="color:#fff;padding:2px 0">${f}</div>
      <img src="data:image/png;base64,${fs.readFileSync(path.join(dir, f)).toString('base64')}" style="width:${cell}px;display:block"></div>`,
    )
    .join('')}</div></body>`;
  const page = await browser.newPage({
    viewport: { width: cols * (cell + 10) + 10, height: 800 },
  });
  await page.setContent(html, { waitUntil: 'load' });
  const out = `${dir}.sheet-${s + 1}.png`;
  await page.screenshot({ path: out, fullPage: true });
  console.log(out);
  await page.close();
}
await browser.close();
