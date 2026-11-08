//! Манифест программы (D6): распознавание, режимы, источники таблицы,
//! описания, группы и происхождение. Ядро знает только виды источников и
//! формат записи; имена программ живут в манифестах.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use regex::Regex;
use serde::Deserialize;

#[derive(Debug, Deserialize, Default)]
#[serde(default)]
struct ManifestFile {
    program: String,
    priority: i64,
    origins: Vec<String>,
    env: Vec<String>,
    first_nonempty: Option<bool>,
    detect: DetectFile,
    modes: ModesFile,
    source: Vec<SourceSpec>,
    key: KeyFile,
    describe: Vec<toml::Table>,
    group: Vec<toml::Table>,
    origin: Vec<toml::Table>,
    view: toml::Table,
    applies: Vec<AppliesFile>,
}

#[derive(Debug, Deserialize, Default)]
#[serde(default)]
struct AppliesFile {
    modes: Vec<String>,
    action: String,
    when: String,
}

/// Правило применимости `[[applies]]` (D17): записи с подходящим действием
/// в подходящем режиме переносятся в раздел «по позиции курсора» при истинном
/// `when` и приглушаются при ложном.
#[derive(Debug, Clone)]
pub struct Applies {
    pub modes: Vec<String>,
    pub action: Regex,
    pub when: crate::cursor::When,
}

impl Applies {
    pub fn matches(&self, action: &str, mode: &[&str]) -> bool {
        (self.modes.is_empty()
            || self
                .modes
                .iter()
                .any(|m| m == "*" || mode.contains(&m.as_str())))
            && self.action.is_match(action)
    }
}

#[derive(Debug, Deserialize, Default)]
#[serde(default)]
struct DetectFile {
    provider: Option<String>,
    process: Vec<String>,
    shell_commands: Vec<String>,
    title: Option<String>,
    screen: Vec<ScreenFile>,
    fallback: bool,
}

#[derive(Debug, Deserialize, Default, Clone)]
#[serde(default)]
struct ScreenFile {
    source: Option<String>,
    lines: Option<u32>,
    regex: String,
    mode: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
#[serde(default)]
struct ModesFile {
    default: Option<String>,
    names: BTreeMap<String, String>,
    from_config: Option<FromConfig>,
    screen: Vec<ScreenFile>,
}

#[derive(Debug, Deserialize, Default, Clone)]
#[serde(default)]
pub struct FromConfig {
    pub file: String,
    pub key: String,
    pub map: BTreeMap<String, String>,
}

#[derive(Debug, Deserialize, Default)]
#[serde(default)]
struct KeyFile {
    map: BTreeMap<String, String>,
}

/// Источник таблицы как он записан в манифесте.
#[derive(Debug, Deserialize, Clone)]
#[serde(default)]
pub struct SourceSpec {
    pub modes: Vec<String>,
    pub kind: String,
    pub file: Option<String>,
    pub path: Option<String>,
    pub command: Option<Vec<String>>,
    pub env: Option<String>,
    pub text: Option<String>,
    pub regex: Option<String>,
    pub sections: Option<String>,
    /// Разделитель клавиш в захвате `key` (регулярное выражение): каждая часть — своя запись.
    pub split: Option<String>,
    pub unquote: Vec<String>,
    pub skip: BTreeMap<String, String>,
    pub on_conflict: Option<String>,
    pub tables: Vec<String>,
    pub arrays: Vec<String>,
    pub layout: Option<String>,
    pub key_field: Option<String>,
    pub action_field: Option<String>,
    pub desc_field: Option<String>,
    pub group_field: Option<String>,
    pub origin_field: Option<String>,
    pub raw_fields: Vec<String>,
    pub replace_if: Option<String>,
    pub pointer: Option<String>,
    pub entries: Vec<toml::Table>,
    pub group: Option<String>,
    pub origin: Option<String>,
}

impl Default for SourceSpec {
    fn default() -> Self {
        Self {
            modes: vec!["*".to_string()],
            kind: String::new(),
            file: None,
            path: None,
            command: None,
            env: None,
            text: None,
            regex: None,
            sections: None,
            split: None,
            unquote: Vec::new(),
            skip: BTreeMap::new(),
            on_conflict: None,
            tables: Vec::new(),
            arrays: Vec::new(),
            layout: None,
            key_field: None,
            action_field: None,
            desc_field: None,
            group_field: None,
            origin_field: None,
            raw_fields: Vec::new(),
            replace_if: None,
            pointer: None,
            entries: Vec::new(),
            group: None,
            origin: None,
        }
    }
}

/// Вид источника.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Regex,
    Toml,
    Json,
    Static,
}

