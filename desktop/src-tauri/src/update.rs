//! Запасное обновление из GitHub Releases без latest.json: скачиваем файл релиза
//! и ставим его по правилам платформы. Штатный подписанный апдейтер Tauri
//! остаётся основным путём; этот нужен, когда релиз собран без ключа подписи
//! или когда приложение стоит из rpm/deb, которые Tauri обновлять не умеет.

use std::path::{Path, PathBuf};
use std::process::Command;

use serde::Serialize;
use tauri::{AppHandle, Emitter};

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct PlatformInfo {
    pub os: String,
    pub appimage: bool,
    /// "rpm" | "deb" | null — чем ставилось приложение на Linux.
    pub package: Option<String>,
    /// Суффикс файла в релизе, который подходит этой установке.
    pub asset_suffix: String,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct Progress {
    fraction: f64,
    stage: &'static str,
}

pub fn platform_info() -> PlatformInfo {
    let os = std::env::consts::OS.to_string();
    let appimage = std::env::var("APPIMAGE").is_ok();
    let package = if os == "linux" && !appimage { detect_linux_package() } else { None };
    let asset_suffix = match (os.as_str(), appimage, package.as_deref()) {
        ("macos", _, _) => ".app.tar.gz",
        ("windows", _, _) => "-setup.exe",
        ("linux", true, _) => ".AppImage",
        ("linux", false, Some("rpm")) => ".rpm",
        ("linux", false, Some("deb")) => ".deb",
        _ => "",
    }
    .to_string();
    PlatformInfo { os, appimage, package, asset_suffix }
}

#[cfg(target_os = "linux")]
fn detect_linux_package() -> Option<String> {
    let exe = std::env::current_exe().ok()?;
    // Пакет ставится в /usr/bin; если бинарник не оттуда — это не пакетная установка.
    if !exe.starts_with("/usr") && !exe.starts_with("/opt") {
        return None;
    }
    if Path::new("/usr/bin/dpkg").exists() && Path::new("/var/lib/dpkg/status").exists() {
        Some("deb".into())
    } else if Path::new("/usr/bin/rpm").exists() {
        Some("rpm".into())
    } else {
        None
    }
}

#[cfg(not(target_os = "linux"))]
fn detect_linux_package() -> Option<String> {
    None
}

fn emit(app: &AppHandle, fraction: f64, stage: &'static str) {
    let _ = app.emit("update-progress", Progress { fraction, stage });
}

/// Скачивает файл релиза и устанавливает. Возвращает Ok, если приложение
/// уже перезапущено или перезапустится само; дальше текущий процесс завершится.
pub async fn install_asset(app: AppHandle, url: String, name: String) -> Result<(), String> {
    let tmp = std::env::temp_dir().join("cat-is-not-helper-update");
    let _ = std::fs::create_dir_all(&tmp);
    let file = tmp.join(&name);

    emit(&app, 0.0, "download");
    download(&app, &url, &file).await?;
    emit(&app, 1.0, "install");

    let info = platform_info();
    match info.os.as_str() {
        "macos" => install_macos(&app, &file),
        "windows" => install_windows(&file),
        "linux" if info.appimage => install_appimage(&file),
        "linux" => install_linux_package(&file, info.package.as_deref()),
        other => Err(format!("обновление для {other} не поддерживается")),
    }
}

async fn download(app: &AppHandle, url: &str, dest: &Path) -> Result<(), String> {
    use futures_util::StreamExt;
    use std::io::Write;

    let client = reqwest::Client::builder()
        .user_agent("CatIsNotHelper")
        .build()
        .map_err(|e| e.to_string())?;
    let response = client.get(url).send().await.map_err(|e| format!("не удалось скачать: {e}"))?;
    if !response.status().is_success() {
        return Err(format!("GitHub ответил {}", response.status()));
    }
    let total = response.content_length().unwrap_or(0);
    let mut file = std::fs::File::create(dest).map_err(|e| format!("не удалось создать файл: {e}"))?;
    let mut stream = response.bytes_stream();
    let mut got: u64 = 0;
    let mut last_emit = 0.0;
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| format!("обрыв загрузки: {e}"))?;
        file.write_all(&chunk).map_err(|e| e.to_string())?;
        got += chunk.len() as u64;
        if total > 0 {
            let fraction = got as f64 / total as f64;
            if fraction - last_emit >= 0.02 {
                last_emit = fraction;
                emit(app, fraction, "download");
            }
        }
    }
    Ok(())
}

// MARK: - macOS: подменить бандл и перезапуститься

