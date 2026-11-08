//! Построение таблицы по манифесту (D6): подстановки, виды источников
//! `regex` (с `sections`, `unquote`, глобальным поиском), `toml`, `json`,
//! `static`, нормализация клавиш, правила `describe`/`group`/`origin`.
//!
//! Построение — чистая функция от манифеста, подстановок и уже полученных
//! выводов команд: если для источника нужен вывод команды, которого ещё нет,
//! возвращается `Build::Need` с командой, и вызывающий запускает её сам
//! (просмотрщик — асинхронно с ожиданием по pidfd, `table` — синхронно).

use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};

use crate::entry::Entry;
use crate::manifest::{Kind, Manifest, Source};
use crate::{keys, shorten};

/// Значения подстановок для источников манифеста.
#[derive(Debug, Clone, Default)]
pub struct Subst {
    /// Родное имя режима (`{mode}`).
    pub mode_native: String,
    /// Имя режима в контексте (`{mode_name}`).
    pub mode: String,
    /// Поля записи поставщика (`{record.<поле>}`).
    pub record: BTreeMap<String, String>,
    /// Переменные окружения (`{env.<ИМЯ>}`).
    pub env: BTreeMap<String, String>,
    /// Команда (`{command}`).
    pub command: String,
    /// Процесс (`{pid}`).
    pub pid: Option<i32>,
    /// Домашний каталог для `~`.
    pub home: String,
}

impl Subst {
    /// Строка-ключ кеша по всем значениям подстановок.
    pub fn cache_key(&self) -> String {
        format!(
            "{}|{}|{:?}|{:?}|{}|{:?}",
            self.mode_native, self.mode, self.record, self.env, self.command, self.pid
        )
    }
}

/// Выводы команд источников: argv → stdout (`None` — команда не запустилась).
pub type Outputs = HashMap<Vec<String>, Option<String>>;

/// Файл, прочитанный при построении, и его время изменения.
pub type FileStamp = (PathBuf, Option<i128>);

#[derive(Debug, Clone, Default)]
pub struct Built {
    pub entries: Vec<Entry>,
    /// Прочитанные файлы (для проверки кеша и наблюдения inotify).
    pub files: Vec<FileStamp>,
}

#[derive(Debug, Clone)]
pub enum Build {
    Done(Built),
    /// Нужен вывод этой команды.
    Need(Vec<String>),
}

/// Время изменения файла в наносекундах.
pub fn mtime_ns(p: &Path) -> Option<i128> {
    use std::os::unix::fs::MetadataExt;
    let m = std::fs::metadata(p).ok()?;
    Some(m.mtime() as i128 * 1_000_000_000 + m.mtime_nsec() as i128)
}

/// Подстановка `{…}`; `None`, если значения нет.
pub fn substitute(s: &str, sub: &Subst) -> Option<String> {
    let mut out = String::new();
    let mut rest = s;
    while let Some(start) = rest.find('{') {
        out.push_str(&rest[..start]);
        let after = &rest[start + 1..];
        let Some(end) = after.find('}') else {
            out.push_str(&rest[start..]);
            rest = "";
            break;
        };
        let name = &after[..end];
        let value = match name {
            "mode" => Some(sub.mode_native.clone()),
            "mode_name" => Some(sub.mode.clone()),
            "command" => Some(sub.command.clone()).filter(|c| !c.is_empty()),
            "pid" => sub.pid.map(|p| p.to_string()),
            _ => {
                if let Some(f) = name.strip_prefix("record.") {
                    sub.record.get(f).cloned()
                } else if let Some(e) = name.strip_prefix("env.") {
                    sub.env.get(e).cloned()
                } else {
                    // Не подстановка (например, фигурные скобки регулярного
                    // выражения) — остаётся как есть.
                    out.push('{');
                    rest = after;
                    continue;
                }
            }
        };
        out.push_str(&value?);
        rest = &after[end + 1..];
    }
    out.push_str(rest);
    Some(out)
}

fn expand_path(s: &str, sub: &Subst, dir: &Path) -> Option<PathBuf> {
    let v = substitute(s, sub)?;
    if v.is_empty() {
        return None;
    }
    let v = if v == "~" {
        sub.home.clone()
    } else if let Some(r) = v.strip_prefix("~/") {
        format!("{}/{}", sub.home, r)
    } else {
        v
    };
    let p = PathBuf::from(v);
    Some(if p.is_absolute() { p } else { dir.join(p) })
}

