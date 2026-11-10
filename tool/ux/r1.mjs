// Review run: the screens changed in round 1.
import { open, tap, tryTap, labels } from './lib.mjs';
const W = Number(process.env.W || 390), H = Number(process.env.H || 844);
const theme = process.env.THEME || 'day';
const { browser, page, shot, errors } = await open({ out: process.env.OUT || `shots/r1-${W}-${theme}`, width: W, height: H, theme });
const step = async (name, fn) => { try { await fn(); } catch (e) { console.log(`!! ${name}: ${e.message}`); await shot(`FAIL-${name}`); } };
const scroll = async (dy) => { await page.mouse.move(W / 2, 500); await page.mouse.wheel(0, dy); await page.waitForTimeout(600); };
const back = async () => { if (!(await tryTap(page, 'Назад', { exact: true }))) console.log('!! no back'); };
await step('guest', async () => {
  await shot('guest-explore');
  await tap(page, 'Мои дома'); await page.waitForTimeout(600); await shot('guest-houses');
  await tap(page, 'Чаты'); await shot('guest-inbox');
  await tap(page, 'Демо-режим'); await shot('demo-dialog'); await tap(page, 'Понятно');
  await tap(page, 'Профиль'); await shot('guest-me');
});
await step('login', async () => { await tap(page, 'Войти'); await shot('login'); await tap(page, 'Айгерім'); await shot('me'); await scroll(700); await shot('me-2'); });
await step('houses', async () => {
  await tap(page, 'Мои дома'); await page.waitForTimeout(900); await shot('houses');
  await tap(page, 'Начать с примера'); await shot('template-sheet');
  await tap(page, 'сельский дом'); await page.waitForTimeout(2500); await shot('editor');
  await back(); await page.waitForTimeout(1200); await shot('houses-with-design');
  await scroll(500); await shot('houses-with-design-2');
  await tap(page, 'Действия с проектом'); await shot('design-menu'); await page.keyboard.press('Escape'); await page.waitForTimeout(400);
  await scroll(-2000);
  await tap(page, 'Новый проект'); await shot('new-design-dialog'); await tap(page, 'Отмена');
  console.log((await labels(page)).join('\n'));
});
await step('workspace', async () => { await tap(page, 'Новых предложений: 1'); await shot('workspace'); await back(); });
await step('work', async () => {
  await tap(page, 'Обзор'); await shot('explore');
  await tap(page, 'Работа', { exact: true }); await shot('work'); await scroll(600); await shot('work-2'); await scroll(-2000);
  await page.mouse.click(W < 700 ? W / 2 : 400, 420); await page.waitForTimeout(1200); await shot('demand'); await back();
});
await step('post', async () => {
  await tap(page, 'Дома', { exact: true }); await page.mouse.click(W < 700 ? W / 2 : 400, 560); await page.waitForTimeout(1500); await shot('post');
  await scroll(1500); await shot('post-form'); await back();
});
await step('inbox', async () => { await tap(page, 'Чаты'); await page.waitForTimeout(600); await shot('inbox'); await tap(page, 'Нұрлан'); await shot('chat'); });
console.log('errors', errors);
await browser.close();
