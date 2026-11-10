// Shared helpers for driving the Flutter web build with Playwright.
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';

export const BASE = process.env.BASE || 'http://localhost:8765';

export async function open({
  width = 390,
  height = 844,
  lang = 'ru',
  theme = 'day',
  route = '',
  textScale,
  out = 'shots',
} = {}) {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const ctx = await browser.newContext({
    viewport: { width, height },
    deviceScaleFactor: 2,
    locale: 'ru-RU',
    hasTouch: width < 700,
    colorScheme: theme === 'night' ? 'dark' : 'light',
  });
  await ctx.addInitScript(
    ([lang, theme]) => {
      try {
        localStorage.setItem('flutter.house-lang', JSON.stringify(lang));
        localStorage.setItem('flutter.house-theme', JSON.stringify(theme));
      } catch (_) {}
    },
    [lang, theme],
  );
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text());
  });
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(`${BASE}/${route}`);
  await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 60000 });
  await page.waitForTimeout(2500);
  await semantics(page);
  let n = 0;
  const shot = async (name) => {
    await page.waitForTimeout(700);
    const file = path.join(out, `${String(++n).padStart(2, '0')}-${name}.png`);
    await page.screenshot({ path: file });
    return file;
  };
  return { browser, ctx, page, shot, errors };
}

export async function semantics(page) {
  await page.evaluate(() => {
    const el = document.querySelector('flt-semantics-placeholder');
    if (el) el.click();
  });
  await page.waitForTimeout(600);
}

/** Text labels of everything the accessibility tree exposes right now. */
export async function labels(page) {
  return page.evaluate(() =>
    [...document.querySelectorAll('flt-semantics')]
      .map((e) => {
        const role = e.getAttribute('role') || '';
        const label =
          e.getAttribute('aria-label') ||
          (e.children.length === 0 ? e.textContent : '') ||
          '';
        const r = e.getBoundingClientRect();
        return label.trim()
          ? `${role || '-'} | ${label.trim().replace(/\s+/g, ' ').slice(0, 90)} | ${Math.round(r.x)},${Math.round(r.y)} ${Math.round(r.width)}x${Math.round(r.height)}`
          : null;
      })
      .filter(Boolean),
  );
}

/** Taps the first semantics node whose label contains [text]. */
export async function tap(page, text, { exact = false, nth = 0 } = {}) {
  const box = await page.evaluate(
    ([text, exact, nth]) => {
      const hits = [...document.querySelectorAll('flt-semantics')].filter((e) => {
        const label =
          e.getAttribute('aria-label') ||
          (e.children.length === 0 ? e.textContent : '') ||
          '';
        const l = label.trim();
        return exact ? l === text : l.includes(text);
      });
      // Prefer the smallest matching node: the actual control.
      hits.sort(
        (a, b) =>
          a.getBoundingClientRect().width * a.getBoundingClientRect().height -
          b.getBoundingClientRect().width * b.getBoundingClientRect().height,
      );
      const e = hits[nth];
      if (!e) return null;
      const r = e.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    },
    [text, exact, nth],
  );
  if (!box) throw new Error(`No node labelled "${text}"`);
  await page.mouse.click(box.x, box.y);
  await page.waitForTimeout(900);
}

export async function tryTap(page, text, opts) {
  try {
    await tap(page, text, opts);
    return true;
  } catch (_) {
    return false;
  }
}