/// Снимает кавычки shell: `'…'`, `"…"`, `$'…'`, обратная косая черта.
pub fn shell_unquote(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '\'' {
            i += 1;
            while i < chars.len() && chars[i] != '\'' {
                out.push(chars[i]);
                i += 1;
            }
            i += 1;
        } else if c == '$' && chars.get(i + 1) == Some(&'\'') {
            i += 2;
            while i < chars.len() && chars[i] != '\'' {
                if chars[i] == '\\' && i + 1 < chars.len() {
                    i += 1;
                    out.push(match chars[i] {
                        'n' => '\n',
                        't' => '\t',
                        'e' | 'E' => '\x1b',
                        o => o,
                    });
                } else {
                    out.push(chars[i]);
                }
                i += 1;
            }
            i += 1;
        } else if c == '"' {
            i += 1;
            while i < chars.len() && chars[i] != '"' {
                if chars[i] == '\\'
                    && i + 1 < chars.len()
                    && matches!(chars[i + 1], '"' | '\\' | '$' | '`')
                {
                    i += 1;
                }
                out.push(chars[i]);
                i += 1;
            }
            i += 1;
        } else if c == '\\' && i + 1 < chars.len() {
            out.push(chars[i + 1]);
            i += 2;
        } else {
            out.push(c);
            i += 1;
        }
    }
    out
}

/// Сырая запись источника: поля для правил и полей записи.
#[derive(Debug, Clone, Default)]
struct Raw {
    fields: BTreeMap<String, String>,
    /// Клавиша уже нормализована (массив клавиш из TOML/JSON).
    key_normalized: bool,
}

/// Строки раздела: заголовок и тело.
fn sections<'a>(text: &'a str, header: &regex::Regex) -> Vec<(String, Vec<&'a str>)> {
    let mut out: Vec<(String, Vec<&'a str>)> = Vec::new();
    let mut current: Option<usize> = None;
    for line in text.lines() {
        let is_header = !line.is_empty() && !line.starts_with(char::is_whitespace);
        if is_header {
            let clean = shorten::strip_man_markup(line);
            if header.is_match(clean.trim()) {
                out.push((clean.trim().to_string(), Vec::new()));
                current = Some(out.len() - 1);
            } else {
                current = None;
            }
            continue;
        }
        if let Some(i) = current {
            out[i].1.push(line);
        }
    }
    out
}

fn indent_of(line: &str) -> usize {
    line.chars()
        .take_while(|c| c.is_whitespace())
        .map(|c| if c == '\t' { 8 } else { 1 })
        .sum()
}

/// Делит строку на термин и описание по промежутку из двух и более пробелов
/// или табуляции.
fn split_term(content: &str) -> (String, Option<String>) {
    let bytes = content.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\t' || (bytes[i] == b' ' && bytes.get(i + 1) == Some(&b' ')) {
            let term = content[..i].trim().to_string();
            let desc = content[i..].trim().to_string();
            return (term, (!desc.is_empty()).then_some(desc));
        }
        i += 1;
    }
    (content.trim().to_string(), None)
}

/// Клавиши термина: `j, Down`, `q or Esc`; все части должны быть похожи на клавишу.
fn term_keys(term: &str) -> Option<Vec<String>> {
    let mut parts: Vec<String> = Vec::new();
    for a in term.split(", ") {
        for b in a.split(" or ") {
            let t = b.trim().trim_matches(|c| c == '`' || c == '"' || c == '\'');
            if t.is_empty() {
                continue;
            }
            parts.push(t.to_string());
        }
    }
    if parts.is_empty() || !parts.iter().all(|p| keys::looks_like_key(p) || is_key_sequence(p)) {
        return None;
    }
    Some(parts)
}

/// Последовательность клавиш через пробел (`C-x C-k`): каждое слово похоже
/// на клавишу и хотя бы одно из них длиннее символа (аккорд, имя клавиши),
/// иначе за последовательность сошли бы обычные слова из одной буквы.
fn is_key_sequence(s: &str) -> bool {
    let words: Vec<&str> = s.split_whitespace().collect();
    words.len() > 1
        && words.iter().all(|w| keys::looks_like_key(w))
        && words.iter().any(|w| w.chars().count() > 1)
}

/// Клавиши в начале строки без промежутка из двух пробелов: `h or H Help: …`.
/// Описание должно начинаться с прописной буквы, если клавиша одна, — иначе
/// это обычная фраза («A file is …»).
fn leading_keys(content: &str) -> Option<(Vec<String>, String)> {
    let words: Vec<&str> = content.split(' ').filter(|w| !w.is_empty()).collect();
    let mut keys_list = Vec::new();
    let mut i = 0;
    while i < words.len() {
        let w = words[i].trim_end_matches(',');
        if !keys::looks_like_key(w) {
            break;
        }
        // Следующие слова-клавиши без запятой и «or» продолжают
        // последовательность (`C-x C-k`), если в ней есть аккорд или имя.
        let mut seq = vec![w];
        let mut j = i + 1;
        while !words[j - 1].ends_with(',') && j < words.len() {
            let next = words[j].trim_end_matches(',');
            if next == "or" || !keys::looks_like_key(next) {
                break;
            }
            seq.push(next);
            j += 1;
        }
        if seq.len() > 1 && is_key_sequence(&seq.join(" ")) {
            keys_list.push(seq.join(" "));
            i = j;
        } else {
            keys_list.push(w.to_string());
            i += 1;
        }
        if words.get(i) == Some(&"or") {
            i += 1;
            continue;
        }
        if words[i - 1].ends_with(',') {
            continue;
        }
        break;
    }
    if keys_list.is_empty() || i >= words.len() {
        return None;
    }
    let desc = words[i..].join(" ");
    let upper = desc.chars().next().is_some_and(|c| c.is_uppercase());
    if keys_list.len() == 1 && !upper {
        return None;
    }
    Some((keys_list, desc))
}

