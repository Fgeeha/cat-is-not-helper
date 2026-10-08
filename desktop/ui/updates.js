// Проверка обновлений, общая для окна котика и панели.
// Сначала штатный апдейтер Tauri (latest.json в релизе); если его нет или
// платформа не умеет самообновляться (rpm/deb) — сверяем версию через GitHub API
// и открываем страницу релиза.
(function () {
  const T = window.__TAURI__;
  const { invoke } = T.core;
  const REPO = 'Fgeeha/cat-is-not-helper';
  const RELEASES_URL = `https://github.com/${REPO}/releases/latest`;

  const state = { available: null, checking: false, platform: null, appimage: false, version: null };

  function isNewer(candidate, current) {
    const parts = (s) => String(s).replace(/^v/, '').split(/[.+-]/).slice(0, 3).map((p) => parseInt(p, 10) || 0);
    const a = parts(candidate), b = parts(current);
    for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] > b[i];
    return false;
  }

  async function init() {
    if (state.version) return;
    state.platform = await invoke('platform');
    state.appimage = state.platform === 'linux' ? await invoke('is_appimage') : false;
    state.version = await invoke('app_version');
  }

  function canSelfUpdate() {
    return !(state.platform === 'linux' && !state.appimage);
  }

  async function viaTauri() {
    try {
      const update = await T.updater.check();
      if (!update) return { none: true };
      return { version: update.version, update, installable: canSelfUpdate(), url: RELEASES_URL };
    } catch (err) {
      console.warn('updater.check:', err);
      return null; // нет latest.json или сети — пробуем GitHub API
    }
  }

  async function viaGitHub() {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { Accept: 'application/vnd.github+json' },
    });
    if (res.status === 404) return { none: true, noReleases: true };
    if (!res.ok) throw new Error(`GitHub ответил ${res.status}`);
    const json = await res.json();
    const version = String(json.tag_name || '').replace(/^v/, '');
    if (!version || !isNewer(version, state.version)) return { none: true };
    return { version, update: null, installable: false, url: json.html_url || RELEASES_URL };
  }

  function menuText() {
    if (!state.available) return 'Проверить обновления';
    return state.available.installable
      ? `⬆️ Обновить до v${state.available.version}…`
      : `⬆️ Скачать v${state.available.version} на GitHub`;
  }

  /// Возвращает { none } | { version, installable, url, update } и обновляет пункт меню.
  async function check() {
    await init();
    if (state.checking) return state.available || { none: true };
    state.checking = true;
    try {
      let result = await viaTauri();
      if (!result) result = await viaGitHub();
      state.available = result.none ? null : result;
      invoke('set_update_text', { text: menuText() });
      return result;
    } finally {
      state.checking = false;
    }
  }

  /// Установить, если можно; иначе открыть страницу релиза.
  async function install(onProgress) {
    const a = state.available;
    if (!a) return false;
    if (!a.installable || !a.update) {
      await T.opener.openUrl(a.url || RELEASES_URL);
      return false;
    }
    let total = 0, got = 0;
    await a.update.downloadAndInstall((ev) => {
      if (ev.event === 'Started') total = ev.data.contentLength || 0;
      if (ev.event === 'Progress') { got += ev.data.chunkLength; onProgress?.(total ? got / total : 0); }
      if (ev.event === 'Finished') onProgress?.(1);
    });
    await T.process.relaunch();
    return true;
  }

  async function openReleases() {
    await T.opener.openUrl((state.available && state.available.url) || RELEASES_URL);
  }

  window.CatUpdates = { state, check, install, openReleases, menuText, isNewer, RELEASES_URL };
})();
