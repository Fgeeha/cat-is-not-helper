//! Иконка в трее и общее меню (оно же контекстное меню котика).

use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::{AppHandle, Emitter, Manager, Wry};

use crate::{actions, AppState};

pub const SIZES: &[(&str, f64)] = &[("S", 0.7), ("M", 1.0), ("L", 1.4), ("XL", 2.0)];
pub const FURS: &[(&str, &str)] = &[("ginger", "Рыжий"), ("gray", "Серый"), ("black", "Чёрный"), ("white", "Белый")];

pub struct TrayMenu {
    pub menu: Menu<Wry>,
    pub header: MenuItem<Wry>,
    pub mood: MenuItem<Wry>,
    pub access: MenuItem<Wry>,
    pub update: MenuItem<Wry>,
    pub open_held: MenuItem<Wry>,
    pub put_away: MenuItem<Wry>,
    pub put_away_all: MenuItem<Wry>,
    pub copy_held: MenuItem<Wry>,
    pub toggle_cat: MenuItem<Wry>,
    pub sizes: Vec<CheckMenuItem<Wry>>,
    pub furs: Vec<CheckMenuItem<Wry>>,
}

pub fn build(app: &AppHandle) -> tauri::Result<TrayMenu> {
    let header = MenuItem::with_id(app, "header", "Сегодня: 0 тапов", false, None::<&str>)?;
    let mood = MenuItem::with_id(app, "mood", "Настроение: 😺", false, None::<&str>)?;
    let access = MenuItem::with_id(app, "access", "⚠️ Дать доступ к клавиатуре…", false, None::<&str>)?;
    let update = MenuItem::with_id(app, "update", "Проверить обновления", true, None::<&str>)?;
    let open_held = MenuItem::with_id(app, "open-held", "Открыть то, что держит котик", false, None::<&str>)?;
    let put_away = MenuItem::with_id(app, "put-away", "Забрать у котика", false, None::<&str>)?;
    let put_away_all = MenuItem::with_id(app, "put-away-all", "Забрать всё", false, None::<&str>)?;
    let copy_held = MenuItem::with_id(app, "copy-held", "Скопировать в буфер обмена", false, None::<&str>)?;
    let toggle_cat = MenuItem::with_id(app, "toggle-cat", "Спрятать котика", true, None::<&str>)?;

    let sizes: Vec<CheckMenuItem<Wry>> = SIZES
        .iter()
        .map(|(label, scale)| {
            CheckMenuItem::with_id(
                app,
                format!("size-{label}"),
                format!("{label} · {}%", (scale * 100.0) as i32),
                true,
                false,
                None::<&str>,
            )
        })
        .collect::<Result<_, _>>()?;
    let furs: Vec<CheckMenuItem<Wry>> = FURS
        .iter()
        .map(|(id, title)| CheckMenuItem::with_id(app, format!("fur-{id}"), *title, true, false, None::<&str>))
        .collect::<Result<_, _>>()?;

    let size_refs: Vec<&dyn tauri::menu::IsMenuItem<Wry>> = sizes.iter().map(|i| i as &dyn tauri::menu::IsMenuItem<Wry>).collect();
    let fur_refs: Vec<&dyn tauri::menu::IsMenuItem<Wry>> = furs.iter().map(|i| i as &dyn tauri::menu::IsMenuItem<Wry>).collect();
    let size_menu = Submenu::with_id_and_items(app, "size", "Размер", true, &size_refs)?;
    let fur_menu = Submenu::with_id_and_items(app, "fur", "Окрас", true, &fur_refs)?;

    let menu = Menu::with_items(
        app,
        &[
            &header,
            &mood,
            &access,
            &update,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "stats", "Статистика…", true, None::<&str>)?,
            &MenuItem::with_id(app, "shot", "Сделать скриншот — котик подержит", true, None::<&str>)?,
            &MenuItem::with_id(app, "gallery", "Галерея скриншотов…", true, None::<&str>)?,
            &open_held,
            &copy_held,
            &put_away,
            &put_away_all,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "pet", "Погладить", true, None::<&str>)?,
            &MenuItem::with_id(app, "feed", "Покормить 🐟", true, None::<&str>)?,
            &PredefinedMenuItem::separator(app)?,
            &toggle_cat,
            &size_menu,
            &fur_menu,
            &MenuItem::with_id(app, "settings", "Настройки…", true, None::<&str>)?,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "quit", "Выйти", true, None::<&str>)?,
        ],
    )?;

    if let Some(tray) = app.tray_by_id("main") {
        tray.set_menu(Some(menu.clone()))?;
    }

    app.on_menu_event(|app, event| {
        let id = event.id().as_ref();
        match id {
            "access" => actions::request_access(app),
            "update" => {
                // Логика в окне котика: проверить / установить / открыть GitHub.
                let _ = app.emit("update-action", ());
            }
            "stats" => actions::open_panel(app, "stats"),
            "shot" => actions::start_capture(app),
            "gallery" => actions::open_panel(app, "gallery"),
            "open-held" => actions::open_held(app),
            "copy-held" => actions::copy_held(app),
            "put-away" => actions::put_away(app, Some("ладно, забирай"), None),
            "put-away-all" => actions::put_away_all(app, Some("ладно, забирай всё")),
            "pet" => actions::pet(app),
            "feed" => actions::feed(app),
            "toggle-cat" => actions::toggle_cat(app),
            "settings" => actions::open_panel(app, "settings"),
            "quit" => actions::quit(app),
            other => {
                if let Some(label) = other.strip_prefix("size-") {
                    if let Some((_, scale)) = SIZES.iter().find(|(l, _)| *l == label) {
                        actions::update_settings(app, |s| s.scale = *scale);
                    }
                } else if let Some(fur) = other.strip_prefix("fur-") {
                    actions::update_settings(app, |s| s.fur = fur.to_string());
                }
            }
        }
    });

    Ok(TrayMenu { menu, header, mood, access, update, open_held, put_away, put_away_all, copy_held, toggle_cat, sizes, furs })
}

