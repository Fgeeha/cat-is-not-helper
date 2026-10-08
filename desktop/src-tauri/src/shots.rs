//! Скриншоты котика: папка, список, импорт, миниатюры, захват области экрана.

use std::io::Cursor;
use std::path::{Path, PathBuf};

use base64::Engine;
use serde::Serialize;

use crate::paths;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ShotInfo {
    pub path: String,
    pub name: String,
    pub modified: i64,
    pub size: u64,
    pub is_image: bool,
}

const IMAGE_EXTENSIONS: &[&str] = &["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic"];

pub fn is_image(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| IMAGE_EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

pub fn stamp() -> String {
    chrono::Local::now().format("%Y-%m-%d_%H-%M-%S").to_string()
}

fn info(path: &Path) -> Option<ShotInfo> {
    let meta = std::fs::metadata(path).ok()?;
    let modified = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    Some(ShotInfo {
        path: path.to_string_lossy().into_owned(),
        name: path.file_name()?.to_string_lossy().into_owned(),
        modified,
        size: meta.len(),
        is_image: is_image(path),
    })
}

/// Все файлы в папке котика: картинки и любые документы, которые ему дали.
pub fn list() -> Vec<ShotInfo> {
    let mut items: Vec<ShotInfo> = std::fs::read_dir(paths::shots_dir())
        .map(|rd| {
            rd.filter_map(|e| e.ok())
                .map(|e| e.path())
                .filter(|p| p.is_file())
                .filter(|p| !p.file_name().map(|n| n.to_string_lossy().starts_with('.')).unwrap_or(true))
                .filter_map(|p| info(&p))
                .collect()
        })
        .unwrap_or_default();
    items.sort_by(|a, b| b.modified.cmp(&a.modified));
    items
}

/// Копирует файл (картинку или любой документ) в папку котика. Повторный импорт
/// того же файла (то же исходное имя и размер) возвращает уже существующую копию.
pub fn import(source: &Path) -> Option<PathBuf> {
    if !source.is_file() {
        return None;
    }
    let dir = paths::shots_dir();
    if source.parent().map(|p| p == dir).unwrap_or(false) {
        return Some(source.to_path_buf());
    }
    let name = source.file_name()?.to_string_lossy().into_owned();
    let size = std::fs::metadata(source).ok()?.len();
    if let Some(existing) = list()
        .into_iter()
        .find(|s| s.name.ends_with(&format!("-{name}")) && s.size == size)
    {
        return Some(PathBuf::from(existing.path));
    }
    let dest = dir.join(format!("cat-{}-{}", stamp(), name));
    std::fs::copy(source, &dest).ok()?;
    Some(dest)
}

pub fn delete(path: &Path) -> bool {
    if path.parent().map(|p| p != paths::shots_dir()).unwrap_or(true) {
        return false; // удаляем только своё
    }
    trash::delete(path).is_ok() || std::fs::remove_file(path).is_ok()
}

/// Миниатюра как data URL (PNG). Большие скриншоты не гоняем в webview целиком.
/// Для не-картинок возвращает None — интерфейс рисует карточку документа сам.
pub fn thumbnail_data_url(path: &Path, max: u32) -> Option<String> {
    if !is_image(path) {
        return None;
    }
    let img = image::open(path).ok()?;
    let thumb = img.thumbnail(max, max);
    let mut buf = Cursor::new(Vec::new());
    thumb.write_to(&mut buf, image::ImageFormat::Png).ok()?;
    let encoded = base64::engine::general_purpose::STANDARD.encode(buf.into_inner());
    Some(format!("data:image/png;base64,{encoded}"))
}

/// Захват прямоугольника экрана. Координаты — физические пиксели в системе координат экрана.
pub fn capture_physical(x: i32, y: i32, width: u32, height: u32) -> Result<PathBuf, String> {
    if width < 2 || height < 2 {
        return Err("слишком маленькая область".into());
    }
    let image = grab(x, y, width, height)?;
    let dest = paths::shots_dir().join(format!("cat-{}.png", stamp()));
    image.save(&dest).map_err(|e| format!("не удалось сохранить: {e}"))?;
    Ok(dest)
}

#[cfg(not(target_os = "linux"))]
fn grab(x: i32, y: i32, width: u32, height: u32) -> Result<image::RgbaImage, String> {
    let monitor = xcap::Monitor::from_point(x + (width as i32) / 2, y + (height as i32) / 2)
        .map_err(|e| format!("монитор не найден: {e}"))?;
    let mx = monitor.x().map_err(|e| e.to_string())?;
    let my = monitor.y().map_err(|e| e.to_string())?;
    let mw = monitor.width().map_err(|e| e.to_string())? as i32;
    let mh = monitor.height().map_err(|e| e.to_string())? as i32;

    // Обрезаем по границам монитора.
    let left = (x - mx).clamp(0, mw - 1);
    let top = (y - my).clamp(0, mh - 1);
    let right = (x - mx + width as i32).clamp(left + 1, mw);
    let bottom = (y - my + height as i32).clamp(top + 1, mh);

    monitor
        .capture_region(left as u32, top as u32, (right - left) as u32, (bottom - top) as u32)
        .map_err(|e| format!("не удалось снять экран: {e}"))
}

/// Linux: читаем область корневого окна X11. Координаты Tauri на X11 совпадают с корневыми.
#[cfg(target_os = "linux")]
fn grab(x: i32, y: i32, width: u32, height: u32) -> Result<image::RgbaImage, String> {
    use x11rb::connection::Connection;
    use x11rb::protocol::xproto::{ConnectionExt, ImageFormat};

    let (conn, screen_num) = x11rb::connect(None).map_err(|e| format!("нет X11: {e}"))?;
    let setup = conn.setup();
    let screen = &setup.roots[screen_num];
    let root_w = screen.width_in_pixels as i32;
    let root_h = screen.height_in_pixels as i32;

    let left = x.clamp(0, root_w - 1);
    let top = y.clamp(0, root_h - 1);
    let right = (x + width as i32).clamp(left + 1, root_w);
    let bottom = (y + height as i32).clamp(top + 1, root_h);
    let (w, h) = ((right - left) as u32, (bottom - top) as u32);

    let reply = conn
        .get_image(ImageFormat::Z_PIXMAP, screen.root, left as i16, top as i16, w as u16, h as u16, !0)
        .map_err(|e| format!("не удалось снять экран: {e}"))?
        .reply()
        .map_err(|e| format!("не удалось снять экран: {e}"))?;

    let bpp = setup
        .pixmap_formats
        .iter()
        .find(|f| f.depth == reply.depth)
        .map(|f| f.bits_per_pixel)
        .unwrap_or(32) as usize;
    let bytes_per_pixel = (bpp / 8).max(1);
    let stride = (w as usize * bytes_per_pixel + 3) / 4 * 4;
    let mut out = image::RgbaImage::new(w, h);
    for row in 0..h as usize {
        for col in 0..w as usize {
            let i = row * stride + col * bytes_per_pixel;
            if i + 2 >= reply.data.len() {
                break;
            }
            // X11 отдаёт BGR(X) при little-endian и 24/32 битах.
            let (b, g, r) = (reply.data[i], reply.data[i + 1], reply.data[i + 2]);
            out.put_pixel(col as u32, row as u32, image::Rgba([r, g, b, 255]));
        }
    }
    Ok(out)
}
