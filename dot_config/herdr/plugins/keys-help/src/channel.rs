//! Канал «верхняя панель → просмотрщик» (D2): каталог записей панели,
//! разбор записей, порядок по `mtime` и событиям inotify, живость процессов
//! по pidfd, файл `env-vars`.

use std::collections::BTreeMap;
use std::ffi::CString;
use std::os::fd::{FromRawFd, OwnedFd, RawFd};
use std::path::{Path, PathBuf};

use serde::Deserialize;

/// Запись поставщика.
#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct Record {
    #[serde(default)]
    pub v: i64,
    pub program: String,
    #[serde(default)]
    pub mode: Option<String>,
    pub pid: i32,
    #[serde(default = "default_state")]
    pub state: String,
    #[serde(default)]
    pub command: Option<String>,
    #[serde(default)]
    pub table: Option<String>,
    #[serde(default)]
    pub server: Option<String>,
    #[serde(default)]
    pub env: BTreeMap<String, String>,
}

fn default_state() -> String {
    "active".to_string()
}

impl Record {
    /// Поля записи для подстановок `{record.<поле>}`.
    pub fn fields(&self) -> BTreeMap<String, String> {
        let mut m = BTreeMap::new();
        m.insert("program".to_string(), self.program.clone());
        m.insert("pid".to_string(), self.pid.to_string());
        m.insert("state".to_string(), self.state.clone());
        for (k, v) in [
            ("mode", &self.mode),
            ("command", &self.command),
            ("table", &self.table),
            ("server", &self.server),
        ] {
            if let Some(v) = v {
                m.insert(k.to_string(), v.clone());
            }
        }
        m
    }
}

/// Разбирает запись; неразобранная пропускается до следующего события.
pub fn parse_record(text: &str) -> Option<Record> {
    serde_json::from_str(text).ok()
}

/// Запись в каталоге с порядковым номером изменения.
#[derive(Debug, Clone)]
pub struct Slot {
    pub name: String,
    pub record: Record,
    pub seq: u64,
}

/// Записи каталога цели в порядке изменения.
#[derive(Debug, Default)]
pub struct Records {
    pub slots: Vec<Slot>,
    next_seq: u64,
}

impl Records {
    /// Начальный набор: записи каталога по `mtime` (наносекунды).
    pub fn scan(dir: &Path) -> Records {
        let mut items: Vec<(i128, String, Record)> = Vec::new();
        if let Ok(rd) = std::fs::read_dir(dir) {
            for e in rd.flatten() {
                let name = e.file_name().to_string_lossy().to_string();
                if !name.ends_with(".json") {
                    continue;
                }
                let p = e.path();
                let Some(r) = std::fs::read_to_string(&p).ok().and_then(|t| parse_record(&t)) else {
                    continue;
                };
                items.push((crate::extract::mtime_ns(&p).unwrap_or(0), name, r));
            }
        }
        items.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
        let mut rs = Records::default();
        for (_, name, record) in items {
            rs.put(name, record);
        }
        rs
    }

    /// Новая или изменённая запись становится последней.
    pub fn put(&mut self, name: String, record: Record) {
        self.next_seq += 1;
        let seq = self.next_seq;
        self.slots.retain(|s| s.name != name);
        self.slots.push(Slot { name, record, seq });
    }

    pub fn remove(&mut self, name: &str) {
        self.slots.retain(|s| s.name != name);
    }

    /// Удаляет записи процесса.
    pub fn remove_pid(&mut self, pid: i32) -> Vec<String> {
        let names: Vec<String> = self
            .slots
            .iter()
            .filter(|s| s.record.pid == pid)
            .map(|s| s.name.clone())
            .collect();
        self.slots.retain(|s| s.record.pid != pid);
        names
    }

    /// Активная запись: последняя изменённая запись живого процесса.
    pub fn active(&self, alive: impl Fn(i32) -> bool) -> Option<&Record> {
        self.slots
            .iter()
            .rev()
            .find(|s| alive(s.record.pid))
            .map(|s| &s.record)
    }

    /// Последняя запись программы (для подстановок при печати таблицы).
    pub fn latest_of(&self, program: &str) -> Option<&Record> {
        self.slots.iter().rev().find(|s| s.record.program == program).map(|s| &s.record)
    }
}