/// Обновить динамические пункты: заголовок, доступ, что держит, размер и окрас.
/// Меню трогаем только из главного потока: на Linux (GTK) вызов из другого
/// потока роняет приложение.
pub fn refresh(app: &AppHandle) {
    let handle = app.clone();
    let _ = app.run_on_main_thread(move || refresh_now(&handle));
}

fn refresh_now(app: &AppHandle) {
    let state = app.state::<AppState>();
    let tray = state.tray.lock();
    let Some(tray) = tray.as_ref() else { return };

    let (today, cpm) = {
        let stats = state.stats.lock();
        (stats.today().keys, stats.cpm())
    };
    let _ = tray.header.set_text(format!("Сегодня: {today} тапов · {cpm}/мин"));

    let needs_access = !crate::input::is_trusted();
    let _ = tray.access.set_enabled(needs_access);
    let _ = tray.access.set_text(if needs_access {
        "⚠️ Дать доступ к клавиатуре…"
    } else {
        "✓ Клавиатуру вижу"
    });

    let count = state.held.lock().len();
    let _ = tray.open_held.set_enabled(count > 0);
    let _ = tray.put_away.set_enabled(count > 0);
    let _ = tray.put_away.set_text(if count > 1 { format!("Забрать у котика верхний (из {count})") } else { "Забрать у котика".to_string() });
    let _ = tray.put_away_all.set_enabled(count > 1);
    let _ = tray.copy_held.set_enabled(count > 0);

    let settings = state.settings.lock().clone();
    let _ = tray
        .toggle_cat
        .set_text(if settings.cat_visible { "Спрятать котика" } else { "Показать котика" });
    for (item, (_, scale)) in tray.sizes.iter().zip(SIZES.iter()) {
        let _ = item.set_checked((settings.scale - scale).abs() < 0.01);
    }
    for (item, (id, _)) in tray.furs.iter().zip(FURS.iter()) {
        let _ = item.set_checked(settings.fur == *id);
    }
}

pub fn set_mood_text(app: &AppHandle, text: &str) {
    let handle = app.clone();
    let text = format!("Настроение: {text}");
    let _ = app.run_on_main_thread(move || {
        let state = handle.state::<AppState>();
        let guard = state.tray.lock();
        if let Some(tray) = guard.as_ref() {
            let _ = tray.mood.set_text(&text);
        }
    });
}

pub fn set_update_text(app: &AppHandle, text: &str) {
    let handle = app.clone();
    let text = text.to_string();
    let _ = app.run_on_main_thread(move || {
        let state = handle.state::<AppState>();
        let guard = state.tray.lock();
        if let Some(tray) = guard.as_ref() {
            let _ = tray.update.set_text(&text);
        }
    });
}
