//! Таблица для разрешённого контекста: подстановки, кеш в памяти (D6)
//! и кеш извлекателя на диске по входам (D7).

use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::context::Resolution;
use crate::entry::Entry;
use crate::extract::{self, Build, Built, FileStamp, Outputs, Subst};
use crate::manifest::Manifest;

pub struct Engine {
    pub manifests: Vec<Manifest>,
    pub errors: Vec<String>,
    pub outputs: Outputs,
    cache: HashMap<String, (Vec<FileStamp>, Vec<Entry>)>,
}

/// Окружение процесса из `/proc/<pid>/environ`.
fn proc_environ(pid: i32) -> BTreeMap<String, String> {
    let mut m = BTreeMap::new();
    if let Ok(b) = std::fs::read(format!("/proc/{pid}/environ")) {
        for item in b.split(|&c| c == 0) {
            let s = String::from_utf8_lossy(item);
            if let Some((k, v)) = s.split_once('=') {
                m.insert(k.to_string(), v.to_string());
            }
        }
    }
    m
}

#[derive(Serialize, Deserialize)]
struct DiskCache {
    key: String,
    files: Vec<(PathBuf, Option<i128>)>,
    entries: Vec<Entry>,
}

fn stamps_valid(files: &[FileStamp]) -> bool {
    files.iter().all(|(p, t)| extract::mtime_ns(p) == *t)
}

/// Путь исполняемого файла команды: `/proc/<pid>/exe` или поиск по `PATH`.
fn exe_path(command: &str, pid: Option<i32>) -> Option<PathBuf> {
    if let Some(pid) = pid {
        if let Ok(p) = std::fs::read_link(format!("/proc/{pid}/exe")) {
            return Some(p);
        }
    }
    if command.contains('/') {
        return Some(PathBuf::from(command));
    }
    let path = std::env::var("PATH").unwrap_or_default();
    path.split(':')
        .map(|d| Path::new(d).join(command))
        .find(|p| p.is_file())
}

/// Время изменения man-страницы команды (разделы 1, 6, 8).
fn man_mtime(command: &str) -> Option<i128> {
    let mut roots: Vec<String> = std::env::var("MANPATH")
        .unwrap_or_default()
        .split(':')
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .collect();
    roots.extend(["/usr/share/man".to_string(), "/usr/local/share/man".to_string()]);
    for r in roots {
        for sec in ["man1", "man6", "man8"] {
            let dir = Path::new(&r).join(sec);
            let Ok(rd) = std::fs::read_dir(&dir) else { continue };
            for e in rd.flatten() {
                let n = e.file_name().to_string_lossy().to_string();
                if n.starts_with(&format!("{command}.")) {
                    return extract::mtime_ns(&e.path());
                }
            }
        }
    }
    None
}

/// Ключ входов извлекателя: путь, `mtime` и размер исполняемого файла, `mtime` man-страницы.
pub fn disk_key(command: &str, pid: Option<i32>) -> String {
    use std::os::unix::fs::MetadataExt;
    let exe = exe_path(command, pid);
    let (mt, size) = exe
        .as_ref()
        .and_then(|p| std::fs::metadata(p).ok())
        .map(|m| (m.mtime() as i128 * 1_000_000_000 + m.mtime_nsec() as i128, m.size()))
        .unwrap_or((0, 0));
    format!(
        "{}|{mt}|{size}|{:?}",
        exe.map(|p| p.display().to_string()).unwrap_or_default(),
        man_mtime(command)
    )
}

impl Engine {
    pub fn load(dirs: &[PathBuf]) -> Engine {
        let (manifests, errors) = crate::manifest::load_dirs(dirs);
        Engine {
            manifests,
            errors,
            outputs: Outputs::new(),
            cache: HashMap::new(),
        }
    }

    /// Перечитывает манифесты (изменение каталога манифестов); кеш сбрасывается.
    pub fn reload(&mut self, dirs: &[PathBuf]) {
        let (manifests, errors) = crate::manifest::load_dirs(dirs);
        self.manifests = manifests;
        self.errors = errors;
        self.cache.clear();
        self.outputs.clear();
    }

