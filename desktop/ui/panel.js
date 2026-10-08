// Панель: статистика, галерея, настройки с живым превью котика.
(async function () {
  const T = window.__TAURI__;
  const { invoke } = T.core;
  const { listen } = T.event;
  const $ = (id) => document.getElementById(id);
  const { FURS, EYES, KEYBOARDS, ACCESSORIES, SIZES, MOODS } = window.CatCatalog;
  const fmt = (n) => Number(n || 0).toLocaleString('ru-RU');

  // MARK: - Вкладки

  const tabs = [...document.querySelectorAll('nav.tabs button')];
  function showTab(name) {
    tabs.forEach((b) => b.classList.toggle('active', b.dataset.tab === name));
    document.querySelectorAll('section.tab').forEach((s) => s.classList.toggle('active', s.id === `tab-${name}`));
    if (name === 'stats') refreshStats();
    if (name === 'gallery') refreshGallery();
    if (name === 'settings') refreshAccess();
  }
  tabs.forEach((b) => b.addEventListener('click', () => showTab(b.dataset.tab)));
  await listen('panel-tab', (e) => showTab(e.payload));

  // MARK: - Превью котика

  const preview = new CatRenderer($('preview'), { fixedOpacity: true });
  let settings = await invoke('get_settings');
  let held = await invoke('get_held');
  preview.applySettings(settings);
  const showHeld = (h) => { if (h.path) preview.hold(h.thumb, { name: h.name }); else preview.putAway(); };
  showHeld(held);

  await listen('tap', (e) => preview.tap(e.payload.paw));
  await listen('tick', (e) => { preview.tick(e.payload.cpm); if ($('tab-stats').classList.contains('active')) refreshStats(); });
  await listen('pet', () => preview.pet());
  await listen('feed', () => preview.feed());
  await listen('held-changed', (e) => {
    held = e.payload;
    showHeld(held);
    if ($('tab-gallery').classList.contains('active')) refreshGallery();
  });
  await listen('settings-changed', (e) => { settings = e.payload; preview.applySettings(settings); fillSettings(); });
  await listen('access-changed', refreshAccess);

  $('btn-pet').addEventListener('click', () => invoke('pet'));
  $('btn-feed').addEventListener('click', () => invoke('feed'));

  // MARK: - Статистика

  function card(label, value, hint) {
    return `<div class="card stat"><div class="label">${label}</div><div class="value">${value}</div><div class="hint">${hint}</div></div>`;
  }

  function barChart(svg, points, { labelEvery = 1, height }) {
    const width = svg.clientWidth || 600;
    const h = height || svg.clientHeight || 170;
    const padL = 34, padB = 18, padT = 8;
    const max = Math.max(1, ...points.map((p) => p.value));
    const n = points.length;
    const slot = (width - padL) / n;
    const barW = Math.max(2, slot * 0.6);
    let out = '';
    const ticks = 3;
    for (let t = 0; t <= ticks; t++) {
      const v = Math.round((max * t) / ticks);
      const y = padT + (h - padT - padB) * (1 - t / ticks);
      out += `<line x1="${padL}" x2="${width}" y1="${y}" y2="${y}" /><text x="${padL - 6}" y="${y + 3}" text-anchor="end">${v}</text>`;
    }
    points.forEach((p, i) => {
      const x = padL + i * slot + (slot - barW) / 2;
      const bh = ((h - padT - padB) * p.value) / max;
      const y = padT + (h - padT - padB) - bh;
      out += `<rect class="bar${p.today ? ' today' : ''}" x="${x}" y="${y}" width="${barW}" height="${bh}" rx="3"><title>${p.label}: ${fmt(p.value)}</title></rect>`;
      if (i % labelEvery === 0) out += `<text x="${x + barW / 2}" y="${h - 4}" text-anchor="middle">${p.label}</text>`;
    });
    svg.setAttribute('viewBox', `0 0 ${width} ${h}`);
    svg.innerHTML = out;
  }

  async function refreshStats() {
    const s = await invoke('stats_snapshot');
    $('since').textContent = s.firstLaunch ? `с ${s.firstLaunch}` : '';
    $('cards').innerHTML =
      card('Сегодня', fmt(s.todayKeys), 'тапов') +
      card('Сейчас', fmt(s.cpm), 'нажатий в минуту') +
      card('Всего', fmt(s.totalKeys), 'за всё время') +
      card('Рекорд скорости', fmt(s.bestCpm), 'в минуту') +
      card('Серия', fmt(s.streak), s.streak === 1 ? 'день подряд' : 'дней подряд') +
      card('Клики мышью', fmt(s.totalClicks), `сегодня: ${fmt(s.todayClicks)}`);
    barChart($('chart-days'), s.last14.map((d) => ({ label: d.label, value: d.keys, today: d.isToday })), { height: 170 });
    barChart($('chart-hours'), s.hourly.map((v, h) => ({ label: String(h).padStart(2, '0'), value: v })), { labelEvery: 3, height: 150 });
    $('best-day').textContent = s.bestDay
      ? `Лучший день: ${s.bestDay.label} — ${fmt(s.bestDay.keys)} тапов. В среднем за активный день: ${fmt(s.averagePerActiveDay)}.`
      : 'Котик ещё ничего не натапал.';
    const mood = MOODS[preview.state.mood];
    $('mood-line').textContent = `Настроение: ${mood.emoji} ${mood.title}`;
    const hp = Math.round(preview.state.happiness * 100);
    $('happy-bar').style.width = `${Math.max(3, hp)}%`;
    $('happy-text').textContent = `Счастье: ${hp}%`;
    $('cat-counts').innerHTML = `Погладили: ${fmt(s.pets)}<br>Покормили: ${fmt(s.feeds)}<br>Скриншотов дали: ${fmt(s.screenshots)}`;
    $('held-line').textContent = held.path ? `Сейчас держит: ${held.path.split(/[\\/]/).pop()}` : 'Сейчас лапки свободны — дай ему скриншот.';
  }

  // MARK: - Галерея

  const thumbCache = new Map();
  async function thumbFor(path) {
    if (!thumbCache.has(path)) thumbCache.set(path, invoke('thumbnail', { path, max: 400 }));
    return thumbCache.get(path);
  }

  async function refreshGallery() {
    const items = await invoke('list_shots');
    $('shots-count').textContent = `${items.length} шт.`;
    const root = $('gallery');
    if (!items.length) {
      root.innerHTML = `<div class="empty"><div class="big">🐾</div><b>Пока пусто</b><br>Нажми «Сделать скриншот» или перетащи любой файл прямо на котика — он подержит.</div>`;
      return;
    }
    root.innerHTML = '<div class="grid"></div>';
    const grid = root.firstElementChild;
    for (const item of items) {
      const isHeld = held.path === item.path;
      const cell = document.createElement('div');
      cell.className = `cell${isHeld ? ' held' : ''}`;
      const ext = (item.name.includes('.') ? item.name.split('.').pop() : '').toUpperCase().slice(0, 5) || 'ФАЙЛ';
      const placeholder = item.isImage ? '<span class="muted">…</span>' : `<div class="doc"><div class="doc-ext">${ext}</div><div class="muted">${(item.size / 1024).toFixed(0)} КБ</div></div>`;
      cell.innerHTML = `
        <div class="thumb">${placeholder}${isHeld ? '<span class="badge">🐾 у котика</span>' : ''}</div>
        <div class="name" title="${item.name}">${item.name}</div>
        <div class="row">
          <button class="plain small act-give">${isHeld ? 'Забрать у котика' : '🐾 Дать котику'}</button>
          <span class="grow"></span>
          <button class="plain small act-open" title="Открыть">↗</button>
          <button class="plain small act-reveal" title="Показать в папке">📁</button>
          <button class="plain small act-delete" title="Удалить">🗑</button>
        </div>`;
      cell.querySelector('.act-give').addEventListener('click', () =>
        isHeld ? invoke('put_away', { message: 'ладно, забирай' }) : invoke('give_shot', { path: item.path }));
      cell.querySelector('.act-open').addEventListener('click', () => invoke('open_shot', { path: item.path }));
      cell.querySelector('.act-reveal').addEventListener('click', () => invoke('reveal_shot', { path: item.path }));
      cell.querySelector('.act-delete').addEventListener('click', async () => {
        await invoke('delete_shot', { path: item.path });
        thumbCache.delete(item.path);
        refreshGallery();
      });
      cell.querySelector('.thumb').addEventListener('dblclick', () => invoke('open_shot', { path: item.path }));
      grid.appendChild(cell);
      if (!item.isImage) continue;
      thumbFor(item.path).then((data) => {
        if (!data) return;
        const box = cell.querySelector('.thumb');
        const img = document.createElement('img');
        img.alt = '';
        img.src = data;
        box.querySelector('.muted')?.remove();
        box.prepend(img);
      });
    }
  }
  $('btn-capture').addEventListener('click', () => invoke('start_capture'));
  $('btn-folder').addEventListener('click', () => invoke('open_shots_folder'));

  // MARK: - Настройки

  function fillSelect(id, entries, current) {
    const sel = $(id);
    sel.innerHTML = entries.map(([k, title]) => `<option value="${k}">${title}</option>`).join('');
    sel.value = current;
  }

  let filling = false;
  function fillSettings() {
    filling = true;
    fillSelect('s-fur', Object.entries(FURS).map(([k, v]) => [k, v.title]), settings.fur);
    fillSelect('s-eyes', Object.entries(EYES).map(([k, v]) => [k, v.title]), settings.eyeColor);
    fillSelect('s-accessory', Object.entries(ACCESSORIES), settings.accessory);
    fillSelect('s-keyboard', Object.entries(KEYBOARDS).map(([k, v]) => [k, v.title]), settings.keyboard);
    $('s-mirrored').checked = settings.mirrored;
    $('s-scale').value = settings.scale;
    $('s-scale-value').textContent = `${Math.round(settings.scale * 100)}%`;
    $('s-opacity').value = settings.opacity;
    $('s-opacity-value').textContent = `${Math.round(settings.opacity * 100)}%`;
    $('s-size-px').textContent = `Размер на экране: ${Math.round(260 * settings.scale)}×${Math.round(230 * settings.scale)} pt`;
    $('s-size-presets').innerHTML = SIZES.map((p) =>
      `<button data-scale="${p.scale}" class="${Math.abs(p.scale - settings.scale) < 0.01 ? 'active' : ''}">${p.title}</button>`).join('');
    $('s-size-presets').querySelectorAll('button').forEach((b) => b.addEventListener('click', () => save({ scale: Number(b.dataset.scale) })));
    $('s-bubbles').checked = settings.bubbles;
    $('s-top').checked = settings.alwaysOnTop;
    $('s-spaces').checked = settings.allSpaces;
    $('s-visible').checked = settings.catVisible;
    $('s-updates').checked = settings.checkUpdates;
    filling = false;
  }

  async function save(patch) {
    if (filling) return;
    settings = { ...settings, ...patch };
    await invoke('set_settings', { settings });
  }

  $('s-fur').addEventListener('change', (e) => save({ fur: e.target.value }));
  $('s-eyes').addEventListener('change', (e) => save({ eyeColor: e.target.value }));
  $('s-accessory').addEventListener('change', (e) => save({ accessory: e.target.value }));
  $('s-keyboard').addEventListener('change', (e) => save({ keyboard: e.target.value }));
  $('s-mirrored').addEventListener('change', (e) => save({ mirrored: e.target.checked }));
  $('s-scale').addEventListener('input', (e) => { $('s-scale-value').textContent = `${Math.round(e.target.value * 100)}%`; });
  $('s-scale').addEventListener('change', (e) => save({ scale: Number(e.target.value) }));
  $('s-opacity').addEventListener('input', (e) => { $('s-opacity-value').textContent = `${Math.round(e.target.value * 100)}%`; });
  $('s-opacity').addEventListener('change', (e) => save({ opacity: Number(e.target.value) }));
  $('s-bubbles').addEventListener('change', (e) => save({ bubbles: e.target.checked }));
  $('s-top').addEventListener('change', (e) => save({ alwaysOnTop: e.target.checked }));
  $('s-spaces').addEventListener('change', (e) => save({ allSpaces: e.target.checked }));
  $('s-visible').addEventListener('change', (e) => save({ catVisible: e.target.checked }));
  $('s-updates').addEventListener('change', (e) => save({ checkUpdates: e.target.checked }));

  // Автозапуск
  try {
    $('s-autostart').checked = await T.autostart.isEnabled();
  } catch (err) { console.warn(err); }
  $('s-autostart').addEventListener('change', async (e) => {
    try {
      if (e.target.checked) await T.autostart.enable(); else await T.autostart.disable();
    } catch (err) {
      $('s-autostart').checked = !e.target.checked;
      alert(`Не удалось изменить автозапуск: ${err}`);
    }
  });

  // Доступ к клавиатуре
  async function refreshAccess() {
    const a = await invoke('access_status');
    $('access-line').innerHTML = a.trusted
      ? '<span class="ok">✓ Доступ есть, котик видит нажатия</span>'
      : `<span class="warn">⚠ ${a.hint || 'Нет доступа к клавиатуре'}</span>`;
    $('btn-access').style.display = a.trusted ? 'none' : '';
  }
  $('btn-access').addEventListener('click', () => invoke('request_access'));

  // Обновления
  const platform = await invoke('platform');
  const appimage = platform === 'linux' ? await invoke('is_appimage') : false;
  const version = await invoke('app_version');
  $('version').textContent = `Текущая версия: ${version}`;
  if (platform === 'linux' && !appimage) {
    $('update-hint').textContent = 'Установлено из пакета (rpm/deb): новая версия скачается из GitHub Releases и поставится через пакетный менеджер, система спросит пароль администратора.';
  }

  const U = window.CatUpdates;
  async function checkUpdate() {
    const status = $('update-status');
    status.innerHTML = 'Проверяю…';
    try {
      const result = await U.check();
      if (result.none) {
        status.innerHTML = result.noReleases
          ? '<span class="muted">Релизов пока нет</span>'
          : '<span class="ok">У тебя последняя версия</span>';
        return;
      }
      if (!result.installable) {
        status.innerHTML = `<span class="warn">Доступна версия ${result.version}</span> <button class="primary small" id="btn-release">Открыть релиз</button>`;
        $('btn-release').addEventListener('click', () => U.openReleases());
        return;
      }
      const how = result.source === 'github'
        ? (U.state.info.package ? ` · через ${U.state.info.package === 'rpm' ? 'dnf' : 'apt'}, система спросит пароль` : ' · из GitHub Releases')
        : '';
      status.innerHTML = `<span class="warn">Доступна версия ${result.version}</span><span class="muted">${how}</span> <button class="primary small" id="btn-install">Обновить</button>`;
      $('btn-install').addEventListener('click', async () => {
        status.textContent = 'Скачиваю…';
        try {
          await U.install((p, stage) => { status.textContent = stage === 'install' ? 'Устанавливаю и перезапускаюсь…' : `Скачиваю… ${Math.round(p * 100)}%`; });
        } catch (err) {
          status.innerHTML = `<span class="bad">Не удалось обновиться: ${err}</span> <button class="plain small" id="btn-release">Открыть релиз</button>`;
          $('btn-release').addEventListener('click', () => U.openReleases());
        }
      });
    } catch (err) {
      status.innerHTML = `<span class="bad">Не удалось проверить: ${err}</span>`;
    }
  }
  $('btn-check').addEventListener('click', () => checkUpdate());
  $('btn-github').addEventListener('click', () => U.openReleases());

  fillSettings();
  showTab('stats');
})();
