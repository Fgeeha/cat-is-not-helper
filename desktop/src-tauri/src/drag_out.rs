//! Перетаскивание файла из лапок наружу на Linux через GTK напрямую.
//!
//! tauri-plugin-drag на Linux передаёт в gtk_drag_begin маску кнопки
//! (GDK_BUTTON1_MASK = 256) вместо её номера, поэтому отпускание мыши не
//! завершает перенос, а пути попадают в URI без экранирования (пробелы и
//! кириллица ломают список). Здесь то же самое, но с кнопкой 1 и
//! glib::filename_to_uri. Итог (бросили или отменили) приходит событием
//! `drag-out-finished` с булевым значением.

use std::cell::{Cell, RefCell};
use std::path::PathBuf;
use std::rc::Rc;

use gtk::gdk_pixbuf::Pixbuf;
use gtk::prelude::*;
use gtk::{gdk, glib};
use tauri::{AppHandle, Emitter, Manager};

use crate::shots;

const ICON_SIZE: i32 = 96;

pub fn start(app: &AppHandle, path: PathBuf) {
    let handle = app.clone();
    let _ = app.run_on_main_thread(move || {
        if let Err(err) = begin(&handle, path) {
            eprintln!("drag out: {err}");
            let _ = handle.emit("drag-out-finished", false);
        }
    });
}

fn begin(app: &AppHandle, path: PathBuf) -> Result<(), String> {
    let cat = app.get_webview_window("cat").ok_or("нет окна котика")?;
    let window = cat.gtk_window().map_err(|e| e.to_string())?;
    let uri = glib::filename_to_uri(&path, None).map_err(|e| e.to_string())?;

    window.drag_source_set(gdk::ModifierType::BUTTON1_MASK, &[], gdk::DragAction::COPY);
    window.drag_source_add_uri_targets();
    let targets = window.drag_source_get_target_list().ok_or("пустой список форматов")?;

    let handlers = Rc::new(RefCell::new(Vec::new()));
    let failed = Rc::new(Cell::new(false));

    handlers.borrow_mut().push(window.connect_drag_data_get(move |_, _, data, _, _| {
        data.set_uris(&[uri.as_str()]);
    }));
    let flag = failed.clone();
    handlers.borrow_mut().push(window.connect_drag_failed(move |_, _, _| {
        flag.set(true);
        glib::Propagation::Proceed
    }));
    let (done_handlers, done_app) = (handlers.clone(), app.clone());
    handlers.borrow_mut().push(window.connect_drag_end(move |w, _| {
        for id in done_handlers.borrow_mut().drain(..) {
            w.disconnect(id);
        }
        w.drag_source_unset();
        let _ = done_app.emit("drag-out-finished", !failed.get());
    }));

    // Кнопка 1, а не маска: по ней GTK узнаёт отпускание и завершает перенос.
    let Some(context) = window.drag_begin_with_coordinates(&targets, gdk::DragAction::COPY, 1, None, -1, -1) else {
        // drag-end не придёт: снимаем обработчики сами, иначе они копятся на окне.
        for id in handlers.borrow_mut().drain(..) {
            window.disconnect(id);
        }
        window.drag_source_unset();
        return Err("GTK не начал перенос".into());
    };

    let icon = shots::is_image(&path)
        .then(|| Pixbuf::from_file_at_scale(&path, ICON_SIZE, ICON_SIZE, true).ok())
        .flatten();
    match icon {
        Some(pixbuf) => context.drag_set_icon_pixbuf(&pixbuf, pixbuf.width() / 2, pixbuf.height() / 2),
        None => context.drag_set_icon_name("text-x-generic", ICON_SIZE / 4, ICON_SIZE / 4),
    }
    Ok(())
}