/// Клавиши и описание строки-записи.
fn entry_head(content: &str) -> Option<(Vec<String>, Option<String>)> {
    let (term, desc) = split_term(content);
    if let Some(k) = term_keys(&term) {
        return Some((k, desc));
    }
    leading_keys(content).map(|(k, d)| (k, Some(d)))
}

/// Разбор справки по разделу без регулярного выражения: запись начинает
/// абзац (после пустой строки или сразу за предыдущей записью) с клавиш,
/// описание — через два пробела или строками ниже с большим отступом;
/// группа — ближайший подзаголовок (строка над записями с меньшим отступом).
fn auto_entries(header: &str, lines: &[&str]) -> Vec<Raw> {
    let mut out = Vec::new();
    let mut group = header.to_lowercase();
    let clean: Vec<String> = lines.iter().map(|l| shorten::strip_man_markup(l)).collect();
    let mut start_ok = true;
    let mut i = 0;
    while i < clean.len() {
        let line = &clean[i];
        if line.trim().is_empty() {
            start_ok = true;
            i += 1;
            continue;
        }
        let ind = indent_of(line);
        if start_ok {
            if let Some((keys_list, desc)) = entry_head(line.trim()) {
                let mut desc_text = desc.unwrap_or_default();
                let mut raw_lines = vec![line.trim_end().to_string()];
                let mut j = i + 1;
                while j < clean.len() {
                    let l = &clean[j];
                    if l.trim().is_empty() || indent_of(l) <= ind {
                        break;
                    }
                    if !desc_text.is_empty() {
                        desc_text.push(' ');
                    }
                    desc_text.push_str(l.trim());
                    raw_lines.push(l.trim_end().to_string());
                    j += 1;
                }
                if !desc_text.is_empty() {
                    for k in keys_list {
                        let mut f = BTreeMap::new();
                        f.insert("key".to_string(), k);
                        f.insert("desc".to_string(), shorten::collapse_ws(&desc_text));
                        f.insert("group".to_string(), group.clone());
                        f.insert("raw".to_string(), raw_lines.join("\n"));
                        out.push(Raw {
                            fields: f,
                            key_normalized: false,
                        });
                    }
                    i = j;
                    // Следующая строка того же уровня тоже может начинать запись.
                    start_ok = true;
                    continue;
                }
            }
            // Подзаголовок: следующая непустая строка глубже и сама — запись.
            let t = line.trim();
            let next = clean[i + 1..].iter().find(|l| !l.trim().is_empty());
            if let Some(n) = next {
                if indent_of(n) > ind
                    && entry_head(n.trim()).is_some()
                    && t.chars().count() < 50
                    && !t.ends_with('.')
                {
                    group = t.trim_end_matches(':').to_lowercase();
                    i += 1;
                    continue;
                }
            }
        }
        start_ok = false;
        i += 1;
    }
    out
}

fn regex_entries(src: &Source, text: &str) -> Vec<Raw> {
    let mut out = Vec::new();
    let blocks: Vec<(Option<String>, String)> = match &src.sections {
        Some(h) => sections(text, h)
            .into_iter()
            .map(|(name, lines)| (Some(name), lines.join("\n")))
            .collect(),
        None => vec![(None, text.to_string())],
    };
    for (header, body) in blocks {
        let Some(re) = &src.regex else {
            let lines: Vec<&str> = body.lines().collect();
            out.extend(auto_entries(header.as_deref().unwrap_or(""), &lines));
            continue;
        };
        let names: Vec<&str> = re.capture_names().flatten().collect();
        for caps in re.captures_iter(&body) {
            let mut f = BTreeMap::new();
            for n in &names {
                if let Some(m) = caps.name(n) {
                    let mut v = m.as_str().to_string();
                    if src.spec.unquote.iter().any(|u| u == n) {
                        v = shell_unquote(&v);
                    }
                    f.insert(n.to_string(), v);
                }
            }
            if let Some(h) = &header {
                f.entry("group".to_string()).or_insert_with(|| h.to_lowercase());
            }
            let whole = caps.get(0).map(|m| m.as_str()).unwrap_or("");
            f.entry("raw".to_string())
                .or_insert_with(|| whole.trim().to_string());
            match (&src.split, f.get("key").cloned()) {
                (Some(sep), Some(k)) => {
                    for part in sep.split(&k).map(str::trim).filter(|p| !p.is_empty()) {
                        let mut g = f.clone();
                        g.insert("key".to_string(), part.to_string());
                        out.push(Raw {
                            fields: g,
                            key_normalized: false,
                        });
                    }
                }
                _ => out.push(Raw {
                    fields: f,
                    key_normalized: false,
                }),
            }
        }
    }
    out
}

