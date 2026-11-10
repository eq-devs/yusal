// Review run 2: publishing flows, a pro page, applying as a pro, a cooperation.
import { open, tap, tryTap, labels } from './lib.mjs';
const W = Number(process.env.W || 390), H = Number(process.env.H || 844);
const theme = process.env.THEME || 'day';
const { browser, page, shot, errors } = await open({ out: process.env.OUT || `shots/r2-${W}-${theme}`, width: W, height: H, theme });
const step = async (name, fn) => { try { await fn(); } catch (e) { console.log(`!! ${name}: ${e.message}`); await shot(`FAIL-${name}`); } };
const scroll = async (dy) => { await page.mouse.move(W / 2, 500); await page.mouse.wheel(0, dy); await page.waitForTimeout(600); };
const back = async () => { if (!(await tryTap(page, 'Назад', { exact: true }))) console.log('!! no back'); };
await tap(page, 'Профиль'); await tap(page, 'Войти'); await tap(page, 'Айгерім');
await step('design', async () => {
  await tap(page, 'Мои дома'); await page.waitForTimeout(900);
  await tap(page, 'Начать с примера'); await tap(page, 'сельский дом'); await page.waitForTimeout(2500);
  await tap(page, 'Другие действия'); await shot('editor-menu'); await page.keyboard.press('Escape'); await page.waitForTimeout(300);
  await back(); await page.waitForTimeout(1200);
});
await step('publish-post', async () => {
  await tap(page, 'Действия с проектом'); await tap(page, 'Опубликовать'); await page.waitForTimeout(1200);
  await shot('publish-post'); await scroll(600); await shot('publish-post-2'); await scroll(600); await shot('publish-post-3');
  await back(); await page.waitForTimeout(600); await shot('publish-post-leave'); await tryTap(page, 'Выйти'); await tryTap(page, 'Не сохранять'); await page.waitForTimeout(500);
  console.log((await labels(page)).slice(0, 12).join('\n'));
});
await step('from-design', async () => {
  await tap(page, 'Найти мастеров'); await page.waitForTimeout(1200); await shot('from-design'); await scroll(700); await shot('from-design-2');
  await tap(page, 'Далее'); await page.waitForTimeout(1200); await shot('publish-from-design'); await scroll(700); await shot('publish-from-design-2');
  await back(); await tryTap(page, 'Выйти'); await back();
});
await step('publish-demand', async () => {
  await tap(page, 'Обзор'); await tap(page, 'Создать'); await shot('create-sheet'); await tap(page, 'Найти мастера'); await page.waitForTimeout(1200);
  await shot('demand-step-1'); await tap(page, 'Найм рабочих'); await tap(page, 'Далее'); await page.waitForTimeout(800);
  await shot('demand-step-2'); await scroll(600); await shot('demand-step-2b');
  await tap(page, 'Назад', { exact: true, nth: 0 }); await page.waitForTimeout(500);
  await tryTap(page, 'Отменить и выйти'); await page.waitForTimeout(500);
  await tryTap(page, 'Назад', { exact: true }); await page.waitForTimeout(500); await tryTap(page, 'Отменить и выйти'); await page.waitForTimeout(600);
});
await step('pro', async () => {
  await tap(page, 'Обзор'); await tap(page, 'Мастера', { exact: true }); await page.waitForTimeout(600); await shot('people');
  await tap(page, 'Болат'); await page.waitForTimeout(1000); await shot('pro'); await scroll(600); await shot('pro-2'); await back();
});
await step('demand-apply', async () => {
  await tap(page, 'Работа', { exact: true }); await page.waitForTimeout(600);
  await tap(page, 'Двускатная кровля'); await page.waitForTimeout(1000); await shot('demand'); await scroll(700); await shot('demand-2');
  await tap(page, 'Предложить цену'); await page.waitForTimeout(1000); await shot('apply'); await scroll(600); await shot('apply-2');
});
console.log('errors', errors);
await browser.close();
