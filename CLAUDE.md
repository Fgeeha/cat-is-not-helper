# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Что это

Котик-питомец поверх всех окон, который тапает лапками в такт нажатиям клавиш, ведёт статистику и держит скриншоты. Две реализации с одинаковым поведением и общими данными (`stats.json`, папка скриншотов):

- **Нативная macOS** (Swift 5.9+, SwiftUI + AppKit, macOS 13+) в `Sources/`, `Package.swift`. Собирается только через SwiftPM, Xcode-проекта нет.
- **Кросс-платформенная** (Tauri 2: Rust + HTML/JS без сборщика) в `desktop/` для macOS, Windows, Linux (RedOS). См. раздел «Desktop (Tauri)» ниже.

Язык интерфейса, комментариев, README и коммитов — русский. Новая фича по умолчанию делается в обеих версиях; если делаешь только в одной — скажи об этом явно.

## Сборка и запуск

```bash
make build                       # swift build (debug)
make app                         # release + упаковка в build/CatIsNotHelper.app (scripts/build-app.sh)
make app-universal               # то же с ARCHS="arm64 x86_64"
make run                         # make app + open
make install                     # копия в /Applications
scripts/build-app.sh debug       # бандл из debug-сборки
```

CI: `.github/workflows/build.yml` на `macos-15` собирает универсальный бандл тем же скриптом, проверяет `lipo -archs`, `codesign --verify` и `--render`, выкладывает zip артефактом; тег `v*` создаёт релиз. Сертификата в CI нет, там подпись ad-hoc. Любое изменение сборки делать в `scripts/build-app.sh`, а не в workflow, чтобы локальная и CI-сборка не расходились.

Если `swift build` падает с «missing DEVELOPER_DIR path», значит `xcode-select` смотрит на несуществующий Xcode. `scripts/build-app.sh` сам подставляет `/Applications/Xcode.app`; для голого `swift build` нужно `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`.

Разрешение «Универсальный доступ» привязано к подписи бандла, поэтому `build-app.sh` подписывает первым сертификатом «Apple Development» (или `CODESIGN_IDENTITY`). Ad-hoc подпись (`--sign -`) не использовать: её cdhash меняется при каждой сборке, и котик перестаёт видеть клавиши. Если доступ всё же слетел, сброс записи: `tccutil reset Accessibility com.fgeeha.cat-is-not-helper`.

Тестов и линтера в проекте нет. Проверка — чистая сборка без предупреждений (`swift build -c release 2>&1 | grep warning:`) и визуальный рендер.

### Визуальная проверка без запуска GUI

У бинарника есть отладочные флаги (см. `main.swift`), которые рисуют SwiftUI в PNG через `ImageRenderer` и выходят:

```bash
.build/debug/CatIsNotHelper --render out.png [ginger|gray|black|white] [normal|happy|sleepy|grumpy|excited|tap|hold <img>] ["текст пузырька"]
# внешность через окружение: CAT_ACCESSORY=bow|glasses|hat|scarf CAT_EYES=green|blue|amber|brown CAT_KEYBOARD=light|pink CAT_MIRROR=1
.build/debug/CatIsNotHelper --render-stats out.png
```

`ImageRenderer` не рисует `ScrollView` и `LazyVGrid`, поэтому у `StatsView` контент вынесен в `content` без скролла, а карточки сделаны на `HStack`. Учитывай это, если добавляешь новые экраны под рендер.

## Архитектура

Точка входа — `main.swift` без `@main`: вручную создаёт `NSApplication`, ставит `.accessory` (нет иконки в Dock, `LSUIElement` в plist) и `AppDelegate`.

`AppDelegate` — единственный владелец всех объектов и единая точка действий. Он связывает:

