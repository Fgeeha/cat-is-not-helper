//! Настройки котика. Хранятся в settings.json, применяются к окну в lib.rs.

use serde::{Deserialize, Serialize};

use crate::paths;

pub const DESIGN_WIDTH: f64 = 260.0;
pub const DESIGN_HEIGHT: f64 = 230.0;
pub const SCALE_MIN: f64 = 0.7;
pub const SCALE_MAX: f64 = 3.0;
/// Во сколько раз выросли пресеты размера (S 0.7→1.0, M 1.0→1.4, …).
const SIZE_V2_FACTOR: f64 = 1.4;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    pub scale: f64,
    pub opacity: f64,
    pub fur: String,
    pub accessory: String,
    pub eye_color: String,
    pub keyboard: String,
    pub mirrored: bool,
    pub always_on_top: bool,
    pub all_spaces: bool,
    pub bubbles: bool,
    pub cat_visible: bool,
    pub check_updates: bool,
    /// Позиция окна котика в физических пикселях экрана.
    pub position: Option<(i32, i32)>,
    /// Масштаб уже пересчитан под увеличенные пресеты. У старых файлов поля нет → false.
    #[serde(default)]
    pub size_v2: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            scale: 1.4,
            opacity: 1.0,
            fur: "ginger".into(),
            accessory: "none".into(),
            eye_color: "auto".into(),
            keyboard: "dark".into(),
            mirrored: false,
            always_on_top: true,
            all_spaces: true,
            bubbles: true,
            cat_visible: true,
            check_updates: true,
            position: None,
            size_v2: true,
        }
    }
}

impl Settings {
    pub fn load() -> Self {
        let mut settings: Self = std::fs::read(paths::settings_file())
            .ok()
            .and_then(|raw| serde_json::from_slice(&raw).ok())
            .unwrap_or_default();
        if !settings.size_v2 {
            settings.scale *= SIZE_V2_FACTOR;
            settings.size_v2 = true;
            settings.clamp();
            settings.save();
        }
        settings.clamp();
        settings
    }

    pub fn clamp(&mut self) {
        self.scale = self.scale.clamp(SCALE_MIN, SCALE_MAX);
        self.opacity = self.opacity.clamp(0.3, 1.0);
    }

    pub fn save(&self) {
        if let Ok(raw) = serde_json::to_vec_pretty(self) {
            let _ = std::fs::write(paths::settings_file(), raw);
        }
    }

    pub fn window_size(&self) -> (f64, f64) {
        (DESIGN_WIDTH * self.scale, DESIGN_HEIGHT * self.scale)
    }
}
