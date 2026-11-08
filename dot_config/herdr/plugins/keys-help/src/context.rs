//! Разрешение контекста (D5) по записи поставщика, процессам переднего
//! плана, заголовку и экрану панели.

use crate::channel::Record;
use crate::manifest::{Manifest, ScreenRule};

/// Процесс переднего плана панели.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Proc {
    pub pid: i32,
    pub name: String,
    pub argv0: String,
}

impl Proc {
    fn names(&self) -> [&str; 2] {
        [self.name.as_str(), basename(&self.argv0)]
    }
}

/// Признаки цели.
pub struct Facts<'a> {
    pub active: Option<&'a Record>,
    pub procs: &'a [Proc],
    pub shell_pid: Option<i32>,
    pub title: &'a str,
    /// Текст экрана по источнику и числу строк (`None` — не прочитан).
    pub screen: &'a dyn Fn(&str, Option<u32>) -> Option<String>,
}

/// Итог разрешения.
#[derive(Debug, Clone, PartialEq)]
pub struct Resolution {
    /// Индекс манифеста.
    pub manifest: usize,
    pub mode_native: String,
    pub mode: String,
    /// Строка контекста `<программа>[.<режим>]`.
    pub ctx: String,
    /// Команда (имя исполняемого файла).
    pub command: String,
    /// Запись поставщика, если контекст взят из неё или из её команды.
    pub record: Option<Record>,
    /// Процесс программы (для `{pid}` и `/proc/<pid>/environ`).
    pub pid: Option<i32>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Resolved {
    Manifest(Box<Resolution>),
    /// Нет ни манифеста, ни извлекателя; команда, если известна.
    Nothing(Option<String>),
}

pub fn basename(s: &str) -> &str {
    s.rsplit('/').next().unwrap_or(s)
}

/// Первое слово командной строки без присваиваний и обёрток (`sudo`, `env`…).
pub fn command_word(cmdline: &str) -> Option<String> {
    let mut words = cmdline.split_whitespace().peekable();
    while let Some(w) = words.next() {
        let w = w.trim_matches(|c| c == '\'' || c == '"');
        if w.is_empty() {
            continue;
        }
        if w.contains('=') && !w.starts_with('=') && !w.starts_with('-') {
            continue;
        }
        if matches!(w, "sudo" | "env" | "exec" | "command" | "nohup" | "time" | "builtin" | "doas") {
            // Ключи обёртки (`sudo -E`) пропускаются.
            while words.peek().is_some_and(|n| n.starts_with('-')) {
                words.next();
            }
            continue;
        }
        return Some(basename(w).to_string());
    }
    None
}

fn screen_hit(rules: &[ScreenRule], facts: &Facts) -> Option<usize> {
    rules.iter().position(|r| {
        (facts.screen)(&r.source, r.lines).is_some_and(|t| r.regex.is_match(&t))
    })
}

fn config_mode(m: &Manifest, home: &str) -> Option<String> {
    let fc = m.modes.from_config.as_ref()?;
    let path = if let Some(r) = fc.file.strip_prefix("~/") {
        format!("{home}/{r}")
    } else {
        fc.file.clone()
    };
    let text = std::fs::read_to_string(path).ok();
    let value = text
        .as_deref()
        .and_then(|t| t.parse::<toml::Table>().ok())
        .and_then(|t| {
            let mut node = toml::Value::Table(t);
            for part in fc.key.split('.') {
                node = node.get(part)?.clone();
            }
            node.as_str().map(str::to_string)
        });
    match value {
        Some(v) => fc.map.get(&v).cloned().or(Some(v)),
        // Ключ не задан: значение по умолчанию программы — запись `map` с ключом "".
        None => fc.map.get("").cloned(),
    }
}

fn ctx_of(m: &Manifest, command: &str, mode: &str) -> String {
    let program = if m.program == "*" { command } else { m.program.as_str() };
    if mode.is_empty() {
        program.to_string()
    } else {
        format!("{program}.{mode}")
    }
}

fn mode_without_record(m: &Manifest, facts: &Facts, home: &str) -> String {
    if let Some(i) = screen_hit(&m.modes.screen, facts) {
        if let Some(mode) = &m.modes.screen[i].mode {
            return mode.clone();
        }
    }
    if let Some(mode) = config_mode(m, home) {
        return mode;
    }
    m.modes.default.clone().unwrap_or_default()
}

/// Разрешает контекст цели.
pub fn resolve(manifests: &[Manifest], facts: &Facts, home: &str) -> Resolved {
    // Активная запись действует, если её процесс на переднем плане (или
    // процессы переднего плана неизвестны).
    let fg_has = |pid: i32| facts.procs.is_empty() || facts.procs.iter().any(|p| p.pid == pid);
    if let Some(r) = facts.active {
        if r.state == "active" && fg_has(r.pid) {
            if let Some((i, m)) = manifests
                .iter()
                .enumerate()
                .filter(|(_, m)| m.detect.provider.as_deref() == Some(r.program.as_str()))
                .max_by_key(|(i, m)| (m.priority, -(*i as i64)))
            {
                let native = r
                    .mode
                    .clone()
                    .or_else(|| m.modes.default.clone().map(|d| m.modes.native_name(&d)))
                    .unwrap_or_default();
                let mode = m.modes.context_name(&native);
                return Resolved::Manifest(Box::new(Resolution {
                    manifest: i,
                    ctx: ctx_of(m, &r.program, &mode),
                    mode_native: native,
                    mode,
                    command: r.program.clone(),
                    record: Some(r.clone()),
                    pid: Some(r.pid),
                }));
            }
        }
    }
    let rec_cmd: Option<String> = facts
        .active
        .filter(|r| r.state != "active")
        .and_then(|r| r.command.clone());
    let rec_word = rec_cmd.as_deref().and_then(command_word);
    // Кандидаты по команде записи, процессам, заголовку и экрану.
    let mut best: Option<(i64, usize, Option<i32>, String)> = None;
    for (i, m) in manifests.iter().enumerate() {
        if m.detect.fallback {
            continue;
        }
        let mut hit: Option<(Option<i32>, String)> = None;
        if let (Some(word), Some(full)) = (&rec_word, &rec_cmd) {
            if crate::glob::any(&m.detect.shell_commands, word)
                || crate::glob::any(&m.detect.shell_commands, full)
            {
                hit = Some((None, word.clone()));
            }
        }
        if hit.is_none() {
            for p in facts.procs {
                if p.names().iter().any(|n| crate::glob::any(&m.detect.process, n)) {
                    hit = Some((Some(p.pid), p.name.clone()));
                    break;
                }
            }
        }
        if hit.is_none() {
            if let Some(t) = &m.detect.title {
                if t.is_match(facts.title) {
                    hit = Some((None, m.program.clone()));
                }
            }
        }
        if hit.is_none() && screen_hit(&m.detect.screen, facts).is_some() {
            hit = Some((None, m.program.clone()));
        }
        if let Some((pid, cmd)) = hit {
            if best.as_ref().is_none_or(|b| m.priority > b.0) {
                best = Some((m.priority, i, pid, cmd));
            }
        }
    }
    if let Some((_, i, pid, cmd)) = best {
        let m = &manifests[i];
        let mode = mode_without_record(m, facts, home);
        return Resolved::Manifest(Box::new(Resolution {
            manifest: i,
            ctx: ctx_of(m, &cmd, &mode),
            mode_native: m.modes.native_name(&mode),
            mode,
            command: cmd,
            record: facts.active.cloned(),
            pid,
        }));
    }
    // Универсальный извлекатель для команды переднего плана.
    let fg = facts
        .procs
        .iter()
        .find(|p| Some(p.pid) != facts.shell_pid)
        .or_else(|| facts.procs.first());
    let (command, pid) = match (fg, &rec_word) {
        (Some(p), _) => (Some(p.name.clone()), Some(p.pid)),
        (None, Some(w)) => (Some(w.clone()), None),
        (None, None) => (None, None),
    };
    let Some(command) = command else {
        return Resolved::Nothing(None);
    };
    let fallback = manifests
        .iter()
        .enumerate()
        .filter(|(_, m)| m.detect.fallback)
        .max_by_key(|(i, m)| (m.priority, -(*i as i64)));
    match fallback {
        Some((i, m)) => {
            let mode = mode_without_record(m, facts, home);
            Resolved::Manifest(Box::new(Resolution {
                manifest: i,
                ctx: ctx_of(m, &command, &mode),
                mode_native: m.modes.native_name(&mode),
                mode,
                command,
                record: facts.active.cloned(),
                pid,
            }))
        }
        None => Resolved::Nothing(Some(command)),
    }
}

/// Разрешение по строке контекста (`table <контекст>`): манифест с этим
/// `program`, иначе извлекатель для команды.
pub fn from_ctx(manifests: &[Manifest], ctx: &str) -> Option<Resolution> {
    let (program, mode) = match ctx.split_once('.') {
        Some((p, m)) => (p, m),
        None => (ctx, ""),
    };
    let found = manifests
        .iter()
        .enumerate()
        .filter(|(_, m)| m.program == program && !m.detect.fallback)
        .max_by_key(|(i, m)| (m.priority, -(*i as i64)))
        .or_else(|| {
            manifests
                .iter()
                .enumerate()
                .filter(|(_, m)| m.detect.fallback)
                .max_by_key(|(i, m)| (m.priority, -(*i as i64)))
        });
    let (i, m) = found?;
    let mode = if mode.is_empty() {
        m.modes.default.clone().unwrap_or_default()
    } else {
        mode.to_string()
    };
    Some(Resolution {
        manifest: i,
        ctx: ctx_of(m, program, &mode),
        mode_native: m.modes.native_name(&mode),
        mode,
        command: program.to_string(),
        record: None,
        pid: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::channel::parse_record;
    use std::path::Path;

    fn ms() -> Vec<Manifest> {
        let ble = "program = \"ble\"\npriority = 100\n[detect]\nprovider = \"ble\"\n[modes]\ndefault = \"vi_imap\"\n";
        let fzf = "program = \"fzf\"\npriority = 50\n[detect]\nprocess = [\"fzf\"]\nshell_commands = [\"fzf-*\"]\n";
        let gen = "program = \"*\"\npriority = 0\n[detect]\nfallback = true\n[modes]\ndefault = \"generic\"\n";
        vec![
            crate::manifest::parse(ble, Path::new("/m/ble.toml")).expect("ble"),
            crate::manifest::parse(fzf, Path::new("/m/fzf.toml")).expect("fzf"),
            crate::manifest::parse(gen, Path::new("/m/generic.toml")).expect("gen"),
        ]
    }

    fn no_screen(_: &str, _: Option<u32>) -> Option<String> {
        None
    }

    #[test]
    fn record_and_widget() {
        let m = ms();
        let r = parse_record(r#"{"program":"ble","mode":"vi_nmap","pid":10,"state":"active"}"#).expect("r");
        let procs = vec![Proc { pid: 10, name: "bash".into(), argv0: "bash".into() }];
        let f = Facts { active: Some(&r), procs: &procs, shell_pid: Some(10), title: "", screen: &no_screen };
        let Resolved::Manifest(res) = resolve(&m, &f, "/h") else { panic!() };
        assert_eq!(res.ctx, "ble.vi_nmap");

        let w = parse_record(r#"{"program":"ble","mode":"vi_imap","pid":10,"state":"widget","command":"fzf-file-widget"}"#).expect("r");
        let f = Facts { active: Some(&w), procs: &procs, shell_pid: Some(10), title: "", screen: &no_screen };
        let Resolved::Manifest(res) = resolve(&m, &f, "/h") else { panic!() };
        assert_eq!(res.ctx, "fzf");
    }

    #[test]
    fn generic_and_manifest_priority() {
        let m = ms();
        let procs = vec![
            Proc { pid: 10, name: "bash".into(), argv0: "bash".into() },
            Proc { pid: 11, name: "htop".into(), argv0: "/usr/bin/htop".into() },
        ];
        let f = Facts { active: None, procs: &procs, shell_pid: Some(10), title: "", screen: &no_screen };
        let Resolved::Manifest(res) = resolve(&m, &f, "/h") else { panic!() };
        assert_eq!(res.ctx, "htop.generic");
        let procs = vec![Proc { pid: 12, name: "fzf".into(), argv0: "fzf".into() }];
        let f = Facts { active: None, procs: &procs, shell_pid: Some(10), title: "", screen: &no_screen };
        let Resolved::Manifest(res) = resolve(&m, &f, "/h") else { panic!() };
        assert_eq!(res.ctx, "fzf");
    }

    #[test]
    fn words() {
        assert_eq!(command_word("FOO=1 sudo -E /usr/bin/htop -d 1").as_deref(), Some("htop"));
        assert_eq!(command_word("tv").as_deref(), Some("tv"));
    }
}
