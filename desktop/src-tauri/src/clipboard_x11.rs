//! Буфер обмена X11 с несколькими форматами сразу: список файлов
//! (text/uri-list и x-special/gnome-copied-files — так вставка в Caja,
//! Nautilus, Dolphin создаёт копию файла), PNG для чатов и редакторов,
//! путь текстом. Обычные библиотеки умеют либо текст, либо картинку,
//! а файловым менеджерам нужен именно uri-list.
//!
//! Владение буфером живёт в отдельном потоке, пока его не перехватит
//! другое приложение (SelectionClear) или мы не положим новое содержимое.

#![cfg(target_os = "linux")]

use std::sync::mpsc::{self, Sender};
use std::sync::OnceLock;

use x11rb::connection::Connection;
use x11rb::protocol::xproto::{
    Atom, AtomEnum, ConnectionExt, CreateWindowAux, EventMask, PropMode, SelectionNotifyEvent, SelectionRequestEvent,
    WindowClass, SELECTION_NOTIFY_EVENT,
};
use x11rb::protocol::Event;
use x11rb::wrapper::ConnectionExt as _;

#[derive(Clone)]
pub struct Content {
    pub paths: Vec<String>,
    pub png: Option<Vec<u8>>,
}

static SENDER: OnceLock<Sender<Content>> = OnceLock::new();

/// Положить содержимое в CLIPBOARD. Поток-владелец создаётся при первом вызове.
pub fn set(content: Content) -> Result<(), String> {
    let sender = SENDER.get_or_init(|| {
        let (tx, rx) = mpsc::channel::<Content>();
        std::thread::Builder::new()
            .name("x11-clipboard".into())
            .spawn(move || serve(rx))
            .expect("clipboard thread");
        tx
    });
    sender.send(content).map_err(|_| "поток буфера обмена остановлен".to_string())
}

struct Atoms {
    clipboard: Atom,
    targets: Atom,
    multiple: Atom,
    timestamp: Atom,
    uri_list: Atom,
    gnome_files: Atom,
    png: Atom,
    utf8: Atom,
    text_plain: Atom,
    text_plain_utf8: Atom,
    atom_pair: Atom,
    incr: Atom,
}

fn intern<C: Connection>(conn: &C, name: &str) -> Atom {
    conn.intern_atom(false, name.as_bytes())
        .ok()
        .and_then(|c| c.reply().ok())
        .map(|r| r.atom)
        .unwrap_or(u32::from(AtomEnum::NONE))
}

fn serve(rx: mpsc::Receiver<Content>) {
    let Ok((conn, screen_num)) = x11rb::connect(None) else {
        eprintln!("clipboard: нет X11");
        return;
    };
    let screen = &conn.setup().roots[screen_num];
    let window = conn.generate_id().unwrap_or(0);
    let _ = conn.create_window(
        0,
        window,
        screen.root,
        0, 0, 1, 1, 0,
        WindowClass::INPUT_OUTPUT,
        screen.root_visual,
        &CreateWindowAux::new().event_mask(EventMask::PROPERTY_CHANGE),
    );
    let atoms = Atoms {
        clipboard: intern(&conn, "CLIPBOARD"),
        targets: intern(&conn, "TARGETS"),
        multiple: intern(&conn, "MULTIPLE"),
        timestamp: intern(&conn, "TIMESTAMP"),
        uri_list: intern(&conn, "text/uri-list"),
        gnome_files: intern(&conn, "x-special/gnome-copied-files"),
        png: intern(&conn, "image/png"),
        utf8: intern(&conn, "UTF8_STRING"),
        text_plain: intern(&conn, "text/plain"),
        text_plain_utf8: intern(&conn, "text/plain;charset=utf-8"),
        atom_pair: intern(&conn, "ATOM_PAIR"),
        incr: intern(&conn, "INCR"),
    };
    let _ = conn.flush();

    let mut content: Option<Content> = None;
    let mut owning = false;

    loop {
        // Новое содержимое: забираем владение селекцией.
        while let Ok(new) = rx.try_recv() {
            content = Some(new);
            let _ = conn.set_selection_owner(window, atoms.clipboard, x11rb::CURRENT_TIME);
            let _ = conn.flush();
            owning = true;
        }
        if !owning {
            // Ничего не держим: просто ждём следующего содержимого.
            match rx.recv() {
                Ok(new) => {
                    content = Some(new);
                    let _ = conn.set_selection_owner(window, atoms.clipboard, x11rb::CURRENT_TIME);
                    let _ = conn.flush();
                    owning = true;
                }
                Err(_) => return,
            }
            continue;
        }
        let event = match conn.poll_for_event() {
            Ok(Some(e)) => e,
            Ok(None) => {
                std::thread::sleep(std::time::Duration::from_millis(20));
                continue;
            }
            Err(_) => return,
        };
        match event {
            Event::SelectionRequest(req) => {
                if let Some(c) = content.as_ref() {
                    handle_request(&conn, &atoms, c, &req);
                }
            }
            Event::SelectionClear(_) => {
                owning = false;
                content = None;
            }
            _ => {}
        }
    }
}

