//! Глобальный монитор клавиатуры и мыши через rdev. Считаем только факт
//! нажатия; какие клавиши нажаты — не записываем. Код клавиши нужен лишь
//! чтобы выбрать лапу: левая половина клавиатуры — левая лапа.

use std::collections::HashSet;
use std::time::Duration;

use rdev::{listen, Event, EventType, Key};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};

use crate::AppState;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Paw {
    Left,
    Right,
}

#[derive(Serialize, Clone)]
struct TapPayload {
    paw: Paw,
    cpm: u64,
    total: u64,
}

fn is_left(key: &Key) -> bool {
    matches!(
        key,
        Key::KeyQ
            | Key::KeyW
            | Key::KeyE
            | Key::KeyR
            | Key::KeyT
            | Key::KeyA
            | Key::KeyS
            | Key::KeyD
            | Key::KeyF
            | Key::KeyG
            | Key::KeyZ
            | Key::KeyX
            | Key::KeyC
            | Key::KeyV
            | Key::KeyB
            | Key::Num1
            | Key::Num2
            | Key::Num3
            | Key::Num4
            | Key::Num5
            | Key::Tab
            | Key::CapsLock
            | Key::ShiftLeft
            | Key::ControlLeft
            | Key::Alt
            | Key::MetaLeft
            | Key::Escape
            | Key::BackQuote
            | Key::Function
    )
}

// MARK: - Разрешения

#[cfg(target_os = "macos")]
#[link(name = "ApplicationServices", kind = "framework")]
extern "C" {
    fn AXIsProcessTrusted() -> bool;
}

#[cfg(target_os = "macos")]
#[link(name = "CoreGraphics", kind = "framework")]
extern "C" {
    fn CGPreflightListenEventAccess() -> bool;
    fn CGRequestListenEventAccess() -> bool;
}

/// Может ли процесс слушать клавиатуру глобально.
pub fn is_trusted() -> bool {
    #[cfg(target_os = "macos")]
    unsafe {
        AXIsProcessTrusted() || CGPreflightListenEventAccess()
    }
    #[cfg(target_os = "linux")]
    {
        !is_wayland_only()
    }
    #[cfg(target_os = "windows")]
    {
        true
    }
}

/// Попросить систему показать диалог разрешения (macOS). На других платформах ничего не делает.
pub fn request_access() {
    #[cfg(target_os = "macos")]
    unsafe {
        CGRequestListenEventAccess();
    }
}

/// Wayland без X11 не даёт слушать клавиатуру глобально.
#[cfg(target_os = "linux")]
pub fn is_wayland_only() -> bool {
    let wayland = std::env::var("XDG_SESSION_TYPE").map(|v| v == "wayland").unwrap_or(false)
        || std::env::var("WAYLAND_DISPLAY").is_ok();
    wayland && std::env::var("DISPLAY").is_err()
}

/// Что сказать пользователю, если доступа нет.
pub fn access_hint() -> &'static str {
    #[cfg(target_os = "macos")]
    {
        "Нужно разрешение «Универсальный доступ» или «Мониторинг ввода»"
    }
    #[cfg(target_os = "linux")]
    {
        "Сессия Wayland без X11: глобальные нажатия недоступны. Войди в сессию X11 (Xorg)."
    }
    #[cfg(target_os = "windows")]
    {
        ""
    }
}

// MARK: - Поток слушателя

pub fn start(app: AppHandle) {
    let _ = std::thread::Builder::new().name("input-monitor".into()).spawn(move || {
        let mut announced_missing = false;
        loop {
            if !is_trusted() {
                if !announced_missing {
                    eprintln!("input monitor: нет доступа к клавиатуре, жду");
                    let _ = app.emit("access-changed", false);
                    announced_missing = true;
                }
                std::thread::sleep(Duration::from_secs(2));
                continue;
            }
            if announced_missing {
                let _ = app.emit("access-changed", true);
                announced_missing = false;
            }

            eprintln!("input monitor: доступ есть, слушаю клавиатуру");
            let handle = app.clone();
            let mut pressed: HashSet<Key> = HashSet::new();
            let mut last_paw = Paw::Right;
            let result = listen(move |event: Event| {
                handle_event(&handle, event, &mut pressed, &mut last_paw);
            });
            match result {
                Ok(()) => break,
                Err(err) => {
                    eprintln!("input monitor: {err:?}");
                    // На macOS listen падает, если доверие отозвали — подождём и попробуем снова.
                    std::thread::sleep(Duration::from_secs(5));
                }
            }
        }
    });
}

fn handle_event(app: &AppHandle, event: Event, pressed: &mut HashSet<Key>, last_paw: &mut Paw) {
    match event.event_type {
        EventType::KeyPress(key) => {
            if !pressed.insert(key) {
                return; // автоповтор
            }
            let paw = if key == Key::Space {
                if *last_paw == Paw::Left { Paw::Right } else { Paw::Left }
            } else if is_left(&key) {
                Paw::Left
            } else {
                Paw::Right
            };
            *last_paw = paw;
            on_key(app, paw);
        }
        EventType::KeyRelease(key) => {
            pressed.remove(&key);
        }
        EventType::ButtonPress(_) => on_click(app),
        _ => {}
    }
}

fn on_key(app: &AppHandle, paw: Paw) {
    let state = app.state::<AppState>();
    let (cpm, total, milestone) = {
        let mut stats = state.stats.lock();
        stats.record_key();
        let total = stats.data.total_keys;
        (stats.cpm(), total, total % 1000 == 0)
    };
    let _ = app.emit("tap", TapPayload { paw, cpm, total });
    if milestone {
        let _ = app.emit("say", crate::SayPayload { text: format!("🎉 {total} тапов!"), seconds: 4.0 });
    }
}

fn on_click(app: &AppHandle) {
    let state = app.state::<AppState>();
    let (cpm, total) = {
        let mut stats = state.stats.lock();
        stats.record_click();
        (stats.cpm(), stats.data.total_keys)
    };
    let _ = app.emit("tap", TapPayload { paw: Paw::Right, cpm, total });
}