/// Открывает pidfd процесса; `None` — процесса нет.
pub fn pidfd_open(pid: i32) -> Option<OwnedFd> {
    // SAFETY: системный вызов pidfd_open возвращает новый дескриптор или -1.
    let fd = unsafe { libc::syscall(libc::SYS_pidfd_open, pid, 0) } as RawFd;
    if fd < 0 {
        return None;
    }
    // SAFETY: fd — только что полученный дескриптор, владеем им.
    Some(unsafe { OwnedFd::from_raw_fd(fd) })
}

/// Жив ли процесс (проверка, не ожидание).
pub fn alive(pid: i32) -> bool {
    // SAFETY: kill с сигналом 0 только проверяет существование процесса.
    pid > 0 && (unsafe { libc::kill(pid, 0) } == 0 || std::io::Error::last_os_error().raw_os_error() == Some(libc::EPERM))
}

/// Переносит каталог записей при `pane.moved`: каталог переименовывается
/// на новый id, а на месте старого остаётся символическая ссылка на новый.
/// Поставщики панели сохраняют прежний `HERDR_PANE_ID` и продолжают писать
/// (и выполнять `mkdir -p`) по старому пути — запись через ссылку попадает
/// в новый каталог.
pub fn move_pane_dir(old: &str, new: &str) {
    let from = crate::paths::pane_dir(old);
    let to = crate::paths::pane_dir(new);
    if from == to {
        return;
    }
    let is_link = std::fs::symlink_metadata(&from).is_ok_and(|m| m.file_type().is_symlink());
    if is_link {
        return;
    }
    if from.is_dir() {
        if to.exists() {
            // Новый каталог уже есть: перенести записи по одной.
            if let Ok(rd) = std::fs::read_dir(&from) {
                for e in rd.flatten() {
                    let _ = std::fs::rename(e.path(), to.join(e.file_name()));
                }
            }
            let _ = std::fs::remove_dir(&from);
        } else if std::fs::rename(&from, &to).is_err() {
            return;
        }
    } else {
        let _ = std::fs::create_dir_all(&to);
    }
    let _ = std::os::unix::fs::symlink(&to, &from);
}

/// Удаляет каталог записей закрытой панели `id` в каталоге `panes`
/// вместе с символическими ссылками на него, оставленными `move_pane_dir`
/// под прежними id. Если `id` сам — ссылка (панель закрыта под прежним id),
/// удаляется только ссылка.
pub fn remove_pane_dir_in(panes: &Path, id: &str) {
    if id.is_empty() || id.contains('/') {
        return;
    }
    let dir = panes.join(id);
    let Ok(meta) = std::fs::symlink_metadata(&dir) else {
        return;
    };
    if meta.file_type().is_symlink() {
        let _ = std::fs::remove_file(&dir);
        return;
    }
    let _ = std::fs::remove_dir_all(&dir);
    if let Ok(rd) = std::fs::read_dir(panes) {
        for e in rd.flatten() {
            let p = e.path();
            if std::fs::read_link(&p).is_ok_and(|t| t == dir) {
                let _ = std::fs::remove_file(&p);
            }
        }
    }
}

pub fn remove_pane_dir(id: &str) {
    remove_pane_dir_in(&crate::paths::panes_dir(), id);
}

/// Имена в каталоге `panes` (каталоги и ссылки) — снимок до запроса
/// списка панелей herdr: каталог панели, созданной после снимка, в уборку
/// не попадает, даже если панели нет в более раннем ответе.
pub fn pane_dir_names_in(panes: &Path) -> Vec<String> {
    std::fs::read_dir(panes)
        .map(|rd| rd.flatten().map(|e| e.file_name().to_string_lossy().to_string()).collect())
        .unwrap_or_default()
}

