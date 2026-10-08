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

  cat.applySettings(settings);
  if (held.thumb) cat.hold(held.thumb);

  // MARK: - События из Rust

  await listen('tap', (e) => cat.tap(e.payload.paw));
  await listen('tick', (e) => cat.tick(e.payload.cpm));
  await listen('say', (e) => cat.say(e.payload.text, e.payload.seconds));
  await listen('pet', () => cat.pet());
  await listen('feed', () => cat.feed());
  await listen('held-changed', (e) => {
    held = e.payload;
    if (held.thumb) cat.hold(held.thumb); else cat.putAway();
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
    if (down.onHeld && held.path) {
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

  // Забрать картинку: тянем из лапок наружу как файл.
  async function dragHeldOut() {
    const path = held.path;
    const icon = held.thumb;
    down = null;
    try {
      await invoke('put_away', { message: null });
      await T.drag.startDrag({ item: [path], icon }, (event) => {
        const result = (event && (event.result || event.payload?.result)) || '';
        setTimeout(() => {
          if (held.path === path) return; // вернули котику
          cat.say(String(result).toLowerCase() === 'dropped' ? 'забирай, твоё' : 'ладно, отпустил');
        }, 100);
      });
    } catch (err) {
      console.error('drag out failed', err);
      await invoke('give_shot', { path });
    }
  }

  // Бросили картинку на котика.
  await webview.onDragDropEvent((e) => {
    if (e.payload.type === 'drop' && e.payload.paths?.length) {
      invoke('import_files', { paths: e.payload.paths });
    }
  });

  // MARK: - Обновления

  async function checkUpdatesQuietly() {
    if (!settings.checkUpdates) return;
    try {
      const update = await T.updater.check();
      if (update) {
        cat.say(`есть обновление v${update.version} — в меню`, 6);
        invoke('set_update_text', { text: `⬆️ Обновить до v${update.version}…` });
      }
    } catch (err) {
      console.warn('update check failed', err);
    }
  }
  setTimeout(checkUpdatesQuietly, 20000);
  setInterval(checkUpdatesQuietly, 6 * 60 * 60 * 1000);
})();