/// Правило экрана: регулярное выражение по содержимому панели.
#[derive(Debug, Clone)]
pub struct ScreenRule {
    pub source: String,
    pub lines: Option<u32>,
    pub regex: Regex,
    pub mode: Option<String>,
}

/// Правило `[[describe]]`, `[[group]]` или `[[origin]]`: условия по полям
/// записи и захватам источника, результат — значения полей.
#[derive(Debug, Clone)]
pub struct Rule {
    pub matchers: Vec<(String, Regex)>,
    pub modes: Vec<String>,
    pub result: BTreeMap<String, String>,
}

impl Rule {
    /// Подходит ли правило: все условия совпали (поле без значения — пустая строка).
    pub fn matches(&self, fields: &BTreeMap<String, String>, mode: &[&str]) -> bool {
        if !self.modes.is_empty() && !mode.iter().any(|m| crate::glob::any(&self.modes, m)) {
            return false;
        }
        self.matchers.iter().all(|(field, re)| {
            let v = fields.get(field).map(String::as_str).unwrap_or("");
            re.is_match(v)
        })
    }
}

/// Скомпилированный источник.
#[derive(Debug, Clone)]
pub struct Source {
    pub spec: SourceSpec,
    pub kind: Kind,
    pub regex: Option<Regex>,
    pub sections: Option<Regex>,
    pub split: Option<Regex>,
    pub skip: Vec<(String, Regex)>,
    pub keep: bool,
}

#[derive(Debug, Clone, Default)]
pub struct Detect {
    pub provider: Option<String>,
    pub process: Vec<String>,
    pub shell_commands: Vec<String>,
    pub title: Option<Regex>,
    pub screen: Vec<ScreenRule>,
    pub fallback: bool,
}

#[derive(Debug, Clone, Default)]
pub struct Modes {
    pub default: Option<String>,
    /// Родное имя режима → имя в контексте.
    pub names: BTreeMap<String, String>,
    pub from_config: Option<FromConfig>,
    pub screen: Vec<ScreenRule>,
}

impl Modes {
    /// Имя режима в контексте по родному имени.
    pub fn context_name(&self, native: &str) -> String {
        self.names
            .get(native)
            .cloned()
            .unwrap_or_else(|| native.to_string())
    }

    /// Родное имя по имени в контексте (обратный поиск в `names`).
    pub fn native_name(&self, ctx: &str) -> String {
        if self.names.contains_key(ctx) {
            return ctx.to_string();
        }
        self.names
            .iter()
            .find(|(_, v)| v.as_str() == ctx)
            .map(|(k, _)| k.clone())
            .unwrap_or_else(|| ctx.to_string())
    }
}

/// Скомпилированный манифест.
#[derive(Debug, Clone)]
pub struct Manifest {
    pub path: PathBuf,
    pub dir: PathBuf,
    pub file_name: String,
    pub stem: String,
    pub program: String,
    pub priority: i64,
    pub origins: Vec<String>,
    pub env: Vec<String>,
    pub first_nonempty: bool,
    pub detect: Detect,
    pub modes: Modes,
    pub sources: Vec<Source>,
    pub key_map: Vec<(String, String)>,
    pub describe: Vec<Rule>,
    pub group: Vec<Rule>,
    pub origin: Vec<Rule>,
    /// Раздел `[view]`: умолчания представления программы (D15).
    pub view: crate::view::Level,
    /// Порядок разделов по происхождению (`[view] origin_order`).
    pub origin_order: Vec<String>,
    pub applies: Vec<Applies>,
}