fn install_macos(app: &AppHandle, archive: &Path) -> Result<(), String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    // .../CatIsNotHelper.app/Contents/MacOS/cat-is-not-helper
    let bundle = exe
        .ancestors()
        .nth(3)
        .filter(|p| p.extension().map(|e| e == "app").unwrap_or(false))
        .ok_or("приложение запущено не из .app")?
        .to_path_buf();
    let unpack = archive.parent().unwrap().join("unpacked");
    let _ = std::fs::remove_dir_all(&unpack);
    std::fs::create_dir_all(&unpack).map_err(|e| e.to_string())?;
    let status = Command::new("/usr/bin/tar")
        .args(["-xzf", &archive.to_string_lossy(), "-C", &unpack.to_string_lossy()])
        .status()
        .map_err(|e| e.to_string())?;
    if !status.success() {
        return Err("архив повреждён".into());
    }
    let new_app = std::fs::read_dir(&unpack)
        .map_err(|e| e.to_string())?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .find(|p| p.extension().map(|e| e == "app").unwrap_or(false))
        .ok_or("в архиве нет .app")?;

    let parent = bundle.parent().ok_or("нет родительской папки")?;
    let backup = parent.join(format!(".{}.old", bundle.file_name().unwrap().to_string_lossy()));
    let _ = std::fs::remove_dir_all(&backup);
    std::fs::rename(&bundle, &backup).map_err(|e| format!("нет прав на замену приложения: {e}"))?;
    if let Err(e) = std::fs::rename(&new_app, &bundle).or_else(|_| copy_dir(&new_app, &bundle)) {
        let _ = std::fs::rename(&backup, &bundle);
        return Err(format!("не удалось поставить новую версию: {e}"));
    }
    let _ = std::fs::remove_dir_all(&backup);
    let _ = std::fs::remove_dir_all(&unpack);
    let _ = std::fs::remove_file(archive);

    let _ = Command::new("/bin/sh")
        .arg("-c")
        .arg(format!("sleep 1; /usr/bin/open -n \"{}\"", bundle.to_string_lossy()))
        .spawn();
    app.exit(0);
    Ok(())
}

fn copy_dir(from: &Path, to: &Path) -> std::io::Result<()> {
    let status = Command::new("/usr/bin/ditto").arg(from).arg(to).status()?;
    if status.success() { Ok(()) } else { Err(std::io::Error::other("ditto failed")) }
}

// MARK: - Windows: тихий установщик NSIS

fn install_windows(installer: &Path) -> Result<(), String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    // Ждём завершения установщика и запускаем приложение заново.
    let script = format!(
        "Start-Process -FilePath '{}' -ArgumentList '/S' -Wait; Start-Process -FilePath '{}'",
        installer.to_string_lossy().replace('\'', "''"),
        exe.to_string_lossy().replace('\'', "''")
    );
    Command::new("powershell")
        .args(["-NoProfile", "-WindowStyle", "Hidden", "-Command", &script])
        .spawn()
        .map_err(|e| format!("не удалось запустить установщик: {e}"))?;
    std::process::exit(0);
}

// MARK: - Linux AppImage: заменить сам файл

fn install_appimage(new_file: &Path) -> Result<(), String> {
    let current = PathBuf::from(std::env::var("APPIMAGE").map_err(|_| "не AppImage")?);
    std::fs::copy(new_file, &current).map_err(|e| format!("нет прав на замену {}: {e}", current.display()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&current, std::fs::Permissions::from_mode(0o755));
    }
    let _ = std::fs::remove_file(new_file);
    Command::new("/bin/sh")
        .arg("-c")
        .arg(format!("sleep 1; \"{}\" &", current.to_string_lossy()))
        .spawn()
        .map_err(|e| e.to_string())?;
    std::process::exit(0);
}

// MARK: - Linux rpm/deb: пакетный менеджер через polkit

fn install_linux_package(file: &Path, package: Option<&str>) -> Result<(), String> {
    let path = file.to_string_lossy().into_owned();
    let (manager, args): (&str, Vec<String>) = match package {
        Some("rpm") => {
            if Path::new("/usr/bin/dnf").exists() {
                ("dnf", vec!["install".into(), "-y".into(), path.clone()])
            } else {
                ("rpm", vec!["-Uvh".into(), path.clone()])
            }
        }
        Some("deb") => ("apt-get", vec!["install".into(), "-y".into(), path.clone()]),
        _ => return Err("непонятно, чем ставить пакет".into()),
    };
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let status = Command::new("pkexec")
        .arg(manager)
        .args(&args)
        .status()
        .map_err(|e| format!("не удалось вызвать pkexec: {e}"))?;
    if !status.success() {
        return Err(format!("{manager} завершился с ошибкой (код {:?})", status.code()));
    }
    let _ = std::fs::remove_file(file);
    Command::new("/bin/sh")
        .arg("-c")
        .arg(format!("sleep 1; \"{}\" &", exe.to_string_lossy()))
        .spawn()
        .map_err(|e| e.to_string())?;
    std::process::exit(0);
}
