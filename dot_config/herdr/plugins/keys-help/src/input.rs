//! Состояние строки ввода цели для просмотрщика (D17): файлы `.line`,
//! `.words`, `.cands` активной записи, команды `PATH`, параметры первого слова
//! (разбор `man` и `--help` с кешем на диске по входам D7), ячейки раздела
//! «дополнение». Всё обновляется по событиям inotify и pidfd, без опроса.

use std::collections::{BTreeSet, HashMap, HashSet};
use std::path::{Path, PathBuf};

use crate::cursor::{self, Cands, Line, Opt, Pos, Word};
use crate::entry::Entry;

/// Предел ячеек раздела «дополнение».
pub const MAX_COMPLETION: usize = 20;

/// Префикс файлов-отметок открытых панелей в каталоге цели: у каждого
/// просмотрщика своя отметка `viewer.<pid>` (D17).
pub const VIEWER_MARK_PREFIX: &str = "viewer.";

/// Имя отметки этого просмотрщика.
pub fn mark_name() -> String {
    format!("{VIEWER_MARK_PREFIX}{}", std::process::id())
}

#[derive(Default)]
pub struct Input {
    dir: PathBuf,
    /// Имя активной записи без `.json` (`ble-123`).
    stem: Option<String>,
    pub line: Option<Line>,
    pub words: Vec<Word>,
    pub cands: Option<Cands>,
    /// Каталоги `PATH` процесса оболочки и команды в них.
    pub path_dirs: Vec<PathBuf>,
    path_cmds: BTreeSet<String>,
    path_pid: Option<i32>,
    /// Параметры команд: память; `None` — разбор не дал параметров.
    opts: HashMap<String, Vec<Opt>>,
    /// Команды, для которых уже идёт или закончилось извлечение.
    asked: HashSet<String>,
}

/// Шаг извлечения параметров: команда для запуска.
pub struct OptNeed {
    pub command: String,
    pub argv: Vec<String>,
}

/// Удаляет отметки завершившихся просмотрщиков (убит без уборки): иначе
/// модуль оболочки писал бы файлы для панели, которой нет. Возвращает число
/// живых отметок.
fn sweep_marks(dir: &Path) -> usize {
    let Ok(rd) = std::fs::read_dir(dir) else { return 0 };
    let mut n = 0;
    for e in rd.flatten() {
        let name = e.file_name().to_string_lossy().to_string();
        let Some(pid) = name.strip_prefix(VIEWER_MARK_PREFIX) else { continue };
        let alive = pid
            .parse::<i32>()
            .is_ok_and(|p| std::path::Path::new(&format!("/proc/{p}")).exists());
        if alive {
            n += 1;
        } else {
            let _ = std::fs::remove_file(e.path());
        }
    }
    n
}

/// Файл строки ввода; пустой файл — данных нет. Устаревшие данные модуль
/// оболочки обнуляет сам: изменение строки без наблюдения очищает файл (D17).
fn read(dir: &Path, name: &str) -> Option<String> {
    std::fs::read_to_string(dir.join(name)).ok().filter(|t| !t.is_empty())
}

/// Создание своей отметки в каталоге цели.
pub fn create_mark(dir: &Path) {
    sweep_marks(dir);
    let _ = std::fs::write(dir.join(mark_name()), b"");
}

/// Снятие своей отметки. Файлы строки ввода остаются: при возврате на цель
/// без ввода разделы показываются по ним сразу; удаляются они только уборкой
/// каталога закрытой панели.
pub fn remove_mark(dir: &Path) {
    let _ = std::fs::remove_file(dir.join(mark_name()));
    // Отметка прежнего формата (общая для всех просмотрщиков).
    let _ = std::fs::remove_file(dir.join("viewer"));
    sweep_marks(dir);
}