impl Manifest {
    /// Значение поля `source` записей манифеста.
    pub fn source_label(&self) -> String {
        if self.detect.fallback {
            self.stem.clone()
        } else {
            format!("manifest:{}", self.file_name)
        }
    }

    /// Происхождение по умолчанию.
    pub fn default_origin(&self) -> String {
        if self.detect.fallback {
            return self.stem.clone();
        }
        self.origins
            .first()
            .cloned()
            .unwrap_or_else(|| self.program.clone())
    }

    /// Имена переменных окружения, которые нужны подстановкам и источникам.
    pub fn env_names(&self) -> Vec<String> {
        let mut out: Vec<String> = self.env.clone();
        let re = Regex::new(r"\{env\.([A-Za-z_][A-Za-z0-9_]*)\}").expect("regex");
        for s in &self.sources {
            if let Some(e) = &s.spec.env {
                out.push(e.clone());
            }
            let mut texts: Vec<&str> = Vec::new();
            for t in [&s.spec.file, &s.spec.path, &s.spec.text]
                .into_iter()
                .flatten()
            {
                texts.push(t);
            }
            if let Some(c) = &s.spec.command {
                texts.extend(c.iter().map(String::as_str));
            }
            for t in texts {
                for c in re.captures_iter(t) {
                    out.push(c[1].to_string());
                }
            }
        }
        out.sort();
        out.dedup();
        out
    }
}

fn compile(re: &str, what: &str) -> Result<Regex, String> {
    regex::RegexBuilder::new(re)
        .multi_line(true)
        .build()
        .map_err(|e| format!("{what}: {e}"))
}

fn screen_rules(list: &[ScreenFile], what: &str) -> Result<Vec<ScreenRule>, String> {
    list.iter()
        .map(|s| {
            Ok(ScreenRule {
                source: s.source.clone().unwrap_or_else(|| "visible".to_string()),
                lines: s.lines,
                regex: compile(&s.regex, what)?,
                mode: s.mode.clone(),
            })
        })
        .collect()
}

fn rules(list: &[toml::Table], result_fields: &[&str], what: &str) -> Result<Vec<Rule>, String> {
    let mut out = Vec::new();
    for (i, t) in list.iter().enumerate() {
        let mut rule = Rule {
            matchers: Vec::new(),
            modes: Vec::new(),
            result: BTreeMap::new(),
        };
        for (k, v) in t {
            if k == "modes" {
                rule.modes = match v {
                    toml::Value::Array(a) => a
                        .iter()
                        .filter_map(|x| x.as_str().map(str::to_string))
                        .collect(),
                    toml::Value::String(s) => vec![s.clone()],
                    _ => return Err(format!("{what}[{i}].modes: нужен список строк")),
                };
                continue;
            }
            let Some(s) = v.as_str() else {
                return Err(format!("{what}[{i}].{k}: нужна строка"));
            };
            if result_fields.contains(&k.as_str()) {
                rule.result.insert(k.clone(), s.to_string());
            } else {
                rule.matchers
                    .push((k.clone(), compile(s, &format!("{what}[{i}].{k}"))?));
            }
        }
        out.push(rule);
    }
    Ok(out)
}

/// Известные поля разделов манифеста (для предупреждений об опечатках).
const KNOWN: &[(&str, &[&str])] = &[
    (
        "",
        &[
            "program",
            "priority",
            "origins",
            "env",
            "first_nonempty",
            "detect",
            "modes",
            "source",
            "key",
            "describe",
            "group",
            "origin",
            "view",
            "applies",
        ],
    ),
    (
        "detect",
        &[
            "provider",
            "process",
            "shell_commands",
            "title",
            "screen",
            "fallback",
        ],
    ),
    ("modes", &["default", "names", "from_config", "screen"]),
    ("key", &["map"]),
    (
        "source",
        &[
            "modes",
            "kind",
            "file",
            "path",
            "command",
            "env",
            "text",
            "regex",
            "sections",
            "split",
            "unquote",
            "skip",
            "on_conflict",
            "tables",
            "arrays",
            "layout",
            "key_field",
            "action_field",
            "desc_field",
            "group_field",
            "origin_field",
            "raw_fields",
            "replace_if",
            "pointer",
            "entries",
            "group",
            "origin",
        ],
    ),
];