fn value_text(v: &toml::Value) -> Option<String> {
    match v {
        toml::Value::String(s) => Some(s.clone()),
        toml::Value::Integer(i) => Some(i.to_string()),
        toml::Value::Boolean(b) => Some(b.to_string()),
        toml::Value::Float(f) => Some(f.to_string()),
        _ => None,
    }
}

fn json_text(v: &serde_json::Value) -> Option<String> {
    match v {
        serde_json::Value::String(s) => Some(s.clone()),
        serde_json::Value::Number(n) => Some(n.to_string()),
        serde_json::Value::Bool(b) => Some(b.to_string()),
        _ => None,
    }
}

/// Поля записи из объекта (таблицы TOML или объекта JSON) по именам полей источника.
struct FieldNames<'a> {
    key: &'a str,
    action: &'a str,
    desc: &'a str,
    group: &'a str,
    origin: &'a str,
}

fn field_names(src: &Source) -> FieldNames<'_> {
    FieldNames {
        key: src.spec.key_field.as_deref().unwrap_or("key"),
        action: src.spec.action_field.as_deref().unwrap_or("action"),
        desc: src.spec.desc_field.as_deref().unwrap_or("desc"),
        group: src.spec.group_field.as_deref().unwrap_or("group"),
        origin: src.spec.origin_field.as_deref().unwrap_or("origin"),
    }
}

/// Значение-список строк (`["g", "g"]`) или одна строка.
fn strings_toml(v: &toml::Value) -> Vec<String> {
    match v {
        toml::Value::Array(a) => a.iter().filter_map(value_text).collect(),
        other => value_text(other).into_iter().collect(),
    }
}

fn strings_json(v: &serde_json::Value) -> Vec<String> {
    match v {
        serde_json::Value::Array(a) => a.iter().filter_map(json_text).collect(),
        other => json_text(other).into_iter().collect(),
    }
}

fn object_raw(
    keys_list: Vec<String>,
    actions: Vec<String>,
    scalar_fields: BTreeMap<String, String>,
    names: &FieldNames,
    raw: String,
    map: &[(String, String)],
) -> Option<Raw> {
    if keys_list.is_empty() {
        return None;
    }
    let mut f = scalar_fields;
    let key = keys_list
        .iter()
        .map(|k| keys::normalize_with(k, map))
        .collect::<Vec<_>>()
        .join(" ");
    f.insert("key".to_string(), key);
    f.insert("action".to_string(), actions.join("; "));
    for (from, to) in [
        (names.desc, "desc"),
        (names.group, "group"),
        (names.origin, "origin"),
    ] {
        if from != to {
            if let Some(v) = f.get(from).cloned() {
                f.insert(to.to_string(), v);
            }
        }
    }
    f.entry("raw".to_string()).or_insert(raw);
    Some(Raw {
        fields: f,
        key_normalized: true,
    })
}