/// Исполняемый обычный файл (по ссылкам).
fn is_exec(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(p).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

#[derive(serde::Serialize, serde::Deserialize)]
struct OptCache {
    key: String,
    opts: Vec<Opt>,
}

fn opt_cache_path(cmd: &str) -> PathBuf {
    crate::paths::cache_dir()
        .join("options")
        .join(format!("{}.json", cmd.replace('/', "_")))
}

impl Input {
    /// Выбор активной записи; при смене — перечитывание файлов.
    pub fn set_active(&mut self, dir: &Path, stem: Option<String>) -> bool {
        if self.dir == dir && self.stem == stem {
            return false;
        }
        self.dir = dir.to_path_buf();
        self.stem = stem;
        self.line = None;
        self.words.clear();
        self.cands = None;
        for ext in ["line", "words", "cands"] {
            self.load(ext);
        }
        true
    }

    fn load(&mut self, ext: &str) {
        let Some(stem) = &self.stem else { return };
        let text = read(&self.dir, &format!("{stem}.{ext}"));
        match ext {
            "line" => self.line = text.as_deref().and_then(cursor::parse_line),
            "words" => self.words = text.as_deref().map(cursor::parse_words).unwrap_or_default(),
            "cands" => self.cands = text.as_deref().map(cursor::parse_cands),
            _ => {}
        }
    }

    /// Событие inotify в каталоге цели: `true`, если изменился файл строки ввода.
    pub fn on_file(&mut self, name: &str) -> bool {
        let Some(stem) = &self.stem else { return false };
        let Some(ext) = name.strip_prefix(stem.as_str()).and_then(|r| r.strip_prefix('.')) else {
            return false;
        };
        if !matches!(ext, "line" | "words" | "cands") {
            return false;
        }
        let ext = ext.to_string();
        self.load(&ext);
        true
    }

    /// Позиция курсора, если строка известна и не пуста.
    pub fn pos(&self) -> Option<Pos> {
        let p = Pos::of(self.line.as_ref()?);
        (!p.blank).then_some(p)
    }

    /// Каталоги `PATH` оболочки `pid`: `Some((старые, новые))` при изменении.
    pub fn refresh_path(&mut self, pid: Option<i32>) -> Option<(Vec<PathBuf>, Vec<PathBuf>)> {
        if pid == self.path_pid && pid.is_some() {
            return None;
        }
        self.path_pid = pid;
        let path = pid
            .and_then(|p| std::fs::read(format!("/proc/{p}/environ")).ok())
            .and_then(|b| {
                b.split(|&c| c == 0)
                    .find_map(|i| i.strip_prefix(b"PATH=").map(|v| String::from_utf8_lossy(v).to_string()))
            })
            .unwrap_or_default();
        let mut dirs: Vec<PathBuf> = Vec::new();
        for d in path.split(':').filter(|d| !d.is_empty()) {
            let p = PathBuf::from(d);
            if p.is_dir() && !dirs.contains(&p) {
                dirs.push(p);
            }
        }
        if dirs == self.path_dirs {
            return None;
        }
        let old = std::mem::replace(&mut self.path_dirs, dirs.clone());
        self.rebuild_path();
        Some((old, dirs))
    }

    /// Список команд по каталогам `PATH` (при смене набора каталогов).
    pub fn rebuild_path(&mut self) {
        let mut cmds = BTreeSet::new();
        for d in &self.path_dirs {
            let Ok(rd) = std::fs::read_dir(d) else { continue };
            for e in rd.flatten() {
                if is_exec(&e.path()) {
                    cmds.insert(e.file_name().to_string_lossy().to_string());
                }
            }
        }
        self.path_cmds = cmds;
    }

    /// Событие inotify об имени `name` в каталоге `PATH`: команда
    /// добавляется или снимается по наличию исполняемого файла с этим именем
    /// в любом из каталогов `PATH` — без пересканирования каталогов.
    pub fn on_path_entry(&mut self, name: &str) {
        if name.is_empty() || name.contains('/') {
            return;
        }
        if self.path_dirs.iter().any(|d| is_exec(&d.join(name))) {
            self.path_cmds.insert(name.to_string());
        } else {
            self.path_cmds.remove(name);
        }
    }

    pub fn has_command(&self, name: &str) -> bool {
        self.path_cmds.contains(name)
    }

    pub fn is_path_dir(&self, dir: &Path) -> bool {
        self.path_dirs.iter().any(|d| d == dir)
    }

    /// Параметры команды из кеша на диске (ключ входов D7).
    fn opts_from_disk(&mut self, cmd: &str) -> bool {
        let key = crate::engine::disk_key(cmd, None);
        let Some(c) = std::fs::read_to_string(opt_cache_path(cmd))
            .ok()
            .and_then(|t| serde_json::from_str::<OptCache>(&t).ok())
        else {
            return false;
        };
        if c.key != key {
            return false;
        }
        self.opts.insert(cmd.to_string(), c.opts);
        true
    }

    /// Результат команды извлечения. `Some(argv)` — следующий шаг (`--help`
    /// после `man` без параметров).
    pub fn opts_done(&mut self, cmd: &str, argv: &[String], out: &str) -> Option<Vec<String>> {
        let opts = cursor::parse_options(out);
        let from_man = argv.first().is_some_and(|a| a == "man");
        if opts.is_empty() && from_man {
            return Some(vec![cmd.to_string(), "--help".to_string()]);
        }
        let c = OptCache {
            key: crate::engine::disk_key(cmd, None),
            opts: opts.clone(),
        };
        let p = opt_cache_path(cmd);
        if let Some(d) = p.parent() {
            let _ = std::fs::create_dir_all(d);
        }
        if let Ok(t) = serde_json::to_string(&c) {
            let tmp = p.with_extension(format!("json.{}.tmp", std::process::id()));
            if std::fs::write(&tmp, t).is_ok() {
                let _ = std::fs::rename(&tmp, &p);
            }
        }
        self.opts.insert(cmd.to_string(), opts);
        None
    }

    /// Ячейки раздела «дополнение» и, если нужны параметры первого слова,
    /// которых ещё нет, — команда их извлечения.
    pub fn completion(&mut self) -> (Vec<Entry>, Option<OptNeed>) {
        let Some(pos) = self.pos() else {
            return (Vec::new(), None);
        };
        let word = pos.word.clone();
        if word.is_empty() {
            return (Vec::new(), None);
        }
        let mut out: Vec<Entry> = Vec::new();
        let mut seen: HashSet<String> = HashSet::new();
        let mut push = |out: &mut Vec<Entry>, key: &str, desc: String, full: &str, kind: &str, source: &str| {
            if out.len() >= MAX_COMPLETION || !seen.insert(key.to_string()) {
                return;
            }
            out.push(Entry {
                key: key.to_string(),
                desc,
                desc_full: full.to_string(),
                group: crate::view::COMPLETION_TITLE.to_string(),
                origin: kind.to_string(),
                action: kind.to_string(),
                source: source.to_string(),
                raw: full.to_string(),
            });
        };
        let short = |s: &str| crate::shorten::shorten(s);
        for w in self.words.iter().filter(|w| w.kind == "sabbrev" && w.name.starts_with(&word)) {
            push(&mut out, &w.name, format!("→ {}", short(&w.value)), &w.value, "аббревиатура", "ble-sabbrev");
        }
        if let Some(c) = &self.cands {
            if c.compv == word {
                for cw in &c.words {
                    push(&mut out, cw, "кандидат".to_string(), cw, "кандидат", "ble");
                }
            }
        }
        let mut need = None;
        if pos.word_index == 0 {
            for w in self.words.iter().filter(|w| w.kind == "alias" && w.name.starts_with(&word)) {
                push(&mut out, &w.name, format!("= {}", short(&w.value)), &w.value, "псевдоним", "alias");
            }
            for w in self.words.iter().filter(|w| w.kind == "function" && w.name.starts_with(&word)) {
                push(&mut out, &w.name, "функция".to_string(), "", "функция", "function");
            }
            for c in self.path_cmds.range(word.clone()..) {
                if !c.starts_with(&word) || out.len() >= MAX_COMPLETION {
                    break;
                }
                push(&mut out, c, "команда".to_string(), "", "команда", "PATH");
            }
        } else if let Some(cmd) = self.first_word() {
            if !self.opts.contains_key(&cmd) && !self.opts_from_disk(&cmd) && self.path_cmds.contains(&cmd) && self.asked.insert(cmd.clone()) {
                need = Some(OptNeed {
                    argv: vec!["man".to_string(), "-P".to_string(), "cat".to_string(), cmd.clone()],
                    command: cmd.clone(),
                });
            }
            if let Some(opts) = self.opts.get(&cmd) {
                for o in opts {
                    if let Some(n) = o.names.iter().find(|n| n.starts_with(&word)) {
                        let full = o.desc.clone();
                        push(&mut out, n, short(&full), &full, "параметр", &cmd);
                    }
                }
            }
        }
        (out, need)
    }

    /// Первое слово текущей команды строки (до курсора).
    fn first_word(&self) -> Option<String> {
        let line = self.line.as_ref()?;
        let before: String = line.text.chars().take(line.point).collect();
        let start = before
            .rfind([';', '|', '&', '\n'])
            .map(|i| i + 1)
            .unwrap_or(0);
        before[start..].split_whitespace().next().map(str::to_string)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("kh-input-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).expect("tmp");
        d
    }

    #[test]
    fn completion_sources() {
        let d = tmp("compl");
        create_mark(&d);
        std::fs::write(d.join("ble-1.line"), "2\ngs").expect("line");
        std::fs::write(d.join("ble-1.words"), "sabbrev\tgs\tgit status\nalias\tgsw\tgit switch\nfunction\tgsx\t\n").expect("words");
        std::fs::write(d.join("ble-1.cands"), "gs\ngsutil\n").expect("cands");
        let mut i = Input::default();
        i.set_active(&d, Some("ble-1".into()));
        let (c, need) = i.completion();
        assert!(need.is_none());
        let keys: Vec<&str> = c.iter().map(|e| e.key.as_str()).collect();
        assert_eq!(keys, vec!["gs", "gsutil", "gsw", "gsx"]);
        assert_eq!(c[0].desc, "→ git status");
        // Изменение строки по событию файла.
        std::fs::write(d.join("ble-1.line"), "0\ngs").expect("line");
        assert!(i.on_file("ble-1.line"));
        assert!(i.completion().0.is_empty());
        assert!(!i.on_file("ble-2.line"));
        remove_mark(&d);
        assert!(d.join("ble-1.line").exists() && !d.join(mark_name()).exists());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn marks_per_viewer() {
        let d = tmp("marks");
        create_mark(&d);
        // Отметка другого живого просмотрщика (pid 1 жив всегда) и отметка
        // завершившегося процесса.
        std::fs::write(d.join("viewer.1"), "").expect("other");
        std::fs::write(d.join("viewer.999999999"), "").expect("dead");
        std::fs::write(d.join("ble-1.line"), "0\nx").expect("line");
        std::fs::write(d.join("ble-1.cands"), "").expect("cands");
        remove_mark(&d);
        assert!(!d.join(mark_name()).exists());
        assert!(d.join("viewer.1").exists(), "чужая отметка остаётся");
        assert!(!d.join("viewer.999999999").exists(), "отметка мёртвого процесса снята");
        assert!(d.join("ble-1.line").exists(), "файлы строки ввода остаются");
        // Возврат на цель: файлы читаются сразу, пустой — нет данных.
        let mut i = Input::default();
        i.set_active(&d, Some("ble-1".into()));
        assert!(i.line.is_some());
        assert!(i.cands.is_none());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn path_entry_incremental() {
        use std::os::unix::fs::PermissionsExt;
        let a = tmp("path-a");
        let b = tmp("path-b");
        let mut i = Input { path_dirs: vec![a.clone(), b.clone()], ..Default::default() };
        i.rebuild_path();
        assert!(!i.has_command("kh-x"));
        let mk = |d: &Path| {
            let p = d.join("kh-x");
            std::fs::write(&p, "").expect("file");
            std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).expect("chmod");
        };
        mk(&a);
        i.on_path_entry("kh-x");
        assert!(i.has_command("kh-x"));
        mk(&b);
        std::fs::remove_file(a.join("kh-x")).expect("rm");
        i.on_path_entry("kh-x");
        assert!(i.has_command("kh-x"), "есть во втором каталоге");
        std::fs::set_permissions(b.join("kh-x"), std::fs::Permissions::from_mode(0o644)).expect("chmod");
        i.on_path_entry("kh-x");
        assert!(!i.has_command("kh-x"), "снят бит исполнения (IN_ATTRIB)");
        let _ = std::fs::remove_dir_all(&a);
        let _ = std::fs::remove_dir_all(&b);
    }
}
