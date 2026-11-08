//! Файл неизвестных программ (D8): `[program."<команда>"]` с `count` и `last`.

use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};

use toml_edit::{value, DocumentMut, Item, Table};

/// Строка перечня: команда, счётчик, дата последнего появления.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Unknown {
    pub command: String,
    pub count: i64,
    pub last: String,
}

/// Увеличивает счётчик команды и ставит дату (`ГГГГ-ММ-ДД`).
pub fn bump_text(text: &str, command: &str, date: &str) -> Result<String, String> {
    let mut doc: DocumentMut = text
        .parse()
        .map_err(|e: toml_edit::TomlError| e.to_string())?;
    if !doc.contains_key("program") {
        let mut t = Table::new();
        t.set_implicit(true);
        doc.insert("program", Item::Table(t));
    }
    let programs = doc["program"]
        .as_table_mut()
        .ok_or("program: нужна таблица")?;
    if !programs.contains_key(command) {
        programs.insert(command, Item::Table(Table::new()));
    }
    let t = programs[command]
        .as_table_like_mut()
        .ok_or("program.<команда>: нужна таблица")?;
    let count = t.get("count").and_then(|i| i.as_integer()).unwrap_or(0) + 1;
    t.insert("count", value(count));
    t.insert("last", value(date));
    Ok(doc.to_string())
}

/// Удаляет команду; второй элемент — была ли она в файле.
pub fn remove_text(text: &str, command: &str) -> Result<(String, bool), String> {
    let mut doc: DocumentMut = text
        .parse()
        .map_err(|e: toml_edit::TomlError| e.to_string())?;
    let removed = doc
        .get_mut("program")
        .and_then(|p| p.as_table_mut())
        .and_then(|p| p.remove(command))
        .is_some();
    Ok((doc.to_string(), removed))
}

/// Перечень по убыванию счётчика, при равенстве — по имени.
pub fn list_text(text: &str) -> Vec<Unknown> {
    let Ok(t) = text.parse::<toml::Table>() else {
        return Vec::new();
    };
    let mut out: Vec<Unknown> = t
        .get("program")
        .and_then(|p| p.as_table())
        .map(|p| {
            p.iter()
                .map(|(k, v)| Unknown {
                    command: k.clone(),
                    count: v.get("count").and_then(|c| c.as_integer()).unwrap_or(0),
                    last: v
                        .get("last")
                        .and_then(|c| c.as_str())
                        .unwrap_or("")
                        .to_string(),
                })
                .collect()
        })
        .unwrap_or_default();
    out.sort_by(|a, b| b.count.cmp(&a.count).then(a.command.cmp(&b.command)));
    out
}

/// Путь файла: `$XDG_STATE_HOME/herdr-keys-help/unknown-programs.toml`.
pub fn default_path() -> PathBuf {
    crate::paths::state_dir().join("unknown-programs.toml")
}

/// Сегодняшняя дата по местному времени.
pub fn today() -> String {
    // SAFETY: time и localtime_r с указателями на локальные переменные.
    unsafe {
        let t = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&t, &mut tm);
        format!(
            "{:04}-{:02}-{:02}",
            tm.tm_year + 1900,
            tm.tm_mon + 1,
            tm.tm_mday
        )
    }
}

/// Правка файла под замком.
///
/// Замок: файл неизвестных программ один на пользователя (решение
/// пользователя), размножить его нельзя, а писать могут несколько
/// просмотрщиков — по одному на tab. Блокирующий `flock` файла-замка рядом
/// с файлом держится только на время одного цикла «чтение — правка —
/// временный файл — rename», поэтому ожидание ограничено длительностью одной
/// записи и срока не имеет. Снять замок можно, если писать будет один процесс.
fn locked_update(
    path: &Path,
    f: impl FnOnce(&str) -> Result<Option<String>, String>,
) -> Result<(), String> {
    let dir = path.parent().ok_or("нет каталога файла")?;
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let lock = std::fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(path.with_extension("lock"))
        .map_err(|e| e.to_string())?;
    // SAFETY: flock на открытом дескрипторе; замок снимается закрытием файла.
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX) } != 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }
    let text = std::fs::read_to_string(path).unwrap_or_default();
    if let Some(new) = f(&text)? {
        let tmp = path.with_extension(format!("toml.{}.tmp", std::process::id()));
        std::fs::write(&tmp, new).map_err(|e| e.to_string())?;
        std::fs::rename(&tmp, path).map_err(|e| e.to_string())?;
    }
    drop(lock);
    Ok(())
}

/// Отмечает появление команды без таблицы.
pub fn record(path: &Path, command: &str, date: &str) -> Result<(), String> {
    locked_update(path, |t| bump_text(t, command, date).map(Some))
}

/// Удаляет команду, получившую таблицу.
pub fn forget(path: &Path, command: &str) -> Result<(), String> {
    if !std::fs::read_to_string(path)
        .is_ok_and(|t| list_text(&t).iter().any(|u| u.command == command))
    {
        return Ok(());
    }
    locked_update(path, |t| {
        let (new, removed) = remove_text(t, command)?;
        Ok(removed.then_some(new))
    })
}

/// Перечень из файла.
pub fn list(path: &Path) -> Vec<Unknown> {
    std::fs::read_to_string(path)
        .map(|t| list_text(&t))
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bump_and_remove() {
        let t = bump_text("", "kh-unknown", "2026-11-08").expect("b");
        let t = bump_text(&t, "kh-unknown", "2026-11-09").expect("b");
        let t = bump_text(&t, "htop", "2026-11-09").expect("b");
        let l = list_text(&t);
        assert_eq!(l[0].command, "kh-unknown");
        assert_eq!(l[0].count, 2);
        assert_eq!(l[0].last, "2026-11-09");
        assert_eq!(t.matches("[program.kh-unknown]").count(), 1);
        let (t, removed) = remove_text(&t, "kh-unknown").expect("r");
        assert!(removed);
        assert_eq!(list_text(&t).len(), 1);
    }
}