/// Записи TOML: таблицы `tables`, массивы `arrays` или пары «клавиша = действие».
/// Второй элемент — встретился ли массив `replace_if`.
fn toml_entries(src: &Source, text: &str, sub: &Subst, map: &[(String, String)]) -> (Vec<Raw>, bool) {
    let Ok(root) = text.parse::<toml::Table>() else {
        return (Vec::new(), false);
    };
    let root = toml::Value::Table(root);
    let names = field_names(src);
    let tables: Vec<String> = if src.spec.tables.is_empty() {
        vec![String::new()]
    } else {
        src.spec
            .tables
            .iter()
            .filter_map(|t| substitute(t, sub))
            .collect()
    };
    let layout = src.spec.layout.clone().unwrap_or_else(|| {
        if src.spec.arrays.is_empty() {
            "key_value".to_string()
        } else {
            "arrays".to_string()
        }
    });
    let mut out = Vec::new();
    let mut replace = false;
    for tpath in tables {
        let mut node = &root;
        let mut found = true;
        for part in tpath.split('.').filter(|p| !p.is_empty()) {
            match node.get(part) {
                Some(n) => node = n,
                None => {
                    found = false;
                    break;
                }
            }
        }
        if !found {
            continue;
        }
        match layout.as_str() {
            "arrays" => {
                let arrays: Vec<String> = if src.spec.arrays.is_empty() {
                    vec![String::new()]
                } else {
                    src.spec.arrays.clone()
                };
                for an in arrays {
                    let arr = if an.is_empty() { Some(node) } else { node.get(&an) };
                    let Some(toml::Value::Array(items)) = arr else {
                        continue;
                    };
                    if src.spec.replace_if.as_deref() == Some(an.as_str()) {
                        replace = true;
                    }
                    for item in items {
                        let Some(t) = item.as_table() else { continue };
                        let keys_list = t.get(names.key).map(strings_toml).unwrap_or_default();
                        let actions = t.get(names.action).map(strings_toml).unwrap_or_default();
                        let scalars: BTreeMap<String, String> = t
                            .iter()
                            .filter_map(|(k, v)| value_text(v).map(|s| (k.clone(), s)))
                            .collect();
                        let raw = toml::to_string(t)
                            .map(|s| s.trim().replace('\n', ", "))
                            .unwrap_or_default();
                        out.extend(object_raw(keys_list, actions, scalars, &names, raw, map));
                    }
                }
            }
            "value_key" => {
                let Some(t) = node.as_table() else { continue };
                for (action, v) in t {
                    for k in strings_toml(v) {
                        let raw = format!("{action} = {v}");
                        out.extend(object_raw(
                            vec![k],
                            vec![action.clone()],
                            BTreeMap::new(),
                            &names,
                            raw,
                            map,
                        ));
                    }
                }
            }
            _ => {
                let Some(t) = node.as_table() else { continue };
                for (k, v) in t {
                    let actions = strings_toml(v);
                    if actions.is_empty() {
                        continue;
                    }
                    let raw = format!("{k} = {v}");
                    out.extend(object_raw(
                        vec![k.clone()],
                        actions,
                        BTreeMap::new(),
                        &names,
                        raw,
                        map,
                    ));
                }
            }
        }
    }
    (out, replace)
}

fn json_entries(src: &Source, text: &str, map: &[(String, String)]) -> Vec<Raw> {
    let Ok(root) = serde_json::from_str::<serde_json::Value>(text.trim()) else {
        return Vec::new();
    };
    let node = match src.spec.pointer.as_deref() {
        Some(p) if !p.is_empty() => match root.pointer(p) {
            Some(n) => n,
            None => return Vec::new(),
        },
        _ => &root,
    };
    let Some(items) = node.as_array() else {
        return Vec::new();
    };
    let names = field_names(src);
    let mut out = Vec::new();
    for item in items {
        let Some(o) = item.as_object() else { continue };
        let keys_list: Vec<String> = o.get(names.key).map(strings_json).unwrap_or_default();
        let actions = o.get(names.action).map(strings_json).unwrap_or_default();
        let scalars: BTreeMap<String, String> = o
            .iter()
            .filter_map(|(k, v)| json_text(v).map(|s| (k.clone(), s)))
            .collect();
        let raw = if src.spec.raw_fields.is_empty() {
            serde_json::to_string(item).unwrap_or_default()
        } else {
            src.spec
                .raw_fields
                .iter()
                .filter_map(|f| o.get(f).and_then(json_text))
                .filter(|s| !s.is_empty())
                .collect::<Vec<_>>()
                .join("  ")
        };
        out.extend(object_raw(keys_list, actions, scalars, &names, raw, map));
    }
    out
}

fn static_entries(list: &[toml::Table], map: &[(String, String)]) -> Vec<Raw> {
    let mut out = Vec::new();
    for t in list {
        let keys_list = t.get("key").map(strings_toml).unwrap_or_default();
        if keys_list.is_empty() {
            continue;
        }
        let scalars: BTreeMap<String, String> = t
            .iter()
            .filter(|(k, _)| k.as_str() != "key")
            .filter_map(|(k, v)| value_text(v).map(|s| (k.clone(), s)))
            .collect();
        let key = keys_list
            .iter()
            .map(|k| keys::normalize_with(k, map))
            .collect::<Vec<_>>()
            .join(" ");
        let mut f = scalars;
        f.insert("key".to_string(), key);
        out.push(Raw {
            fields: f,
            key_normalized: true,
        });
    }
    out
}

/// Записи статического файла данных: TOML с массивом `entries`/`entry` или JSON-массив.
fn static_file_entries(text: &str, map: &[(String, String)]) -> Vec<Raw> {
    if let Ok(t) = text.parse::<toml::Table>() {
        for name in ["entries", "entry"] {
            if let Some(toml::Value::Array(a)) = t.get(name) {
                let list: Vec<toml::Table> =
                    a.iter().filter_map(|v| v.as_table().cloned()).collect();
                return static_entries(&list, map);
            }
        }
        return Vec::new();
    }
    if let Ok(serde_json::Value::Array(a)) = serde_json::from_str::<serde_json::Value>(text) {
        let list: Vec<toml::Table> = a
            .iter()
            .filter_map(|v| toml::Value::try_from(v).ok())
            .filter_map(|v| v.as_table().cloned())
            .collect();
        return static_entries(&list, map);
    }
    Vec::new()
}

