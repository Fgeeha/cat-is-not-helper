//! Cat Is Not Helper — кросс-платформенный котик на Tauri.

mod actions;
mod input;
mod paths;
mod settings;
mod shots;
mod stats;
mod tray;
mod update;

use std::path::PathBuf;
use std::time::{Duration, Instant};

use parking_lot::Mutex;
use serde::Serialize;
use tauri::menu::ContextMenu;
use tauri::{AppHandle, Emitter, Manager, WindowEvent};

use settings::Settings;
use shots::ShotInfo;
use stats::{Snapshot, StatsStore};

pub struct AppState {
    pub stats: Mutex<StatsStore>,
    pub settings: Mutex<Settings>,
    pub held: Mutex<Option<PathBuf>>,
    pub tray: Mutex<Option<tray::TrayMenu>>,
    pub last_position_save: Mutex<Instant>,
    /// Держим буфер обмена живым: на X11 содержимое пропадает, если владелец закрыт.
    pub clipboard: Mutex<Option<arboard::Clipboard>>,
}

#[derive(Serialize, Clone)]
pub struct SayPayload {
    pub text: String,
    pub seconds: f64,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct TickPayload {
    cpm: u64,
    today_keys: u64,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct AccessStatus {
    trusted: bool,
    hint: String,
}

// MARK: - Команды из webview

#[tauri::command]
fn get_settings(state: tauri::State<AppState>) -> Settings {
    state.settings.lock().clone()
}

#[tauri::command]
fn set_settings(app: AppHandle, settings: Settings) {
    actions::update_settings(&app, |current| {
        let position = current.position;
        *current = settings;
        current.position = position;
    });
}

#[tauri::command]
fn stats_snapshot(state: tauri::State<AppState>) -> Snapshot {
    state.stats.lock().snapshot()
}

#[tauri::command]
fn record_pet(app: AppHandle) {
    app.state::<AppState>().stats.lock().record_pet();
}

#[tauri::command]
fn record_feed(app: AppHandle) {
    app.state::<AppState>().stats.lock().record_feed();
}

#[tauri::command]
fn list_shots() -> Vec<ShotInfo> {
    shots::list()
}

#[tauri::command]
fn thumbnail(path: String, max: u32) -> Option<String> {
    shots::thumbnail_data_url(std::path::Path::new(&path), max)
}

#[tauri::command]
fn import_files(app: AppHandle, paths: Vec<String>) -> bool {
    paths.first().map(|p| actions::give(&app, std::path::Path::new(p))).unwrap_or(false)
}

#[tauri::command]
fn give_shot(app: AppHandle, path: String) {
    actions::hold(&app, PathBuf::from(path), true);
}

#[tauri::command]
fn put_away(app: AppHandle, message: Option<String>) {
    actions::put_away(&app, message.as_deref());
}

#[tauri::command]
fn get_held(app: AppHandle) -> actions::HeldPayload {
    actions::held_payload(&app)
}

#[tauri::command]
fn open_held(app: AppHandle) {
    actions::open_held(&app);
}

#[tauri::command]
fn copy_held(app: AppHandle) {
    actions::copy_held(&app);
}

#[tauri::command]
fn delete_shot(app: AppHandle, path: String) -> bool {
    let target = PathBuf::from(&path);
    let is_held = app.state::<AppState>().held.lock().as_ref() == Some(&target);
    if is_held {
        actions::put_away(&app, None);
    }
    shots::delete(&target)
}

#[tauri::command]
fn reveal_shot(path: String) {
    let _ = tauri_plugin_opener::reveal_item_in_dir(path);
}

#[tauri::command]
fn open_shot(path: String) {
    let _ = tauri_plugin_opener::open_path(path, None::<&str>);
}

#[tauri::command]
fn open_shots_folder() {
    let _ = tauri_plugin_opener::open_path(paths::shots_dir().to_string_lossy().into_owned(), None::<&str>);
}

#[tauri::command]
fn shots_folder() -> String {
    paths::shots_dir().to_string_lossy().into_owned()
}

#[tauri::command]
fn start_capture(app: AppHandle) {
    actions::start_capture(&app);
}

#[tauri::command]
fn finish_capture(app: AppHandle, label: String, x: f64, y: f64, width: f64, height: f64) {
    actions::finish_capture(&app, &label, x, y, width, height);
}

#[tauri::command]
fn cancel_capture(app: AppHandle) {
    actions::cancel_capture(&app);
}

#[tauri::command]
fn show_cat_menu(app: AppHandle) {
    let state = app.state::<AppState>();
    let menu = state.tray.lock().as_ref().map(|t| t.menu.clone());
    if let (Some(menu), Some(cat)) = (menu, app.get_webview_window("cat")) {
        let _ = menu.popup(cat.as_ref().window());
    }
}

#[tauri::command]
fn access_status() -> AccessStatus {
    AccessStatus { trusted: input::is_trusted(), hint: input::access_hint().to_string() }
}

#[tauri::command]
fn request_access(app: AppHandle) {
    actions::request_access(&app);
}

#[tauri::command]
fn open_panel(app: AppHandle, tab: String) {
    actions::open_panel(&app, &tab);
}

#[tauri::command]
fn pet(app: AppHandle) {
    actions::pet(&app);
}

#[tauri::command]
fn feed(app: AppHandle) {
    actions::feed(&app);
}

#[tauri::command]
fn set_mood(app: AppHandle, text: String) {
    tray::set_mood_text(&app, &text);
}

#[tauri::command]
fn set_update_text(app: AppHandle, text: String) {
    tray::set_update_text(&app, &text);
}

#[tauri::command]
fn app_version(app: AppHandle) -> String {
    app.package_info().version.to_string()
}

#[tauri::command]
fn platform() -> String {
    std::env::consts::OS.to_string()
}

#[tauri::command]
fn is_appimage() -> bool {
    std::env::var("APPIMAGE").is_ok()
}

#[tauri::command]
fn platform_info() -> update::PlatformInfo {
    update::platform_info()
}

#[tauri::command]
async fn install_release_asset(app: AppHandle, url: String, name: String) -> Result<(), String> {
    app.state::<AppState>().stats.lock().save();
    update::install_asset(app, url, name).await
}

#[tauri::command]
fn quit(app: AppHandle) {
    actions::quit(&app);
}

// MARK: - Запуск

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, None))
        .plugin(tauri_plugin_drag::init())
        .manage(AppState {
            stats: Mutex::new(StatsStore::load()),
            settings: Mutex::new(Settings::load()),
            held: Mutex::new(None),
            tray: Mutex::new(None),
            last_position_save: Mutex::new(Instant::now()),
            clipboard: Mutex::new(None),
        })
        .setup(|app| {
            let handle = app.handle().clone();
            let menu = tray::build(&handle)?;
            *handle.state::<AppState>().tray.lock() = Some(menu);

            actions::place_cat(&handle);
            {
                let settings = handle.state::<AppState>().settings.lock().clone();
                actions::apply_settings(&handle, &settings);
            }
            tray::refresh(&handle);
            input::start(handle.clone());

            // Секундный тик: скорость, сохранение, обновление меню.
            let ticker = handle.clone();
            std::thread::spawn(move || {
                let mut n: u64 = 0;
                loop {
                    std::thread::sleep(Duration::from_secs(1));
                    let state = ticker.state::<AppState>();
                    let (cpm, today) = {
                        let mut stats = state.stats.lock();
                        let cpm = stats.tick();
                        (cpm, stats.today().keys)
                    };
                    let _ = ticker.emit("tick", TickPayload { cpm, today_keys: today });
                    n += 1;
                    if n % 5 == 0 {
                        tray::refresh(&ticker);
                    }
                }
            });
            Ok(())
        })
        .on_window_event(|window, event| match event {
            WindowEvent::CloseRequested { api, .. } if window.label() == "panel" => {
                api.prevent_close();
                let _ = window.hide();
            }
            WindowEvent::CloseRequested { api, .. } if window.label() == "cat" => {
                api.prevent_close();
                actions::update_settings(window.app_handle(), |s| s.cat_visible = false);
            }
            WindowEvent::Moved(position) if window.label() == "cat" => {
                let app = window.app_handle();
                let state = app.state::<AppState>();
                let mut settings = state.settings.lock();
                settings.position = Some((position.x, position.y));
                let mut last = state.last_position_save.lock();
                if last.elapsed() > Duration::from_secs(2) {
                    settings.save();
                    *last = Instant::now();
                }
            }
            _ => {}
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            set_settings,
            stats_snapshot,
            record_pet,
            record_feed,
            list_shots,
            thumbnail,
            import_files,
            give_shot,
            put_away,
            get_held,
            open_held,
            copy_held,
            delete_shot,
            reveal_shot,
            open_shot,
            open_shots_folder,
            shots_folder,
            start_capture,
            finish_capture,
            cancel_capture,
            show_cat_menu,
            access_status,
            request_access,
            open_panel,
            pet,
            feed,
            set_mood,
            set_update_text,
            app_version,
            platform,
            is_appimage,
            platform_info,
            install_release_asset,
            quit
        ])
        .build(tauri::generate_context!())
        .expect("не удалось запустить котика")
        .run(|app, event| {
            if let tauri::RunEvent::ExitRequested { .. } | tauri::RunEvent::Exit = event {
                app.state::<AppState>().stats.lock().save();
                app.state::<AppState>().settings.lock().save();
            }
        });
}
