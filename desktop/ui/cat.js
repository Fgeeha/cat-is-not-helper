// Окно котика: связывает CatRenderer с Tauri — события тапов, мышь,
// перетаскивание окна, drag & drop картинок в лапки и из лапок.
(async function () {
  const T = window.__TAURI__;
  const { invoke } = T.core;
  const { listen } = T.event;
  const win = T.window.getCurrentWindow();
  const webview = T.webview.getCurrentWebview();

  const stage = document.getElementById('stage');
  const cat = new CatRenderer(stage, {
    onMoodChange: (mood, info) => invoke('set_mood', { text: `${info.emoji} ${info.title}` }),
  });

  let settings = await invoke('get_settings');
  let held = await invoke('get_held');
  let needsAccess = false;

  function updateScaleVar() {
    document.documentElement.style.setProperty('--k', String(window.innerWidth / 260));
  }
  updateScaleVar();
  window.addEventListener('resize', updateScaleVar);

  const platformInfo = await invoke('platform_info');
  const isLinux = platformInfo.os === 'linux';

  function showHeld(h) {
    if (h.top) cat.hold(h.top.thumb, { name: h.top.name, count: h.count }); else cat.putAway();
  }

  cat.applySettings(settings);
  showHeld(held);

  // MARK: - События из Rust

  await listen('tap', (e) => cat.tap(e.payload.paw));
  await listen('tick', (e) => cat.tick(e.payload.cpm));
  await listen('say', (e) => cat.say(e.payload.text, e.payload.seconds));
  await listen('pet', () => cat.pet());
  await listen('feed', () => cat.feed());
  await listen('held-changed', (e) => {
    held = e.payload;
    showHeld(held);
  });
  await listen('settings-changed', (e) => {
    settings = e.payload;
    cat.applySettings(settings);
  });
  await listen('access-changed', (e) => {
    needsAccess = !e.payload;
    if (e.payload) cat.say('вижу клавиатуру! 🎉', 4);
  });

  const access = await invoke('access_status');
  needsAccess = !access.trusted;
  if (needsAccess) {
    cat.say(access.hint ? 'дай доступ к клавиатуре 🙏 (меню)' : 'привет!', 8);
    invoke('request_access');
  } else {
    cat.say('привет! я не помогаю, я тапаю', 4);
  }

  // MARK: - Мышь

  let down = null;
  let dragging = false;

  stage.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    down = { x: e.clientX, y: e.clientY, onHeld: cat.hitHeld(e.clientX, e.clientY) };
    dragging = false;
  });

  stage.addEventListener('mousemove', async (e) => {
    if (!down || dragging) return;
    if (Math.hypot(e.clientX - down.x, e.clientY - down.y) <= 3) return;
    dragging = true;
    if (down.onHeld && held.top) {
      await dragHeldOut();
    } else {
      await win.startDragging();
    }
  });

  window.addEventListener('mouseup', () => {
    const wasDragging = dragging;
    const hadDown = !!down;
    down = null;
    dragging = false;
    if (hadDown && !wasDragging) {
      cat.pet();
      invoke('record_pet');
    }
  });

  stage.addEventListener('dblclick', (e) => {
    e.preventDefault();
    invoke('open_held');
  });

  stage.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    invoke('show_cat_menu');
  });

  // Забрать: тянем из лапок наружу как файл. На Linux перетаскивание из окна
  // в другие приложения ненадёжно, поэтому там же кладём в буфер обмена.
  async function dragHeldOut() {
    const path = held.top.path;
    const icon = held.top.thumb;
    down = null;
    if (isLinux) {
      await invoke('copy_held'); // X11: список файлов + PNG + путь, скажет «в буфере»
    }
    try {
      await invoke('put_away', { message: null, path });
      await T.drag.startDrag({ item: [path], icon: icon || path }, (event) => {
        const result = (event && (event.result || event.payload?.result)) || '';
        setTimeout(() => {
          if (held.paths.includes(path)) return; // вернули котику
          if (isLinux) return; // сообщение про буфер уже показано
          cat.say(String(result).toLowerCase() === 'dropped' ? 'забирай, твоё' : 'ладно, отпустил');
        }, 100);
      });
    } catch (err) {
      console.error('drag out failed', err);
      if (!isLinux) {
        await invoke('give_shot', { path }); // вернуть в стопку
        await invoke('copy_held');
      }
    }
  }

  // Бросили картинку на котика.
  await webview.onDragDropEvent((e) => {
    if (e.payload.type === 'drop' && e.payload.paths?.length) {
      invoke('import_files', { paths: e.payload.paths });
    }
  });

  // MARK: - Обновления

  const U = window.CatUpdates;

  async function checkUpdates(manual) {
    try {
      const result = await U.check();
      if (result.none) {
        if (manual) cat.say(result.noReleases ? 'релизов пока нет' : 'у меня последняя версия', 3);
        return;
      }
      cat.say(result.installable
        ? `есть v${result.version} — обновить в меню`
        : `есть v${result.version} — скачать в меню`, 6);
    } catch (err) {
      console.warn('update check failed', err);
      if (manual) cat.say('не смог проверить: нет сети?', 3);
    }
  }

  // Пункт меню «Проверить обновления» / «Обновить до vX» / «Скачать vX на GitHub».
  await listen('update-action', async () => {
    if (!U.state.available) { await checkUpdates(true); return; }
    if (!U.state.available.installable) { await U.install(); return; }
    const v = U.state.available.version;
    cat.say(`качаю v${v}…`, 300);
    try {
      await U.install((p, stage) => cat.say(stage === 'install' ? `ставлю v${v}, сейчас перезапущусь…` : `качаю v${v}… ${Math.round(p * 100)}%`, 300));
    } catch (err) {
      console.error('update failed', err);
      cat.say(`не вышло: ${String(err).slice(0, 60)}`, 6);
      invoke('set_update_text', { text: `⬆️ Скачать v${v} на GitHub` });
      U.state.available.installable = false;
    }
  });

  setTimeout(() => { if (settings.checkUpdates) checkUpdates(false); }, 20000);
  setInterval(() => { if (settings.checkUpdates) checkUpdates(false); }, 6 * 60 * 60 * 1000);
})();