/// Запись таблицы из сырой записи по правилам манифеста.
fn finish(m: &Manifest, src: &Source, raw: Raw, mode: &[&str], label: &str) -> Option<Entry> {
    let mut f = raw.fields;
    // skip проверяется по исходным значениям и ещё раз — по нормализованной клавише.
    for (field, re) in &src.skip {
        if re.is_match(f.get(field).map(String::as_str).unwrap_or("")) && f.contains_key(field) {
            return None;
        }
    }
    let key_raw = f.get("key").cloned().unwrap_or_default();
    let key = if raw.key_normalized {
        key_raw
    } else {
        keys::normalize_with(key_raw.trim(), &m.key_map)
    };
    if key.is_empty() {
        return None;
    }
    f.insert("key".to_string(), key.clone());
    f.entry("action".to_string()).or_default();
    for (field, re) in &src.skip {
        if re.is_match(f.get(field).map(String::as_str).unwrap_or("")) {
            return None;
        }
    }
    let rule_mode: Vec<&str> = mode.to_vec();
    // Поле desc_full источника — полный текст, desc при нём — короткое описание;
    // без desc_full поле desc источника — полный текст.
    let (mut desc, mut desc_full) = match f.get("desc_full") {
        Some(full) => (f.get("desc").cloned().unwrap_or_default(), full.clone()),
        None => (String::new(), f.get("desc").cloned().unwrap_or_default()),
    };
    if let Some(r) = m.describe.iter().find(|r| r.matches(&f, &rule_mode)) {
        if let Some(d) = r.result.get("desc") {
            desc = d.clone();
        }
        if let Some(d) = r.result.get("desc_full") {
            desc_full = d.clone();
        }
    }
    let desc_full = shorten::collapse_ws(&shorten::strip_man_markup(&desc_full));
    if desc.is_empty() && !desc_full.is_empty() {
        desc = shorten::shorten(&desc_full);
    }
    let group = m
        .group
        .iter()
        .find(|r| r.matches(&f, &rule_mode))
        .and_then(|r| r.result.get("group").cloned())
        .or_else(|| f.get("group").cloned().filter(|g| !g.is_empty()))
        .or_else(|| src.spec.group.clone())
        .unwrap_or_else(|| "other".to_string());
    let origin = m
        .origin
        .iter()
        .find(|r| r.matches(&f, &rule_mode))
        .and_then(|r| r.result.get("origin").cloned())
        .or_else(|| f.get("origin").cloned().filter(|o| !o.is_empty()))
        .or_else(|| src.spec.origin.clone())
        .unwrap_or_else(|| m.default_origin());
    Some(Entry {
        key,
        desc,
        desc_full,
        group,
        origin,
        action: f.get("action").cloned().unwrap_or_default(),
        source: label.to_string(),
        raw: f.get("raw").cloned().unwrap_or_default(),
    })
}

/// Входной текст источника или `Need`/пропуск.
enum Input {
    Text(String),
    Skip,
    Need(Vec<String>),
}

/// Подстановка для источника; нет значения — источник пропускается,
/// причина пишется в журнал на уровне отладки.
fn subst_or_skip(m: &Manifest, s: &str, sub: &Subst) -> Option<String> {
    let v = substitute(s, sub);
    if v.is_none() {
        crate::paths::debug(&format!(
            "{}: источник пропущен, нет значения подстановки в «{s}» (режим {})",
            m.file_name, sub.mode_native
        ));
    }
    v
}

fn source_input(m: &Manifest, src: &Source, sub: &Subst, outputs: &Outputs, files: &mut Vec<FileStamp>) -> Input {
    if let Some(cmd) = &src.spec.command {
        let mut argv = Vec::new();
        for a in cmd {
            match subst_or_skip(m, a, sub) {
                Some(v) => argv.push(v),
                None => return Input::Skip,
            }
        }
        if argv.is_empty() || argv[0].is_empty() {
            return Input::Skip;
        }
        return match outputs.get(&argv) {
            Some(Some(out)) => Input::Text(out.clone()),
            Some(None) => Input::Skip,
            None => Input::Need(argv),
        };
    }
    if let Some(p) = src.spec.file.as_ref().or(src.spec.path.as_ref()) {
        subst_or_skip(m, p, sub);
        let Some(path) = expand_path(p, sub, &m.dir) else {
            return Input::Skip;
        };
        let stamp = mtime_ns(&path);
        files.push((path.clone(), stamp));
        return match std::fs::read_to_string(&path) {
            Ok(t) => Input::Text(t),
            Err(_) => Input::Skip,
        };
    }
    if let Some(e) = &src.spec.env {
        return match sub.env.get(e) {
            Some(v) => Input::Text(v.clone()),
            None => Input::Skip,
        };
    }
    if let Some(t) = &src.spec.text {
        return match subst_or_skip(m, t, sub) {
            Some(v) => Input::Text(v),
            None => Input::Skip,
        };
    }
    Input::Skip
}

