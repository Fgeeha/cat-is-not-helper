//! Действия приложения: одна точка для трея, контекстного меню и команд из webview.

use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Emitter, LogicalSize, Manager, PhysicalPosition, Position, Size, WebviewUrl, WebviewWindowBuilder};

use crate::settings::Settings;
use crate::{input, shots, tray, AppState, SayPayload};

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct HeldPayload {
    pub path: Option<String>,
    pub thumb: Option<String>,
}

pub fn say(app: &AppHandle, text: impl Into<String>, seconds: f64) {
    let _ = app.emit("say", SayPayload { text: text.into(), seconds });
}

pub fn pet(app: &AppHandle) {
    app.state::<AppState>().stats.lock().record_pet();
    let _ = app.emit("pet", ());
}

pub fn feed(app: &AppHandle) {
    app.state::<AppState>().stats.lock().record_feed();
    let _ = app.emit("feed", ());
}

pub fn open_panel(app: &AppHandle, tab: &str) {
    if let Some(panel) = app.get_webview_window("panel") {
        let _ = panel.show();
        let _ = panel.unminimize();
        let _ = panel.set_focus();
        let _ = panel.emit("panel-tab", tab);
    }
}

pub fn request_access(app: &AppHandle) {
    input::request_access();
    #[cfg(target_os = "macos")]
    {
        let _ = tauri_plugin_opener::open_url(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            None::<&str>,
        );
    }
    let _ = app;
}

// MARK: - Что держит котик

pub fn held_payload(app: &AppHandle) -> HeldPayload {
    let held = app.state::<AppState>().held.lock().clone();
    match held {
        Some(path) => HeldPayload {
            thumb: shots::thumbnail_data_url(&path, 480),
            path: Some(path.to_string_lossy().into_owned()),
        },
        None => HeldPayload { path: None, thumb: None },
    }
}

pub fn hold(app: &AppHandle, path: PathBuf, announce: bool) {
    *app.state::<AppState>().held.lock() = Some(path);
    let _ = app.emit("held-changed", held_payload(app));
    if announce {
        say(app, ["держу!", "о, скриншот", "не потеряю", "моя прелесть"][fastrand(4)], 2.6);
    }
    tray::refresh(app);
}

pub fn put_away(app: &AppHandle, message: Option<&str>) {
    *app.state::<AppState>().held.lock() = None;
    let _ = app.emit("held-changed", HeldPayload { path: None, thumb: None });
    if let Some(text) = message {
        say(app, text, 2.6);
    }
    tray::refresh(app);
}

pub fn open_held(app: &AppHandle) {
    let held = app.state::<AppState>().held.lock().clone();
    match held {
        Some(path) => {
            let _ = tauri_plugin_opener::open_path(path.to_string_lossy().into_owned(), None::<&str>);
        }
        None => pet(app),
    }
}

/// Картинки, брошенные на котика или выбранные в галерее.
pub fn give(app: &AppHandle, source: &Path) -> bool {
    let Some(stored) = shots::import(source) else {
        say(app, "это не картинка 🤔", 2.6);
        return false;
    };
    if stored != source {
        app.state::<AppState>().stats.lock().record_screenshot();
    }
    hold(app, stored, true);
    true
}

// MARK: - Настройки

pub fn update_settings(app: &AppHandle, change: impl FnOnce(&mut Settings)) {
    let snapshot = {
        let state = app.state::<AppState>();
        let mut settings = state.settings.lock();
        change(&mut settings);
        settings.scale = settings.scale.clamp(0.5, 2.5);
        settings.opacity = settings.opacity.clamp(0.3, 1.0);
        settings.save();
        settings.clone()
    };
    apply_settings(app, &snapshot);
}

pub fn apply_settings(app: &AppHandle, settings: &Settings) {
    if let Some(cat) = app.get_webview_window("cat") {
        let (w, h) = settings.window_size();
        let _ = cat.set_size(Size::Logical(LogicalSize::new(w, h)));
        let _ = cat.set_always_on_top(settings.always_on_top);
        let _ = cat.set_visible_on_all_workspaces(settings.all_spaces);
        if settings.cat_visible {
            let _ = cat.show();
        } else {
            let _ = cat.hide();
        }
    }
    let _ = app.emit("settings-changed", settings);
    tray::refresh(app);
}