/// Неизвестные поля манифеста: опечатки не ломают разбор, но попадают в журнал.
pub fn unknown_fields(text: &str) -> Vec<String> {
    let Ok(root) = text.parse::<toml::Table>() else {
        return Vec::new();
    };
    let mut out = Vec::new();
    let known = |sec: &str| {
        KNOWN
            .iter()
            .find(|(n, _)| *n == sec)
            .map(|(_, k)| *k)
            .unwrap_or(&[])
    };
    for k in root.keys() {
        if !known("").contains(&k.as_str()) {
            out.push(k.clone());
        }
    }
    for sec in ["detect", "modes", "key"] {
        if let Some(t) = root.get(sec).and_then(|v| v.as_table()) {
            for k in t.keys() {
                if !known(sec).contains(&k.as_str()) {
                    out.push(format!("{sec}.{k}"));
                }
            }
        }
    }
    if let Some(a) = root.get("source").and_then(|v| v.as_array()) {
        for (i, t) in a.iter().enumerate() {
            for k in t
                .as_table()
                .map(|t| t.keys().cloned().collect::<Vec<_>>())
                .unwrap_or_default()
            {
                if !known("source").contains(&k.as_str()) {
                    out.push(format!("source[{i}].{k}"));
                }
            }
        }
    }
    out
}

/// Разбирает манифест из текста; `path` — путь файла (для относительных путей
/// источников и подписи `source`).
pub fn parse(text: &str, path: &Path) -> Result<Manifest, String> {
    let f: ManifestFile = toml::from_str(text).map_err(|e| e.to_string())?;
    if f.program.is_empty() {
        return Err("нет поля program".to_string());
    }
    let mut sources = Vec::new();
    for (i, s) in f.source.iter().enumerate() {
        let what = format!("source[{i}]");
        let kind = match s.kind.as_str() {
            "regex" => Kind::Regex,
            "toml" => Kind::Toml,
            "json" => Kind::Json,
            "static" => Kind::Static,
            other => return Err(format!("{what}.kind: неизвестный вид «{other}»")),
        };
        let regex = match &s.regex {
            Some(r) => Some(compile(r, &format!("{what}.regex"))?),
            None => None,
        };
        let sections = match &s.sections {
            Some(r) => Some(compile(r, &format!("{what}.sections"))?),
            None => None,
        };
        let split = match &s.split {
            Some(r) => Some(compile(r, &format!("{what}.split"))?),
            None => None,
        };
        if kind == Kind::Regex && regex.is_none() && sections.is_none() {
            return Err(format!("{what}: виду regex нужно regex или sections"));
        }
        let mut skip = Vec::new();
        for (k, v) in &s.skip {
            skip.push((k.clone(), compile(v, &format!("{what}.skip.{k}"))?));
        }
        let keep = match s.on_conflict.as_deref() {
            None | Some("override") => false,
            Some("keep") => true,
            Some(o) => return Err(format!("{what}.on_conflict: неизвестное «{o}»")),
        };
        sources.push(Source {
            spec: s.clone(),
            kind,
            regex,
            sections,
            split,
            skip,
            keep,
        });
    }
    let title = match &f.detect.title {
        Some(t) if !t.is_empty() => Some(compile(t, "detect.title")?),
        _ => None,
    };
    let file_name = path
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    let stem = path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    let mut view_table = f.view.clone();
    let origin_order = match view_table.remove("origin_order") {
        Some(toml::Value::Array(a)) => a
            .iter()
            .map(|v| {
                v.as_str()
                    .map(str::to_string)
                    .ok_or("view.origin_order: нужен список строк".to_string())
            })
            .collect::<Result<Vec<_>, _>>()?,
        Some(_) => return Err("view.origin_order: нужен список строк".to_string()),
        None => Vec::new(),
    };
    let view = crate::view::parse_level(&view_table, "view")?;
    let mut applies = Vec::new();
    for (i, a) in f.applies.iter().enumerate() {
        let what = format!("applies[{i}]");
        if a.action.is_empty() {
            return Err(format!("{what}: нет action"));
        }
        let when = if a.when.trim().is_empty() {
            return Err(format!("{what}: нет when"));
        } else {
            crate::cursor::When::parse(&a.when, &format!("{what}.when"))?
        };
        applies.push(Applies {
            modes: a.modes.clone(),
            action: compile(&a.action, &format!("{what}.action"))?,
            when,
        });
    }
    Ok(Manifest {
        path: path.to_path_buf(),
        dir: path.parent().map(Path::to_path_buf).unwrap_or_default(),
        file_name,
        stem,
        program: f.program,
        priority: f.priority,
        origins: f.origins,
        env: f.env,
        first_nonempty: f.first_nonempty.unwrap_or(f.detect.fallback),
        detect: Detect {
            provider: f.detect.provider.filter(|p| !p.is_empty()),
            process: f.detect.process,
            shell_commands: f.detect.shell_commands,
            title,
            screen: screen_rules(&f.detect.screen, "detect.screen")?,
            fallback: f.detect.fallback,
        },
        modes: Modes {
            default: f.modes.default,
            names: f.modes.names,
            from_config: f.modes.from_config,
            screen: screen_rules(&f.modes.screen, "modes.screen")?,
        },
        sources,
        key_map: f.key.map.into_iter().collect(),
        describe: rules(&f.describe, &["desc", "desc_full"], "describe")?,
        group: rules(&f.group, &["group"], "group")?,
        origin: rules(&f.origin, &["origin"], "origin")?,
        view,
        origin_order,
        applies,
    })
}