/// Уборка каталогов панелей, которых нет среди живых (`live`): каталоги
/// закрытых без просмотрщика панелей. Ссылка прежнего id остаётся, пока
/// жив каталог, на который она указывает: по ней пишет оболочка
/// перенесённой панели.
pub fn sweep_pane_dirs_in(panes: &Path, names: &[String], live: &std::collections::HashSet<String>) {
    let mut links = Vec::new();
    for n in names {
        if live.contains(n) {
            continue;
        }
        let p = panes.join(n);
        if std::fs::symlink_metadata(&p).is_ok_and(|m| m.file_type().is_symlink()) {
            links.push(p);
        } else {
            remove_pane_dir_in(panes, n);
        }
    }
    for l in links {
        // Ссылка на исчезнувший каталог (`exists` идёт по ссылке).
        if !l.exists() {
            let _ = std::fs::remove_file(&l);
        }
    }
}

/// Файл `env-vars`: имена переменных по строке; пишется, только если изменился,
/// чтобы не менять `mtime` без нужды (оболочка перечитывает его по `-nt`).
pub fn write_env_vars(names: &[String]) {
    let p = crate::paths::runtime_dir().join("env-vars");
    let mut text = names.join("\n");
    if !text.is_empty() {
        text.push('\n');
    }
    if std::fs::read_to_string(&p).is_ok_and(|t| t == text) {
        return;
    }
    let _ = std::fs::create_dir_all(crate::paths::runtime_dir());
    let tmp = p.with_extension(format!("{}.tmp", std::process::id()));
    if std::fs::write(&tmp, text).is_ok() {
        let _ = std::fs::rename(&tmp, &p);
    }
}

/// Обёртка inotify.
pub struct Inotify {
    pub fd: OwnedFd,
    watches: BTreeMap<i32, PathBuf>,
}

/// Событие inotify: каталог наблюдения и имя файла.
#[derive(Debug, Clone)]
pub struct FsEvent {
    pub dir: PathBuf,
    pub name: String,
    pub mask: u32,
}

impl Inotify {
    pub fn new() -> std::io::Result<Inotify> {
        // SAFETY: inotify_init1 возвращает новый дескриптор или -1.
        let fd = unsafe { libc::inotify_init1(libc::IN_NONBLOCK | libc::IN_CLOEXEC) };
        if fd < 0 {
            return Err(std::io::Error::last_os_error());
        }
        Ok(Inotify {
            // SAFETY: fd — только что полученный дескриптор.
            fd: unsafe { OwnedFd::from_raw_fd(fd) },
            watches: BTreeMap::new(),
        })
    }

    /// Наблюдение каталога (создание, запись, переименование, удаление).
    pub fn watch(&mut self, dir: &Path) -> Option<i32> {
        if let Some((&wd, _)) = self.watches.iter().find(|(_, p)| p.as_path() == dir) {
            return Some(wd);
        }
        let c = CString::new(dir.as_os_str().as_encoded_bytes()).ok()?;
        let mask = libc::IN_CLOSE_WRITE
            | libc::IN_MOVED_TO
            | libc::IN_MOVED_FROM
            | libc::IN_CREATE
            | libc::IN_DELETE
            | libc::IN_DELETE_SELF
            | libc::IN_MOVE_SELF;
        use std::os::fd::AsRawFd;
        // SAFETY: путь — корректная C-строка, fd — наш дескриптор inotify.
        let wd = unsafe { libc::inotify_add_watch(self.fd.as_raw_fd(), c.as_ptr(), mask) };
        if wd < 0 {
            return None;
        }
        self.watches.insert(wd, dir.to_path_buf());
        Some(wd)
    }

    pub fn unwatch(&mut self, dir: &Path) {
        use std::os::fd::AsRawFd;
        let wds: Vec<i32> = self
            .watches
            .iter()
            .filter(|(_, p)| p.as_path() == dir)
            .map(|(w, _)| *w)
            .collect();
        for wd in wds {
            // SAFETY: снимаем своё наблюдение.
            unsafe { libc::inotify_rm_watch(self.fd.as_raw_fd(), wd) };
            self.watches.remove(&wd);
        }
    }

    pub fn watched(&self) -> Vec<PathBuf> {
        self.watches.values().cloned().collect()
    }