/// Подходит ли источник к режиму.
fn source_applies(src: &Source, sub: &Subst) -> bool {
    src.spec.modes.is_empty()
        || crate::glob::any(&src.spec.modes, &sub.mode_native)
        || crate::glob::any(&src.spec.modes, &sub.mode)
}

/// Строит таблицу по манифесту для режима и подстановок.
pub fn build(m: &Manifest, sub: &Subst, outputs: &Outputs) -> Build {
    let label = m.source_label();
    let mode: Vec<&str> = vec![sub.mode_native.as_str(), sub.mode.as_str()];
    let mut acc: Vec<Entry> = Vec::new();
    let mut index: HashMap<String, usize> = HashMap::new();
    let mut files: Vec<FileStamp> = Vec::new();
    for src in &m.sources {
        if !source_applies(src, sub) {
            continue;
        }
        let mut replace = false;
        let raws: Vec<Raw> = if src.kind == Kind::Static && src.spec.file.is_none() && src.spec.path.is_none() {
            static_entries(&src.spec.entries, &m.key_map)
        } else {
            let text = match source_input(m, src, sub, outputs, &mut files) {
                Input::Text(t) => t,
                Input::Skip => continue,
                Input::Need(argv) => return Build::Need(argv),
            };
            match src.kind {
                Kind::Regex => regex_entries(src, &text),
                Kind::Toml => {
                    let (r, rep) = toml_entries(src, &text, sub, &m.key_map);
                    replace = rep;
                    r
                }
                Kind::Json => json_entries(src, &text, &m.key_map),
                Kind::Static => static_file_entries(&text, &m.key_map),
            }
        };
        if replace {
            acc.clear();
            index.clear();
        }
        // Внутри источника побеждает первое вхождение клавиши.
        let mut seen: HashMap<String, ()> = HashMap::new();
        for raw in raws {
            let Some(e) = finish(m, src, raw, &mode, &label) else {
                continue;
            };
            if seen.insert(e.key.clone(), ()).is_some() {
                continue;
            }
            match index.get(&e.key) {
                Some(&i) => {
                    if !src.keep {
                        acc[i] = e;
                    }
                }
                None => {
                    index.insert(e.key.clone(), acc.len());
                    acc.push(e);
                }
            }
        }
        if m.first_nonempty && !acc.is_empty() {
            break;
        }
    }
    Build::Done(Built {
        entries: acc,
        files,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::manifest;

    fn man(text: &str) -> Manifest {
        manifest::parse(text, Path::new("/m/test.toml")).expect("manifest")
    }

    #[test]
    fn unquote() {
        assert_eq!(shell_unquote("'C-x C-k'"), "C-x C-k");
        assert_eq!(shell_unquote(r#""a\"b""#), "a\"b");
        assert_eq!(shell_unquote(r"a\ b"), "a b");
    }

    #[test]
    fn subst() {
        let mut s = Subst {
            mode_native: "mgr".into(),
            ..Default::default()
        };
        s.record.insert("table".into(), "/t".into());
        assert_eq!(substitute("{record.table}", &s).as_deref(), Some("/t"));
        assert_eq!(substitute("{mode}", &s).as_deref(), Some("mgr"));
        assert_eq!(substitute("{record.server}", &s), None);
        assert_eq!(substitute("a{2,3}", &s).as_deref(), Some("a{2,3}"));
    }

    #[test]
    fn regex_source_with_rules() {
        let m = man(r#"
program = "ble"
[[source]]
kind = "regex"
text = """
ble-bind -m 'vi_imap' -f C-r history-isearch-backward
ble-bind -m 'vi_imap' -x M-f fzf-file-widget
ble-bind -m 'vi_imap' -f __default__ self-insert
"""
regex = '''^ble-bind -m \S+ -(?P<type>[fxcs]) (?P<key>'[^']*'|\S+) (?P<action>.+)$'''
unquote = ["key", "action"]
skip = { key = "^__.*__$" }
[[describe]]
action = "^history-isearch-backward$"
desc = "поиск по истории назад"
[[origin]]
type = "^[xc]$"
origin = "user"
[[origin]]
type = "^f$"
origin = "ble"
"#);
        let Build::Done(b) = build(&m, &Subst::default(), &Outputs::new()) else {
            panic!("need");
        };
        assert_eq!(b.entries.len(), 2);
        assert_eq!(b.entries[0].key, "C-r");
        assert_eq!(b.entries[0].desc, "поиск по истории назад");
        assert_eq!(b.entries[0].origin, "ble");
        assert_eq!(b.entries[1].origin, "user");
        assert_eq!(b.entries[1].action, "fzf-file-widget");
        assert_eq!(
            b.entries[1].raw,
            "ble-bind -m 'vi_imap' -x M-f fzf-file-widget"
        );
    }

    #[test]
    fn command_source_needs_output() {
        let m = man(r#"
program = "fzf"
[[source]]
kind = "regex"
command = ["man", "fzf"]
regex = '^\s+(?P<key>\S+)\s{2,}(?P<action>\S+)$'
"#);
        let Build::Need(argv) = build(&m, &Subst::default(), &Outputs::new()) else {
            panic!("done");
        };
        assert_eq!(argv, vec!["man", "fzf"]);
        let mut o = Outputs::new();
        o.insert(argv, Some("    ctrl-a  beginning-of-line\n".into()));
        let Build::Done(b) = build(&m, &Subst::default(), &o) else {
            panic!("need");
        };
        assert_eq!(b.entries[0].key, "C-a");
    }

    #[test]
    fn toml_arrays_and_replace() {
        let m = man(r#"
program = "yazi"
[[source]]
kind = "toml"
text = """
[mgr]
keymap = [ { on = ["g", "g"], run = "arrow top", desc = "Move cursor to the top" },
           { on = "<C-a>", run = ["a", "b"] } ]
"""
tables = ["{mode}"]
arrays = ["prepend_keymap", "keymap", "append_keymap"]
key_field = "on"
action_field = "run"
replace_if = "keymap"
"#);
        let s = Subst {
            mode_native: "mgr".into(),
            mode: "manager".into(),
            ..Default::default()
        };
        let Build::Done(b) = build(&m, &s, &Outputs::new()) else {
            panic!()
        };
        assert_eq!(b.entries[0].key, "g g");
        assert_eq!(b.entries[0].desc_full, "Move cursor to the top");
        assert_eq!(b.entries[0].desc, "Move cursor to the top");
        assert_eq!(b.entries[1].key, "C-a");
        assert_eq!(b.entries[1].action, "a; b");
    }

    #[test]
    fn toml_key_value_forms() {
        let m = man(r#"
program = "tv"
[[source]]
kind = "toml"
text = """
[keybindings]
esc = "quit"
ctrl-j = "select_next_entry"
"""
tables = ["keybindings"]
[[source]]
kind = "toml"
text = """
[keybindings]
quit = ["esc", "ctrl-c"]
"""
tables = ["keybindings"]
layout = "value_key"
on_conflict = "keep"
"#);
        let Build::Done(b) = build(&m, &Subst::default(), &Outputs::new()) else {
            panic!()
        };
        let keys: Vec<&str> = b.entries.iter().map(|e| e.key.as_str()).collect();
        assert_eq!(keys, vec!["ESC", "C-j", "C-c"]);
    }

    #[test]
    fn man_sections_auto() {
        let m = man(r#"
program = "*"
priority = 0
[detect]
fallback = true
[[source]]
kind = "regex"
text = """
NAME
       prog - test

KEY BINDINGS
   Movement
       j, Down   Move down one line.
       q         This will quit the program immediately. Unsaved changes are lost.
       Ctrl-L
              Redraw the screen.

OPTIONS
       -h     help
"""
sections = '^(KEY ?BINDINGS|KEYS)\b'
"#);
        let Build::Done(b) = build(&m, &Subst::default(), &Outputs::new()) else {
            panic!()
        };
        let keys: Vec<&str> = b.entries.iter().map(|e| e.key.as_str()).collect();
        assert_eq!(keys, vec!["j", "down", "q", "C-l"]);
        assert_eq!(b.entries[2].desc, "quit the program immediately");
        assert_eq!(b.entries[0].group, "movement");
        assert_eq!(b.entries[0].origin, "test");
        assert_eq!(b.entries[0].source, "test");
        assert_eq!(b.entries[3].desc_full, "Redraw the screen.");
    }

    #[test]
    fn json_source() {
        let m = man(r#"
program = "nvim"
[[source]]
kind = "json"
text = '[{"lhs":" ff","rhs":"","desc":"Find Files (Root Dir)","origin":"lazyvim","source":"/x.lua:3"}]'
key_field = "lhs"
action_field = "rhs"
raw_fields = ["rhs", "source"]
"#);
        let Build::Done(b) = build(&m, &Subst::default(), &Outputs::new()) else {
            panic!()
        };
        assert_eq!(b.entries[0].key, "SP f f");
        assert_eq!(b.entries[0].origin, "lazyvim");
        assert_eq!(b.entries[0].desc, "Find Files");
        assert_eq!(b.entries[0].raw, "/x.lua:3");
    }
}
