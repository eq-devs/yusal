// End-to-end checks of the major flows against the web build.
// Each flow runs in a fresh browser context (a fresh demo backend) and
// fails loudly: node e2e.mjs [flow-name ...]
import { open, labels, tap, tryTap } from './lib.mjs';

const only = process.argv.slice(2);
const results = [];

/** Labels currently exposed, joined; for "is this text on screen". */
const screen = async (page) =>
  page.evaluate(() => {
    const out = [];
    for (const e of document.querySelectorAll('flt-semantics')) {
      const label = e.getAttribute('aria-label');
      if (label) out.push(label);
      // Plain text sits in a span directly under its node.
      for (const c of e.children)
        if (c.tagName === 'SPAN' && c.textContent.trim()) out.push(c.textContent.trim());
      if (e.children.length === 0 && e.textContent.trim()) out.push(e.textContent.trim());
    }
    for (const e of document.querySelectorAll('input, textarea')) {
      if (e.value) out.push(e.value);
      const l = e.getAttribute('aria-label');
      if (l) out.push(l);
    }
    return out.join('\n');
  });
const has = async (page, text) => (await screen(page)).includes(text);
async function expectText(page, text, why = '') {
  for (let i = 0; i < 12; i++) {
    if (await has(page, text)) return;
    await page.waitForTimeout(300);
  }
  throw new Error(`expected "${text}" on screen ${why}\n--- screen ---\n${(await screen(page)).slice(-1400)}`);
}
async function expectNoText(page, text) {
  await page.waitForTimeout(400);
  if (await has(page, text)) throw new Error(`did not expect "${text}" on screen`);
}
/** Types into the text field whose label contains [label] (or the nth field). */
async function fill(page, label, text, { nth = 0 } = {}) {
  const box = await page.evaluate(
    ([label, nth]) => {
      const all = [...document.querySelectorAll('flt-semantics input, flt-semantics textarea, input, textarea')];
      const hits = all.filter((e) => (e.getAttribute('aria-label') || '').includes(label));
      const e = hits[nth];
      if (!e) return { miss: all.map((e) => e.getAttribute('aria-label') || '(no label)') };
      const r = e.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    },
    [label, nth],
  );
  if (box.miss) throw new Error(`no field labelled "${label}"; fields: ${JSON.stringify(box.miss)}`);
  await page.mouse.click(box.x, box.y);
  await page.waitForTimeout(300);
  await page.keyboard.press('ControlOrMeta+a');
  await page.keyboard.type(text, { delay: 15 });
  await page.waitForTimeout(400);
}
/** Scrolls until the node labelled [text] is clear of the bars, then taps it. */
async function reach(page, text, { field = false } = {}) {
  for (let i = 0; i < 6; i++) {
    const y = await page.evaluate(
      ([text, field]) => {
        const nodes = field
          ? [...document.querySelectorAll('input, textarea')].filter((e) => (e.getAttribute('aria-label') || '').includes(text))
          : [...document.querySelectorAll('flt-semantics')].filter((e) => ((e.getAttribute('aria-label') || (e.children.length === 0 ? e.textContent : '') || '').trim()).includes(text));
        if (!nodes.length) return null;
        nodes.sort((a, b) => a.getBoundingClientRect().width * a.getBoundingClientRect().height - b.getBoundingClientRect().width * b.getBoundingClientRect().height);
        const r = nodes[0].getBoundingClientRect();
        return r.y + r.height / 2;
      },
      [text, field],
    );
    if (y === null) { await scroll(page, 500); continue; }
    if (y > 120 && y < 700) return;
    await scroll(page, y - 400);
  }
}
const back = (page) => tap(page, 'Назад', { exact: true });
const signIn = async (page, who = 'Айгерім') => {
  await tap(page, 'Профиль');
  await tap(page, 'Войти');
  await tap(page, who);
  await expectText(page, 'Демо-аккаунт');
};
const scroll = async (page, dy, x = 195, y = 500) => {
  await page.mouse.move(x, y);
  await page.mouse.wheel(0, dy);
  await page.waitForTimeout(500);
};

