# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Что это

Нативное macOS-приложение (Swift 5.9+, SwiftUI + AppKit, macOS 13+): котик-питомец поверх всех окон, который тапает лапками в такт нажатиям клавиш, ведёт статистику и держит скриншоты. Собирается только через SwiftPM, Xcode-проекта нет. Язык интерфейса, комментариев, README и коммитов — русский.

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

## Коммиты

Русский язык, Conventional Commits (`feat:`, `fix:`, …), без эмодзи, без трейлеров об инструментах. Перед коммитом проверять diff на запрещённые упоминания (см. глобальные правила пользователя).