- `CatState` (ObservableObject) — живое состояние котика: лапки, настроение, пузырёк, что держит. Все анимации запускаются через `withAnimation` внутри него, вью только отображает.
- `InputMonitor` — глобальный и локальный `NSEvent` мониторы. Глобальный keyDown работает только при Accessibility (`AXIsProcessTrusted`); `AppDelegate.tick()` раз в секунду опрашивает доверие и перезапускает монитор, когда его дали. Код клавиши используется только для выбора лапы (левая/правая половина клавиатуры) и не сохраняется.
- `StatsStore` — счётчики по дням (`yyyy-MM-dd`) и часам, CPM по скользящему окну 60 с, сохранение с дебаунсом в `~/Library/Application Support/CatIsNotHelper/stats.json`.
- `ScreenshotManager` — папка `~/Pictures/CatIsNotHelper`, запуск `/usr/sbin/screencapture -i -x` через `Process`, импорт с дедупликацией по исходному имени и размеру.
- `AppSettings.shared` — настройки в `UserDefaults`; `AppDelegate` подписан на `objectWillChange` и применяет их к панели.
- `CatPanel` + `CatContainerView` — прозрачный `NSPanel` (`.nonactivatingPanel`, `canBecomeKey = false`, чтобы фокус не уходил из редактора). Контейнер перехватывает мышь сам: клик — погладить, двойной — открыть скриншот, перетаскивание — `performDrag`, правый клик — то же меню, что в меню-баре, drop файла — отдать котику. SwiftUI-жесты на котике не использовать, они сломают перетаскивание окна.
- `StatusBarController` — иконка 🐾, меню строится заново при каждом открытии (`menuNeedsUpdate`), все действия делегируются в `AppDelegate`.
- Окна `StatsView`, `GalleryView`, `SettingsView` создаются в `AppDelegate.show(id:…)` один раз и переиспользуются (`isReleasedWhenClosed = false`).

`CatView` рисует котика в фиксированных дизайн-координатах 260×230 и масштабирует через `scaleEffect`; размер панели считается `CatView.size(for:)`. Все позиции частей — абсолютные `.position(x:y:)` в этой системе, поэтому новая деталь добавляется одной строкой в ZStack.

## Desktop (Tauri)

```bash
cd desktop && npm install
npm run dev                                   # tauri dev
npm run build                                 # установщики в src-tauri/target/release/bundle/
cd src-tauri && cargo check                   # быстрая проверка Rust (нужен DEVELOPER_DIR, см. выше)
npx tauri build --debug --bundles app         # отладочный .app для запуска на этой машине
```

Архитектура повторяет нативную: `src-tauri/src/lib.rs` — команды и запуск; `actions.rs` — единая точка действий для трея, контекстного меню и команд; `input.rs` — поток `rdev::listen` (на macOS ждёт доверия через `AXIsProcessTrusted`/`CGPreflightListenEventAccess`, на Wayland без X11 сообщает, что нажатия недоступны); `stats.rs` — тот же JSON, что у Swift, включая `firstLaunch` в секундах эпохи Apple; `shots.rs` — папка, импорт с дедупликацией, миниатюры base64, захват через `xcap` на macOS/Windows и через `x11rb` (GetImage корневого окна) на Linux, потому что `xcap` на Linux тянет pipewire, которого нет на ubuntu-22.04 и старых RedOS; `tray.rs` — меню, оно же контекстное для котика (`menu.popup`); все изменения пунктов меню идут через `run_on_main_thread`, иначе GTK на Linux падает. Котик держит стопку файлов (`AppState.held: Vec<PathBuf>`, последний сверху; payload `{top, paths, count}`): для не-картинок `thumb` = None, интерфейс рисует карточку с расширением, при count > 1 бейдж. Перетаскивание из лапок наружу на Linux идёт через свой `drag_out.rs` (см. раздел про стенд RedOS), на macOS/Windows — через `tauri-plugin-drag`. Пункт «Скопировать в буфер обмена» (`copy_held`) на Linux — собственный владелец CLIPBOARD в `clipboard_x11.rs` (x11rb), который отдаёт `text/uri-list`, `x-special/gnome-copied-files`, `image/png` и текст одновременно, чтобы вставка работала и в Caja/Nautilus, и в чатах; на macOS/Windows — arboard (объект `Clipboard` живёт в `AppState`). В нативной версии стопка — `CatState.heldStack`, верхний дублируется в `heldURL`/`heldImage`. Изменение размера окна котика делается с временным `set_resizable(true)`: GTK игнорирует `set_size` у неизменяемого окна. Скриншот области — свои окна-оверлеи `overlay-N` на каждом мониторе (`ui/overlay.html`), координаты переводятся в физические и режутся `xcap`.

Интерфейс: `ui/cat-renderer.js` — SVG-котик в тех же координатах 260×230 и его характер (настроение, пузырьки), общий для окна котика и превью настроек; `ui/cat.js` — связь с Tauri (события `tap`/`tick`/`say`/`held-changed`/`settings-changed`, мышь, перетаскивание окна, drag & drop картинок внутрь и наружу через `tauri-plugin-drag`); `ui/panel.*` — вкладки статистики, галереи, настроек. Плагины доступны через `window.__TAURI__` (`withGlobalTauri`), npm-зависимость одна — CLI.

