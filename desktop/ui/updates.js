// Проверка и установка обновлений, общая для окна котика и панели.
// Основной путь — подписанный апдейтер Tauri (latest.json в релизе).
// Запасной — GitHub API: берём файл релиза, подходящий этой установке
// (dmg-архив, установщик exe, AppImage, rpm или deb), и ставим его через Rust.
(function () {
  const T = window.__TAURI__;
  const { invoke } = T.core;
  const REPO = 'Fgeeha/cat-is-not-helper';
  const RELEASES_URL = `https://github.com/${REPO}/releases/latest`;

  const state = { available: null, checking: false, installing: false, info: null, version: null };

  function isNewer(candidate, current) {
    const parts = (s) => String(s).replace(/^v/, '').split(/[.+-]/).slice(0, 3).map((p) => parseInt(p, 10) || 0);
    const a = parts(candidate), b = parts(current);
    for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] > b[i];
    return false;
  }

  async function init() {
    if (state.version) return;
    state.info = await invoke('platform_info');
    state.version = await invoke('app_version');
  }

  async function viaTauri() {
    try {
      const update = await T.updater.check();
      if (!update) return { none: true };
      // Tauri не умеет ставить rpm/deb — для них идём через GitHub.
      const pkg = state.info.package;
      if (pkg) return null;
      return { version: update.version, update, installable: true, url: RELEASES_URL, source: 'tauri' };
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
    const suffix = state.info.assetSuffix;
    const asset = suffix ? (json.assets || []).find((a) => a.name.endsWith(suffix)) : null;
    return {
      version,
      update: null,
      asset: asset ? { url: asset.browser_download_url, name: asset.name, size: asset.size } : null,
      installable: !!asset,
      url: json.html_url || RELEASES_URL,
      source: 'github',
    };
  }

  function menuText() {
    if (!state.available) return 'Проверить обновления';
    return state.available.installable
      ? `⬆️ Обновить до v${state.available.version}…`
      : `⬆️ Скачать v${state.available.version} на GitHub`;
  }

  /// Возвращает { none } | { version, installable, url, ... } и обновляет пункт меню.
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

  /// Установить, если можно; иначе открыть страницу релиза. onProgress(fraction, stage).
  async function install(onProgress) {
    const a = state.available;
    if (!a) return false;
    if (!a.installable) {
      await T.opener.openUrl(a.url || RELEASES_URL);
      return false;
    }
    if (state.installing) return false;
    state.installing = true;
    try {
      if (a.update) {
        let total = 0, got = 0;
        await a.update.downloadAndInstall((ev) => {
          if (ev.event === 'Started') total = ev.data.contentLength || 0;
          if (ev.event === 'Progress') { got += ev.data.chunkLength; onProgress?.(total ? got / total : 0, 'download'); }
          if (ev.event === 'Finished') onProgress?.(1, 'install');
        });
        await T.process.relaunch();
        return true;
      }
      const unlisten = await T.event.listen('update-progress', (e) => onProgress?.(e.payload.fraction, e.payload.stage));
      try {
        await invoke('install_release_asset', { url: a.asset.url, name: a.asset.name });
      } finally {
        unlisten();
      }
      return true;
    } finally {
      state.installing = false;
    }
  }

  async function openReleases() {
    await T.opener.openUrl((state.available && state.available.url) || RELEASES_URL);
  }

  window.CatUpdates = { state, check, install, openReleases, menuText, isNewer, RELEASES_URL };
})();