fn uri_list(paths: &[String]) -> Vec<u8> {
    paths.iter().map(|p| format!("file://{p}\r\n")).collect::<String>().into_bytes()
}

fn gnome_files(paths: &[String]) -> Vec<u8> {
    let mut s = String::from("copy");
    for p in paths {
        s.push('\n');
        s.push_str(&format!("file://{p}"));
    }
    s.into_bytes()
}

fn data_for(atoms: &Atoms, content: &Content, target: Atom) -> Option<(Atom, Vec<u8>, u8)> {
    if target == atoms.uri_list {
        Some((atoms.uri_list, uri_list(&content.paths), 8))
    } else if target == atoms.gnome_files {
        Some((atoms.gnome_files, gnome_files(&content.paths), 8))
    } else if target == atoms.png {
        content.png.as_ref().map(|png| (atoms.png, png.clone(), 8))
    } else if target == atoms.utf8 || target == atoms.text_plain_utf8 || target == atoms.text_plain || target == Atom::from(AtomEnum::STRING) {
        Some((target, content.paths.join("\n").into_bytes(), 8))
    } else {
        None
    }
}

fn handle_request<C: Connection>(conn: &C, atoms: &Atoms, content: &Content, req: &SelectionRequestEvent) {
    let property = if req.property == u32::from(AtomEnum::NONE) { req.target } else { req.property };
    let mut ok = false;

    if req.target == atoms.targets {
        let mut list: Vec<Atom> = vec![atoms.targets, atoms.timestamp, atoms.multiple, atoms.uri_list, atoms.gnome_files,
            atoms.utf8, atoms.text_plain_utf8, atoms.text_plain, u32::from(AtomEnum::STRING)];
        if content.png.is_some() {
            list.push(atoms.png);
        }
        ok = conn
            .change_property32(PropMode::REPLACE, req.requestor, property, AtomEnum::ATOM, &list)
            .is_ok();
    } else if req.target == atoms.timestamp {
        ok = conn
            .change_property32(PropMode::REPLACE, req.requestor, property, AtomEnum::INTEGER, &[req.time])
            .is_ok();
    } else if req.target == atoms.multiple {
        // Пары (target, property) в свойстве requestor; отвечаем на каждую.
        if let Ok(reply) = conn
            .get_property(false, req.requestor, property, atoms.atom_pair, 0, u32::MAX)
            .and_then(|c| Ok(c.reply()))
        {
            if let Ok(reply) = reply {
                if let Some(values) = reply.value32() {
                    let pairs: Vec<u32> = values.collect();
                    for pair in pairs.chunks(2) {
                        if let [target, prop] = pair {
                            if let Some((kind, bytes, _)) = data_for(atoms, content, *target) {
                                if bytes.len() < 4_000_000 {
                                    let _ = conn.change_property8(PropMode::REPLACE, req.requestor, *prop, kind, &bytes);
                                }
                            }
                        }
                    }
                    ok = true;
                }
            }
        }
    } else if let Some((kind, bytes, _)) = data_for(atoms, content, req.target) {
        // Очень большие данные требовали бы INCR; скриншоты в такой размер не упираются.
        if bytes.len() < 16_000_000 {
            ok = conn
                .change_property8(PropMode::REPLACE, req.requestor, property, kind, &bytes)
                .is_ok();
        }
    }

    let notify = SelectionNotifyEvent {
        response_type: SELECTION_NOTIFY_EVENT,
        sequence: 0,
        time: req.time,
        requestor: req.requestor,
        selection: req.selection,
        target: req.target,
        property: if ok { property } else { u32::from(AtomEnum::NONE) },
    };
    let _ = conn.send_event(false, req.requestor, EventMask::NO_EVENT, notify);
    let _ = conn.flush();
    let _ = atoms.incr;
}
