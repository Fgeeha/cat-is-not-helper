//! Где лежат данные. Пути совпадают с нативной macOS-версией, чтобы статистика
//! и скриншоты подхватывались при переходе.

use std::path::PathBuf;

const FOLDER: &str = "CatIsNotHelper";

/// ~/Library/Application Support/CatIsNotHelper · %APPDATA%\CatIsNotHelper · ~/.local/share/CatIsNotHelper
pub fn data_dir() -> PathBuf {
    let base = dirs::data_dir().unwrap_or_else(|| dirs::home_dir().unwrap_or_else(|| PathBuf::from(".")));
    let dir = base.join(FOLDER);
    let _ = std::fs::create_dir_all(&dir);
    dir
}

pub fn stats_file() -> PathBuf {
    data_dir().join("stats.json")
}

pub fn settings_file() -> PathBuf {
    data_dir().join("settings.json")
}

/// ~/Pictures/CatIsNotHelper
pub fn shots_dir() -> PathBuf {
    let base = dirs::picture_dir()
        .or_else(dirs::home_dir)
        .unwrap_or_else(|| PathBuf::from("."));
    let dir = base.join(FOLDER);
    let _ = std::fs::create_dir_all(&dir);
    dir
}
