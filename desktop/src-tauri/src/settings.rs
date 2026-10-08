//! Настройки котика. Хранятся в settings.json, применяются к окну в lib.rs.

use serde::{Deserialize, Serialize};

use crate::paths;

pub const DESIGN_WIDTH: f64 = 260.0;
pub const DESIGN_HEIGHT: f64 = 230.0;

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
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            scale: 1.0,
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
        }
    }
}

impl Settings {
    pub fn load() -> Self {
        std::fs::read(paths::settings_file())
            .ok()
            .and_then(|raw| serde_json::from_slice(&raw).ok())
            .unwrap_or_default()
    }

    pub fn save(&self) {
        if let Ok(raw) = serde_json::to_vec_pretty(self) {
            let _ = std::fs::write(paths::settings_file(), raw);
        }
    }

    pub fn window_size(&self) -> (f64, f64) {
        let scale = self.scale.clamp(0.5, 2.5);
        (DESIGN_WIDTH * scale, DESIGN_HEIGHT * scale)
    }
}