    /// Читает накопленные события.
    pub fn read(&mut self) -> Vec<FsEvent> {
        use std::os::fd::AsRawFd;
        let mut out = Vec::new();
        let mut buf = [0u8; 8192];
        loop {
            // SAFETY: чтение в локальный буфер его размера.
            let n = unsafe { libc::read(self.fd.as_raw_fd(), buf.as_mut_ptr().cast(), buf.len()) };
            if n <= 0 {
                break;
            }
            let n = n as usize;
            let mut off = 0;
            let hdr = std::mem::size_of::<libc::inotify_event>();
            while off + hdr <= n {
                // SAFETY: ядро пишет целые события; читаем заголовок без выравнивания.
                let ev: libc::inotify_event =
                    unsafe { std::ptr::read_unaligned(buf[off..].as_ptr().cast()) };
                let len = ev.len as usize;
                let name_bytes = &buf[off + hdr..(off + hdr + len).min(n)];
                let name = String::from_utf8_lossy(name_bytes)
                    .trim_end_matches('\0')
                    .to_string();
                if ev.mask & libc::IN_IGNORED != 0 {
                    self.watches.remove(&ev.wd);
                }
                if let Some(dir) = self.watches.get(&ev.wd) {
                    out.push(FsEvent {
                        dir: dir.clone(),
                        name,
                        mask: ev.mask,
                    });
                }
                off += hdr + len;
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rec(program: &str, pid: i32) -> Record {
        parse_record(&format!(
            r#"{{"v":1,"program":"{program}","mode":null,"pid":{pid},"state":"active"}}"#
        ))
        .expect("record")
    }

    #[test]
    fn stack_order() {
        let mut r = Records::default();
        r.put("ble-1.json".into(), rec("ble", 1));
        r.put("yazi-2.json".into(), rec("yazi", 2));
        r.put("nvim-3.json".into(), rec("nvim", 3));
        assert_eq!(r.active(|_| true).map(|x| x.program.as_str()), Some("nvim"));
        r.remove("nvim-3.json");
        assert_eq!(r.active(|_| true).map(|x| x.program.as_str()), Some("yazi"));
        assert_eq!(r.active(|p| p != 2).map(|x| x.program.as_str()), Some("ble"));
        r.put("ble-1.json".into(), rec("ble", 1));
        assert_eq!(r.active(|_| true).map(|x| x.program.as_str()), Some("ble"));
    }

    fn panes_tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("kh-panes-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).expect("tmp");
        d
    }

    #[test]
    fn remove_closed_pane_dir_with_links() {
        let d = panes_tmp("rm");
        std::fs::create_dir_all(d.join("w:p2")).expect("dir");
        std::fs::write(d.join("w:p2/ble-1.json"), "{}").expect("rec");
        std::os::unix::fs::symlink(d.join("w:p2"), d.join("w:p1")).expect("link");
        std::fs::create_dir_all(d.join("w:p3")).expect("other");
        remove_pane_dir_in(&d, "w:p2");
        assert!(std::fs::symlink_metadata(d.join("w:p2")).is_err());
        assert!(std::fs::symlink_metadata(d.join("w:p1")).is_err());
        assert!(d.join("w:p3").is_dir());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn sweep_keeps_live_and_links_to_live() {
        let d = panes_tmp("sweep");
        for n in ["w:p5", "w:p6", "w:p7"] {
            std::fs::create_dir_all(d.join(n)).expect("dir");
        }
        // w:p1 перенесена в w:p5 (жива), w:p2 — в w:p6 (закрыта).
        std::os::unix::fs::symlink(d.join("w:p5"), d.join("w:p1")).expect("link");
        std::os::unix::fs::symlink(d.join("w:p6"), d.join("w:p2")).expect("link");
        let names = pane_dir_names_in(&d);
        // Каталог, появившийся после снимка имён, уборка не трогает.
        std::fs::create_dir_all(d.join("w:p9")).expect("new");
        let live: std::collections::HashSet<String> = ["w:p5", "w:p7"].iter().map(|s| s.to_string()).collect();
        sweep_pane_dirs_in(&d, &names, &live);
        assert!(d.join("w:p5").is_dir());
        assert!(d.join("w:p7").is_dir());
        assert!(d.join("w:p9").is_dir());
        assert!(std::fs::symlink_metadata(d.join("w:p1")).is_ok());
        assert!(std::fs::symlink_metadata(d.join("w:p6")).is_err());
        assert!(std::fs::symlink_metadata(d.join("w:p2")).is_err());
        let _ = std::fs::remove_dir_all(&d);
    }
}