    /// Имена переменных окружения для файла `env-vars`.
    pub fn env_names(&self) -> Vec<String> {
        let mut v: Vec<String> = self.manifests.iter().flat_map(|m| m.env_names()).collect();
        v.sort();
        v.dedup();
        v
    }

    /// Подстановки для разрешения.
    pub fn subst(&self, res: &Resolution) -> Subst {
        let m = &self.manifests[res.manifest];
        let mut env = BTreeMap::new();
        let names = m.env_names();
        if !names.is_empty() {
            let procenv = res.pid.map(proc_environ).unwrap_or_default();
            for n in names {
                let v = res
                    .record
                    .as_ref()
                    .and_then(|r| r.env.get(&n).cloned())
                    .or_else(|| procenv.get(&n).cloned())
                    .or_else(|| std::env::var(&n).ok());
                if let Some(v) = v {
                    env.insert(n, v);
                }
            }
        }
        Subst {
            mode_native: res.mode_native.clone(),
            mode: res.mode.clone(),
            record: res.record.as_ref().map(|r| r.fields()).unwrap_or_default(),
            env,
            command: res.command.clone(),
            pid: res.pid,
            home: crate::paths::home(),
        }
    }

    fn mem_key(&self, res: &Resolution, sub: &Subst) -> String {
        format!("{}|{}", self.manifests[res.manifest].path.display(), sub.cache_key())
    }

    fn disk_path(&self, res: &Resolution) -> PathBuf {
        let m = &self.manifests[res.manifest];
        crate::paths::cache_dir()
            .join(&m.stem)
            .join(format!("{}.json", res.command.replace('/', "_")))
    }

    /// Готовая таблица из кеша или очередной шаг построения.
    pub fn step(&mut self, res: &Resolution) -> Build {
        let sub = self.subst(res);
        let key = self.mem_key(res, &sub);
        if let Some((files, entries)) = self.cache.get(&key) {
            if stamps_valid(files) {
                return Build::Done(Built {
                    entries: entries.clone(),
                    files: files.clone(),
                });
            }
        }
        let m = &self.manifests[res.manifest];
        if m.detect.fallback {
            let dk = disk_key(&res.command, res.pid);
            if let Some(dc) = std::fs::read_to_string(self.disk_path(res))
                .ok()
                .and_then(|t| serde_json::from_str::<DiskCache>(&t).ok())
            {
                if dc.key == dk && stamps_valid(&dc.files) {
                    self.cache.insert(key, (dc.files.clone(), dc.entries.clone()));
                    return Build::Done(Built {
                        entries: dc.entries,
                        files: dc.files,
                    });
                }
            }
        }
        let b = extract::build(m, &sub, &self.outputs);
        if let Build::Done(built) = &b {
            self.cache
                .insert(key, (built.files.clone(), built.entries.clone()));
            if m.detect.fallback {
                let dc = DiskCache {
                    key: disk_key(&res.command, res.pid),
                    files: built.files.clone(),
                    entries: built.entries.clone(),
                };
                let p = self.disk_path(res);
                if let Some(d) = p.parent() {
                    let _ = std::fs::create_dir_all(d);
                }
                if let Ok(t) = serde_json::to_string(&dc) {
                    let tmp = p.with_extension(format!("json.{}.tmp", std::process::id()));
                    if std::fs::write(&tmp, t).is_ok() {
                        let _ = std::fs::rename(&tmp, &p);
                    }
                }
            }
        }
        b
    }

    /// Полное построение с синхронным запуском команд (`table`).
    pub fn build_blocking(&mut self, res: &Resolution) -> Built {
        loop {
            match self.step(res) {
                Build::Done(b) => return b,
                Build::Need(argv) => {
                    let out = crate::cmdrun::run_blocking(&argv);
                    self.outputs.insert(argv, out);
                }
            }
        }
    }
}