/// Загружает манифесты `*.toml` из каталогов по порядку; ошибочные
/// пропускаются, сообщения о них — во втором элементе.
pub fn load_dirs(dirs: &[PathBuf]) -> (Vec<Manifest>, Vec<String>) {
    let mut out = Vec::new();
    let mut errors = Vec::new();
    for dir in dirs {
        let Ok(rd) = std::fs::read_dir(dir) else {
            continue;
        };
        let mut files: Vec<PathBuf> = rd
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter(|p| p.extension().is_some_and(|x| x == "toml") && p.is_file())
            .collect();
        files.sort();
        for p in files {
            match std::fs::read_to_string(&p)
                .map_err(|e| e.to_string())
                .and_then(|t| parse(&t, &p))
            {
                Ok(m) => {
                    if let Ok(t) = std::fs::read_to_string(&p) {
                        let unk = unknown_fields(&t);
                        if !unk.is_empty() {
                            errors.push(format!(
                                "манифест {}: неизвестные поля {} (пропущены)",
                                p.display(),
                                unk.join(", ")
                            ));
                        }
                    }
                    out.push(m)
                }
                Err(e) => errors.push(format!("манифест {}: {e}", p.display())),
            }
        }
    }
    (out, errors)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_design_example() {
        let text = r#"
program = "ble"
priority = 100
origins = ["readline", "ble"]
[detect]
provider = "ble"
[modes]
default = "vi_imap"
names = { mgr = "manager" }
[[source]]
modes = ["*"]
kind = "regex"
file = "{record.table}"
regex = '''^ble-bind -m \S+ -(?P<type>[fxcs]) (?P<key>'[^']*'|\S+) (?P<action>.+)$'''
unquote = ["key", "action"]
skip = { key = "^__.*__$" }
on_conflict = "override"
[key]
map = { "ctrl-" = "C-" }
[[describe]]
action = "^history-isearch-backward$"
desc = "поиск по истории назад"
[[origin]]
type = "^[xc]$"
origin = "user"
"#;
        let m = parse(text, Path::new("/x/ble.toml")).expect("parse");
        assert_eq!(m.program, "ble");
        assert_eq!(m.sources.len(), 1);
        assert_eq!(m.describe[0].result["desc"], "поиск по истории назад");
        assert_eq!(m.source_label(), "manifest:ble.toml");
        assert_eq!(m.modes.native_name("manager"), "mgr");
    }

    #[test]
    fn bad_regex_is_error() {
        let text = "program = \"x\"\n[[source]]\nkind = \"regex\"\nregex = \"(\"\n";
        assert!(parse(text, Path::new("/x/x.toml")).is_err());
    }
}
