//! Каталоги и файлы плагина.

use std::io::Write;
use std::path::PathBuf;

pub fn home() -> String {
    std::env::var("HOME").unwrap_or_else(|_| "/".to_string())
}

fn xdg(var: &str, fallback: &str) -> PathBuf {
    match std::env::var(var) {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => PathBuf::from(home()).join(fallback),
    }
}

/// `$XDG_RUNTIME_DIR/herdr-keys-help` — канал записей поставщиков (D2).
pub fn runtime_dir() -> PathBuf {
    match std::env::var("XDG_RUNTIME_DIR") {
        Ok(v) if !v.is_empty() => PathBuf::from(v).join("herdr-keys-help"),
        // SAFETY: getuid не имеет побочных эффектов.
        _ => PathBuf::from(format!("/run/user/{}", unsafe { libc::getuid() })).join("herdr-keys-help"),
    }
}

/// Каталог каталогов записей панелей.
pub fn panes_dir() -> PathBuf {
    runtime_dir().join("panes")
}

/// Каталог записей панели.
pub fn pane_dir(pane_id: &str) -> PathBuf {
    panes_dir().join(pane_id)
}

pub fn state_dir() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state").join("herdr-keys-help")
}

pub fn cache_dir() -> PathBuf {
    xdg("XDG_CACHE_HOME", ".cache").join("herdr-keys-help")
}

/// Конфигурация представления: `KEYS_HELP_VIEW` или
/// `$XDG_CONFIG_HOME/herdr/keys-help/view.toml`.
pub fn view_path() -> PathBuf {
    if let Ok(v) = std::env::var("KEYS_HELP_VIEW") {
        if !v.is_empty() {
            return PathBuf::from(v);
        }
    }
    xdg("XDG_CONFIG_HOME", ".config").join("herdr/keys-help/view.toml")
}

/// Корень плагина: `HERDR_PLUGIN_ROOT` или каталог выше `target/<профиль>/`.
pub fn plugin_root() -> PathBuf {
    if let Ok(v) = std::env::var("HERDR_PLUGIN_ROOT") {
        if !v.is_empty() {
            return PathBuf::from(v);
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(root) = exe.parent().and_then(|p| p.parent()).and_then(|p| p.parent()) {
            if root.join("herdr-plugin.toml").exists() {
                return root.to_path_buf();
            }
        }
    }
    PathBuf::from(".")
}

/// Каталоги манифестов: `KEYS_HELP_MANIFESTS` (через `:`) или `manifests/` плагина.
pub fn manifest_dirs() -> Vec<PathBuf> {
    if let Ok(v) = std::env::var("KEYS_HELP_MANIFESTS") {
        if !v.is_empty() {
            return v.split(':').filter(|s| !s.is_empty()).map(PathBuf::from).collect();
        }
    }
    vec![plugin_root().join("manifests")]
}

/// Журнал плагина: `$HERDR_PLUGIN_STATE_DIR/keys-help.log` или каталог состояния.
pub fn log_path() -> PathBuf {
    match std::env::var("HERDR_PLUGIN_STATE_DIR") {
        Ok(v) if !v.is_empty() => PathBuf::from(v).join("keys-help.log"),
        _ => state_dir().join("keys-help.log"),
    }
}

/// Строка в журнал плагина.
pub fn log(msg: &str) {
    let p = log_path();
    if let Some(d) = p.parent() {
        let _ = std::fs::create_dir_all(d);
    }
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&p) {
        let _ = writeln!(f, "{} [{}] {msg}", crate::unknown::today(), std::process::id());
    }
}

/// Строка отладки в журнал плагина: пишется, только если задана переменная
/// окружения `KEYS_HELP_DEBUG` (непустая).
pub fn debug(msg: &str) {
    if std::env::var("KEYS_HELP_DEBUG").is_ok_and(|v| !v.is_empty()) {
        log(&format!("debug: {msg}"));
    }
}