pub fn toggle_cat(app: &AppHandle) {
    update_settings(app, |s| s.cat_visible = !s.cat_visible);
}

pub fn quit(app: &AppHandle) {
    app.state::<AppState>().stats.lock().save();
    app.exit(0);
}

/// Первое размещение котика: сохранённая позиция или правый нижний угол основного экрана.
pub fn place_cat(app: &AppHandle) {
    let Some(cat) = app.get_webview_window("cat") else { return };
    let settings = app.state::<AppState>().settings.lock().clone();
    let (w, h) = settings.window_size();
    let _ = cat.set_size(Size::Logical(LogicalSize::new(w, h)));

    if let Some((x, y)) = settings.position {
        let _ = cat.set_position(Position::Physical(PhysicalPosition::new(x, y)));
    } else if let Ok(Some(monitor)) = app.primary_monitor() {
        let sf = monitor.scale_factor();
        let area = monitor.work_area();
        let x = area.position.x + area.size.width as i32 - (w * sf) as i32 - (24.0 * sf) as i32;
        let y = area.position.y + area.size.height as i32 - (h * sf) as i32 - (16.0 * sf) as i32;
        let _ = cat.set_position(Position::Physical(PhysicalPosition::new(x, y)));
    }
    let _ = cat.set_focusable(false);
    if settings.cat_visible {
        let _ = cat.show();
    }
}

// MARK: - Скриншот области

pub fn start_capture(app: &AppHandle) {
    let Ok(monitors) = app.available_monitors() else { return };
    if monitors.is_empty() {
        return;
    }
    if let Some(cat) = app.get_webview_window("cat") {
        let _ = cat.hide();
    }
    for (i, monitor) in monitors.iter().enumerate() {
        let label = format!("overlay-{i}");
        let Ok(win) = WebviewWindowBuilder::new(app, &label, WebviewUrl::App("overlay.html".into()))
            .title("Выдели область")
            .decorations(false)
            .transparent(true)
            .shadow(false)
            .always_on_top(true)
            .skip_taskbar(true)
            .resizable(false)
            .visible(false)
            .build()
        else {
            continue;
        };
        let _ = win.set_position(Position::Physical(*monitor.position()));
        let _ = win.set_size(Size::Physical(*monitor.size()));
        let _ = win.show();
        if i == 0 {
            let _ = win.set_focus();
        }
    }
}

fn close_overlays(app: &AppHandle) {
    for (label, win) in app.webview_windows() {
        if label.starts_with("overlay-") {
            let _ = win.close();
        }
    }
}

fn restore_cat(app: &AppHandle) {
    let visible = app.state::<AppState>().settings.lock().cat_visible;
    if visible {
        if let Some(cat) = app.get_webview_window("cat") {
            let _ = cat.show();
        }
    }
}

pub fn cancel_capture(app: &AppHandle) {
    close_overlays(app);
    restore_cat(app);
    say(app, "передумал? ладно", 2.0);
}

/// Прямоугольник в логических координатах окна-оверлея с меткой `label`.
pub fn finish_capture(app: &AppHandle, label: &str, x: f64, y: f64, width: f64, height: f64) {
    let Some(overlay) = app.get_webview_window(label) else {
        close_overlays(app);
        restore_cat(app);
        return;
    };
    let sf = overlay.scale_factor().unwrap_or(1.0);
    let origin = overlay.outer_position().unwrap_or(PhysicalPosition::new(0, 0));
    let px = origin.x + (x * sf).round() as i32;
    let py = origin.y + (y * sf).round() as i32;
    let pw = (width * sf).round().max(1.0) as u32;
    let ph = (height * sf).round().max(1.0) as u32;

    close_overlays(app);

    let app = app.clone();
    std::thread::spawn(move || {
        // Даём композитору убрать оверлеи, иначе они попадут в кадр.
        std::thread::sleep(Duration::from_millis(250));
        let result = shots::capture_physical(px, py, pw, ph);
        restore_cat(&app);
        match result {
            Ok(path) => {
                app.state::<AppState>().stats.lock().record_screenshot();
                hold(&app, path, true);
            }
            Err(err) => say(&app, format!("не вышло: {err}"), 4.0),
        }
    });
}

fn fastrand(n: usize) -> usize {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.subsec_nanos()).unwrap_or(0);
    (nanos as usize) % n
}