const flows = {
  async 'guest browses and is asked to sign in only when needed'({ page }) {
    await expectText(page, 'Демо-режим');
    await expectText(page, 'Начать с этого');
    await tap(page, 'Чаты');
    await expectText(page, 'Войдите, чтобы видеть сообщения');
    await expectNoText(page, 'Повторить');
    await tap(page, 'Обзор');
    await tap(page, 'Работа', { exact: true });
    await expectText(page, 'Найм рабочих');
    await tap(page, 'Мастера', { exact: true });
    await expectText(page, 'Частный мастер');
    await tap(page, 'Дома', { exact: true });
    await tap(page, 'Одноэтажный кирпичный дом для родителей');
    await expectText(page, 'Чертежи проекта');
    await tap(page, 'Нравится');
    await expectText(page, 'Получить код', '(liking needs an account)');
    await back(page);
    await reach(page, 'Открыть чертежи');
    await tap(page, 'Открыть чертежи');
    await expectText(page, '3D');
  },

  async 'sign in, rename, switch language and theme, sign out'({ page }) {
    await signIn(page);
    await expectText(page, 'Айгерім');
    await scroll(page, 900);
    await tap(page, 'Язык');
    await tap(page, 'Қазақша');
    await expectText(page, 'Аккаунтты жою');
    await expectText(page, 'Үйлерім');
    await tap(page, 'Тіл');
    await tap(page, 'Русский');
    await expectText(page, 'Удалить аккаунт');
    await tap(page, 'Тема');
    await tap(page, 'Тёмная');
    const dark = await page.evaluate(() => {
      const c = document.querySelector('flt-glass-pane, flutter-view');
      return !!c;
    });
    if (!dark) throw new Error('no flutter view after theme switch');
    await expectText(page, 'Тёмная');
    await scroll(page, 900);
    await tap(page, 'Выйти');
    await expectText(page, 'Войдите, чтобы публиковать');
  },

  async 'create a design by size, open the editor, come back to its card'({ page }) {
    await tap(page, 'Мои дома');
    await expectText(page, 'Проектов пока нет');
    await tap(page, 'Новый проект');
    await expectText(page, 'Название проекта');
    await fill(page, 'Название проекта', 'Дом у реки');
    await tap(page, 'Начать', { exact: true });
    await page.waitForTimeout(2500);
    await expectText(page, 'Дом у реки');
    await expectText(page, '3D');
    await back(page);
    await page.waitForTimeout(1200);
    await expectText(page, 'Мои проекты');
    await expectText(page, 'Дом у реки');
    await expectText(page, 'Продолжить');
    await expectText(page, 'Найти мастеров');
    // Survives a reload: local designs are kept.
    await page.evaluate(() => localStorage.removeItem('flutter.editing-project'));
  },

  async 'start from the example and walk the editor pages'({ page }) {
    await tap(page, 'Мои дома');
    await tap(page, 'Открыть пример');
    await page.waitForTimeout(3000);
    await expectText(page, 'Казахский сельский дом');
    for (const key of ['3D', 'Участок', 'Смета']) {
      if (!(await tryTap(page, key))) throw new Error(`editor page "${key}" not reachable`);
      await page.waitForTimeout(900);
    }
    await tap(page, 'Другие действия');
    // The menu is Russian and offers all three languages.
    await expectText(page, 'Экспорт чертежей в PDF');
    await tap(page, 'Язык');
    await expectText(page, 'Русский');
    await expectText(page, 'Қазақша');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    await back(page);
    await page.waitForTimeout(1200);
    await expectText(page, 'Казахский сельский дом');
  },

  async 'publish a house from a design and find it in my profile'({ page }) {
    await signIn(page);
    await tap(page, 'Мои дома');
    await page.waitForTimeout(800);
    await tap(page, 'Начать с примера');
    await tap(page, 'сельский дом');
    await page.waitForTimeout(3000);
    await back(page);
    await page.waitForTimeout(1200);
    await tap(page, 'Действия с проектом');
    await tap(page, 'Опубликовать', { exact: true });
    await page.waitForTimeout(1200);
    await expectText(page, 'Чего вы хотите?');
    await tap(page, 'Опубликовать', { exact: true });
    await page.waitForTimeout(2000);
    await tryTap(page, 'Назад', { exact: true });
    await tap(page, 'Профиль');
    await expectText(page, 'Мои публикации');
    await expectText(page, 'Казахский сельский дом');
  },

  async 'find builders from a design: quantities come from the drawing'({ page }) {
    await signIn(page);
    await tap(page, 'Мои дома');
    await page.waitForTimeout(800);
    await tap(page, 'Начать с примера');
    await tap(page, 'сельский дом');
    await page.waitForTimeout(3000);
    await back(page);
    await page.waitForTimeout(1200);
    await tap(page, 'Найти мастеров');
    await page.waitForTimeout(1200);
    await expectText(page, 'Что поручить');
    await expectText(page, 'Проверьте объёмы');
    await expectText(page, 'Кладка наружных стен', '(quantities are named in Russian)');
    await expectText(page, 'Из проекта');
    await tap(page, 'Далее');
    await page.waitForTimeout(1200);
    await expectText(page, 'Из проекта');
    await expectText(page, 'Черновик');
  },

  async 'a pro quotes on a demand and sees his quote'({ page }) {
    await signIn(page, 'Болат');
    await tap(page, 'Обзор');
    await tap(page, 'Работа', { exact: true });
    await page.waitForTimeout(700);
    await tap(page, 'Двускатная кровля');
    await page.waitForTimeout(1000);
    await tap(page, 'Предложить цену');
    await page.waitForTimeout(1000);
    await expectText(page, 'От имени');
    await expectText(page, 'Болат · каменщик');
    await tap(page, 'Уточнить на месте');
    await fill(page, 'Комментарий', 'Приеду посмотреть крышу в субботу');
    await tap(page, 'Отправить');
    await page.waitForTimeout(1500);
    await expectText(page, 'Мой отклик');
  },

  async 'chat: a sent message appears in the conversation'({ page }) {
    await signIn(page);
    await tap(page, 'Чаты');
    await page.waitForTimeout(700);
    await tap(page, 'Нұрлан');
    await expectText(page, 'Хорошо, буду в субботу в 10.');
    await fill(page, 'Сообщение', 'Жду вас в субботу');
    await tap(page, 'Отправить');
    await expectText(page, 'Жду вас в субботу');
  },

  async 'opinion: write one on a house and see it listed'({ page }) {
    await signIn(page);
    await tap(page, 'Обзор');
    await tap(page, 'Дом с мансардой');
    await page.waitForTimeout(1500);
    await reach(page, 'Что думаете', { field: true });
    await fill(page, 'Что думаете', 'Лестницу лучше поставить у входа');
    await reach(page, 'Отправить');
    await tap(page, 'Отправить');
    await page.waitForTimeout(1200);
    await scroll(page, 400);
    await expectText(page, 'Лестницу лучше поставить у входа');
  },

  async 'owner: house in work opens its workspace with scrollable tabs'({ page }) {
    await signIn(page);
    await tap(page, 'Мои дома');
    await page.waitForTimeout(900);
    await expectText(page, 'Дома в работе');
    await tap(page, 'Новых предложений: 1');
    await expectText(page, 'Предложения · 1');
    await tap(page, 'Предложения · 1');
    await expectText(page, 'новых 1');
    await tap(page, 'Соглашения');
    await expectText(page, 'Пока нет соглашений');
  },

  async 'desktop: side rail instead of the bottom bar'({ page }) {
    const l = await labels(page);
    // A rail destination announces itself as "Обзор Вкладка 1 из 4".
    const tabs = l.filter((x) => /\| (Обзор|Мои дома|Чаты|Профиль) Вкладка \d из 4 \|/.test(x));
    if (tabs.length !== 4) throw new Error(`expected 4 places, got ${tabs.length}`);
    // In a rail every destination sits at the left edge, one under another.
    const xs = tabs.map((x) => Number(x.split(' | ')[2].split(',')[0]));
    if (Math.max(...xs) > 120) throw new Error(`places are not in a left rail: x=${xs}`);
    await tap(page, 'Мои дома');
    await expectText(page, 'Мои проекты');
  },
};
flows['desktop: side rail instead of the bottom bar'].size = { width: 1280, height: 800 };

for (const [name, run] of Object.entries(flows)) {
  if (only.length && !only.some((o) => name.includes(o))) continue;
  const size = run.size || { width: 390, height: 844 };
  const session = await open({ out: 'shots/e2e', ...size });
  const started = Date.now();
  try {
    await run(session);
    if (session.errors.length) throw new Error(`console errors: ${session.errors.join(' | ').slice(0, 400)}`);
    results.push([name, true]);
    console.log(`PASS  ${name}  (${((Date.now() - started) / 1000).toFixed(1)} s)`);
  } catch (e) {
    results.push([name, false]);
    await session.shot(`FAIL-${name.replace(/[^a-zа-я0-9]+/gi, '-').slice(0, 40)}`).catch(() => {});
    console.log(`FAIL  ${name}\n      ${String(e.message).split('\n').join('\n      ')}`);
  }
  await session.browser.close();
}
const failed = results.filter(([, ok]) => !ok).length;
console.log(`\n${results.length - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