Быстро посмотреть котика без Tauri: открыть страницу с `cat-renderer.js` в браузере (пример: заголовок `--allow-file-access-from-files` в headless Chrome) — рендерер не зависит от `window.__TAURI__`.

Bundle id у Tauri-версии другой (`…cat-is-not-helper.desktop`), чтобы на macOS две версии не делили одну запись TCC и не сбивали друг другу доступ к клавиатуре. Пути к данным при этом общие, они заданы явно в `paths.rs`.

Обновления: `ui/updates.js` сначала пробует `tauri-plugin-updater` (публичный ключ в `tauri.conf.json`, приватный только в секретах CI), а без `latest.json` или для rpm/deb берёт файл релиза через GitHub API и зовёт `install_release_asset` из `src-tauri/src/update.rs`: macOS подменяет бандл из `.app.tar.gz`, Windows запускает NSIS с `/S` через PowerShell, AppImage копирует поверх `$APPIMAGE`, rpm/deb ставятся `pkexec dnf|apt-get`. Какой файл релиза брать, решает `platform_info()` по суффиксу.

### Стенд RedOS 8 в Docker (`desktop/redos/`)

Живая проверка Linux-версии в RedOS 8 с разными рабочими столами. Базовый образ берётся из `registry.red-soft.ru/ubi8/ubi` (сертификат реестра выдан российским УЦ, поэтому тянуть через skopeo с `--src-tls-verify=false` и `docker load`). RedOS 7.3 не подходит: там нет webkit2gtk 4.1, Tauri 2 не запускается.

```bash
docker build --target mate|gnome|kde|cinnamon -t cat-redos8-<de> desktop/redos   # образы рабочих столов
desktop/redos/build.sh [каталог]       # release-сборка внутри RedOS, бинарник в desktop/redos/out
docker run -d --name cat-mate --shm-size=512m --cap-add SYS_NICE -e DE=mate -e SCREENS=1 \
  -v $PWD/desktop/redos:/redos:ro cat-redos8-mate /redos/session.sh
```

`DE`: `mate`, `gnome`, `gnome-wayland`, `kde`, `kde-wayland`, `cinnamon`; `SCREENS=2` — два монитора (Xorg с драйвером dummy, у Xvfb один RandR-выход). Сессия идёт от пользователя `u` на дисплее `:99`, окружение — в `/tmp/env.sh`; управлять через `xdotool`, снимать через `import -window root`. Wayland-сессии вложены в Xvfb, приложению нужен дисплей Xwayland (`:0`) и его Xauthority из `$XDG_RUNTIME_DIR`. Ограничения стенда: во вложенном KWin без GPU нет `ScreenShot2` (портал скриншотов KDE отказывает), в `kde-wayland` нет трея (kded не запущен).

Особенности Linux, найденные на стенде:
- В сессии Wayland приложение само ставит `GDK_BACKEND=x11` (через Xwayland): только X11-окно умеет стоять в углу, поверх всех и двигаться.
- Скриншот в Wayland — через `org.freedesktop.portal.Screenshot` (`shots::grab_portal`), X11 `GetImage` там падает с BadMatch. GNOME при каждом снимке спрашивает разрешение.
- Оверлеи выделения: сначала `show`, потом позиция и `fullscreen_on_monitor`, иначе оконный менеджер ужимает их до рабочей области и переносит с монитора с панелью на соседний. Координаты выделения пересчитываются по фактическому отношению физического размера окна к `innerWidth`: WebKitGTK масштабирует страницу по DPI шрифтов (у MATE часто не 96).
- Вынос файла из лапок на Linux — свой `drag_out.rs` (GTK): у `tauri-plugin-drag` на Linux в `drag_begin` передаётся маска кнопки вместо номера, перенос не завершается, а URI не экранируются. Файл уходит из стопки только после успешного броска (`drag-out-finished`).
- URI в буфере обмена и при переносе — с процентным кодированием (пробелы и кириллица).

## Коммиты

Русский язык, Conventional Commits (`feat:`, `fix:`, …), без эмодзи, без трейлеров об инструментах. Перед коммитом проверять diff на запрещённые упоминания (см. глобальные правила пользователя).
