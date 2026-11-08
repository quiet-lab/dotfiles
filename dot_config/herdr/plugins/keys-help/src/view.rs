//! Конфигурация представления (D12): разбор `view.toml`, слияние уровней
//! «умолчания → программа → режим» с шаблонами, фильтрация и порядок записей,
//! `[entry]`, запись `d`/`D`/`u` через `toml_edit` с `rename` по настоящему пути.

use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};

use crate::entry::Entry;
use crate::keys;

/// `show_origin`: все подписи, перечень происхождений или без подписей.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub enum ShowOrigin {
    #[default]
    None,
    All,
    List(Vec<String>),
}

impl ShowOrigin {
    /// Показывать ли подпись у записи с этим происхождением.
    pub fn label_for(&self, origin: &str) -> bool {
        match self {
            ShowOrigin::None => false,
            ShowOrigin::All => true,
            ShowOrigin::List(l) => l.iter().any(|o| o == origin),
        }
    }
}

/// Один уровень конфигурации (`[defaults]` или `[context."…"]`).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Level {
    pub order: Option<Vec<String>>,
    pub hide: Option<Vec<String>>,
    pub hide_groups: Option<Vec<String>>,
    pub pin: Option<Vec<String>>,
    pub only_modifiers: Option<bool>,
    pub show_origin: Option<ShowOrigin>,
}

/// Переопределение или добавление записи `[entry."<контекст>"."<клавиша>"]`.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct EntryOverride {
    pub desc: Option<String>,
    pub group: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct ViewConfig {
    pub defaults: Level,
    pub contexts: Vec<(String, Level)>,
    pub entries: Vec<(String, String, EntryOverride)>,
}

/// Действующие поля для контекста после слияния уровней.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Effective {
    pub order: Vec<String>,
    pub hide: Vec<String>,
    pub hide_groups: Vec<String>,
    pub pin: Vec<String>,
    pub only_modifiers: bool,
    pub show_origin: ShowOrigin,
    /// Клавиша → переопределение (уже слитое по уровням).
    pub entries: BTreeMap<String, EntryOverride>,
}

fn str_list(v: &toml::Value, what: &str, normalize: bool) -> Result<Vec<String>, String> {
    let toml::Value::Array(a) = v else {
        return Err(format!("{what}: нужен список строк"));
    };
    a.iter()
        .map(|x| {
            x.as_str()
                .map(|s| if normalize { keys::normalize(s) } else { s.to_string() })
                .ok_or_else(|| format!("{what}: нужен список строк"))
        })
        .collect()
}

pub fn parse_level(t: &toml::Table, what: &str) -> Result<Level, String> {
    let mut l = Level::default();
    for (k, v) in t {
        let w = format!("{what}.{k}");
        match k.as_str() {
            "order" => l.order = Some(str_list(v, &w, false)?),
            "hide" => l.hide = Some(str_list(v, &w, true)?),
            "hide_groups" => l.hide_groups = Some(str_list(v, &w, false)?),
            "pin" => l.pin = Some(str_list(v, &w, true)?),
            "only_modifiers" => {
                l.only_modifiers = Some(v.as_bool().ok_or_else(|| format!("{w}: нужно true или false"))?)
            }
            "show_origin" => {
                l.show_origin = Some(match v {
                    toml::Value::Boolean(true) => ShowOrigin::All,
                    toml::Value::Boolean(false) => ShowOrigin::None,
                    toml::Value::Array(_) => ShowOrigin::List(str_list(v, &w, false)?),
                    _ => return Err(format!("{w}: нужно true, false или список")),
                })
            }
            other => return Err(format!("{what}: неизвестное поле «{other}»")),
        }
    }
    Ok(l)
}

/// Разбирает `view.toml`.
pub fn parse(text: &str) -> Result<ViewConfig, String> {
    let root: toml::Table = text.parse().map_err(|e: toml::de::Error| e.to_string())?;
    let mut cfg = ViewConfig::default();
    for (k, v) in &root {
        match k.as_str() {
            "defaults" => {
                let t = v.as_table().ok_or("defaults: нужна таблица")?;
                cfg.defaults = parse_level(t, "defaults")?;
            }
            "context" => {
                let t = v.as_table().ok_or("context: нужна таблица")?;
                for (pat, lv) in t {
                    let lt = lv
                        .as_table()
                        .ok_or_else(|| format!("context.\"{pat}\": нужна таблица"))?;
                    cfg.contexts
                        .push((pat.clone(), parse_level(lt, &format!("context.\"{pat}\""))?));
                }
            }
            "entry" => {
                let t = v.as_table().ok_or("entry: нужна таблица")?;
                for (pat, kv) in t {
                    let kt = kv
                        .as_table()
                        .ok_or_else(|| format!("entry.\"{pat}\": нужна таблица"))?;
                    for (key, ov) in kt {
                        let ot = ov
                            .as_table()
                            .ok_or_else(|| format!("entry.\"{pat}\".\"{key}\": нужна таблица"))?;
                        let mut o = EntryOverride::default();
                        for (f, fv) in ot {
                            let s = fv.as_str().map(str::to_string);
                            match f.as_str() {
                                "desc" => o.desc = s,
                                "group" => o.group = s,
                                other => {
                                    return Err(format!(
                                        "entry.\"{pat}\".\"{key}\": неизвестное поле «{other}»"
                                    ))
                                }
                            }
                        }
                        cfg.entries.push((pat.clone(), keys::normalize(key), o));
                    }
                }
            }
            other => return Err(format!("неизвестный раздел «{other}»")),
        }
    }
    Ok(cfg)
}

/// Подходит ли шаблон к контексту и его частность (больше — применяется позже).
///
/// `x.*` подходит к `x` и `x.<режим>`; имя программы без точки — к `x` и
/// `x.<режим>`; `*.generic` — ко всем контекстам извлекателя; полное имя —
/// только к себе (самый частный уровень).
pub fn pattern_specificity(pat: &str, ctx: &str) -> Option<usize> {
    if pat == ctx {
        return Some(10_000 + pat.len());
    }
    if let Some(prog) = pat.strip_suffix(".*") {
        if !prog.contains('*') && (ctx == prog || ctx.starts_with(&format!("{prog}."))) {
            return Some(prog.len() + 1);
        }
    }
    if !pat.contains('*') && !pat.contains('.') && ctx.starts_with(&format!("{pat}.")) {
        return Some(pat.len() + 1);
    }
    if pat.contains('*') && crate::glob::matches(pat, ctx) {
        return Some(pat.find('*').unwrap_or(pat.len()));
    }
    None
}

fn union(into: &mut Vec<String>, add: &[String]) {
    for x in add {
        if !into.contains(x) {
            into.push(x.clone());
        }
    }
}

/// Слияние уровней для контекста.
pub fn effective(cfg: &ViewConfig, ctx: &str) -> Effective {
    effective_with(cfg, ctx, None)
}

/// Слияние уровней «умолчания → `[view]` манифеста программы → контексты».
pub fn effective_with(cfg: &ViewConfig, ctx: &str, program: Option<&Level>) -> Effective {
    let mut levels: Vec<(usize, usize, &Level)> = cfg
        .contexts
        .iter()
        .enumerate()
        .filter_map(|(i, (pat, l))| pattern_specificity(pat, ctx).map(|s| (s, i, l)))
        .collect();
    levels.sort_by_key(|&(s, i, _)| (s, i));
    let mut e = Effective::default();
    for l in std::iter::once(&cfg.defaults)
        .chain(program)
        .chain(levels.iter().map(|x| x.2))
    {
        if let Some(v) = &l.order {
            e.order = v.clone();
        }
        if let Some(v) = &l.hide {
            union(&mut e.hide, v);
        }
        if let Some(v) = &l.hide_groups {
            union(&mut e.hide_groups, v);
        }
        if let Some(v) = &l.pin {
            e.pin = v.clone();
        }
        if let Some(v) = l.only_modifiers {
            e.only_modifiers = v;
        }
        if let Some(v) = &l.show_origin {
            e.show_origin = v.clone();
        }
    }
    let mut ents: Vec<(usize, usize, &String, &EntryOverride)> = cfg
        .entries
        .iter()
        .enumerate()
        .filter_map(|(i, (pat, key, o))| pattern_specificity(pat, ctx).map(|s| (s, i, key, o)))
        .collect();
    ents.sort_by_key(|&(s, i, _, _)| (s, i));
    for (_, _, key, o) in ents {
        let slot = e.entries.entry(key.clone()).or_default();
        if o.desc.is_some() {
            slot.desc = o.desc.clone();
        }
        if o.group.is_some() {
            slot.group = o.group.clone();
        }
    }
    e
}

/// Блок показа: закреплённые записи (`title = None`) или группа.
#[derive(Debug, Clone, PartialEq)]
pub struct Section {
    pub title: Option<String>,
    pub entries: Vec<Shown>,
}

/// Вид раздела, в котором показана запись: скрыть группу клавишей `D`
/// можно только из раздела группы.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SectionKind {
    #[default]
    Group,
    Pin,
    Cursor,
    Completion,
    Origin,
}

impl SectionKind {
    /// Название раздела для сообщения о том, что группу скрыть нельзя.
    pub fn label(self) -> &'static str {
        match self {
            SectionKind::Group => "группа",
            SectionKind::Pin => "закреплённые записи",
            SectionKind::Cursor => "раздел по позиции курсора",
            SectionKind::Completion => "раздел дополнения",
            SectionKind::Origin => "раздел по происхождению",
        }
    }
}

/// Запись к показу с признаком подписи происхождения.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Shown {
    pub entry: Entry,
    /// Раздел, в котором запись показана.
    pub kind: SectionKind,
    pub show_origin: bool,
    /// Неприменима при текущей позиции курсора (D17): показывается приглушённой.
    pub dim: bool,
    /// Подсветка совпадения поиска (D16).
    pub hl: crate::search::Hl,
}

/// Предел ячеек раздела «по позиции курсора» (D17).
pub const MAX_CURSOR: usize = 8;

/// Заголовок раздела «по позиции курсора».
pub const CURSOR_TITLE: &str = "по позиции курсора";
/// Заголовок раздела «дополнение».
pub const COMPLETION_TITLE: &str = "дополнение";

/// Применимость записи при текущей позиции курсора: номер правила
/// `[[applies]]` и значение его `when`; `None` — правило не подходит.
pub type ApplyRule<'a> = &'a dyn Fn(&Entry) -> Option<(usize, bool)>;

/// Дополнительные разделы и порядок поверх `apply` (D15, D17).
#[derive(Default)]
pub struct Extra<'a> {
    /// Порядок разделов по происхождению из манифеста.
    pub origin_order: Vec<String>,
    /// Правила применимости; `None` — позиция курсора неизвестна
    /// (раздела «по позиции курсора» и приглушения нет).
    pub applies: Option<ApplyRule<'a>>,
    /// Ячейки раздела «дополнение».
    pub completion: Vec<Entry>,
}

/// Применяет `[entry]`, фильтры и порядок к таблице.
pub fn apply(table: &[Entry], eff: &Effective) -> Vec<Section> {
    apply_ext(table, eff, &Extra::default())
}

/// То же с разделами «по позиции курсора», «дополнение» и порядком
/// по происхождению: `pin` → курсор → дополнение → происхождения → группы.
pub fn apply_ext(table: &[Entry], eff: &Effective, extra: &Extra) -> Vec<Section> {
    let mut list: Vec<Entry> = table.to_vec();
    for (key, o) in &eff.entries {
        if let Some(e) = list.iter_mut().find(|e| &e.key == key) {
            if let Some(d) = &o.desc {
                e.desc = d.clone();
            }
            if let Some(g) = &o.group {
                e.group = g.clone();
            }
        } else {
            list.push(Entry {
                key: key.clone(),
                desc: o.desc.clone().unwrap_or_default(),
                group: o.group.clone().unwrap_or_else(|| "user".to_string()),
                origin: "user".to_string(),
                source: "user".to_string(),
                ..Default::default()
            });
        }
    }
    let hide: HashSet<&str> = eff.hide.iter().map(String::as_str).collect();
    let hide_groups: HashSet<&str> = eff.hide_groups.iter().map(String::as_str).collect();
    list.retain(|e| {
        !hide.contains(e.key.as_str())
            && !hide_groups.contains(e.group.as_str())
            && (!eff.only_modifiers || keys::has_modifier(&e.key))
    });
    let shown = |e: Entry| Shown {
        show_origin: eff.show_origin.label_for(&e.origin),
        entry: e,
        ..Default::default()
    };
    let mut out = Vec::new();
    let mut pinned = Vec::new();
    for p in &eff.pin {
        if let Some(i) = list.iter().position(|e| &e.key == p) {
            pinned.push(Shown { kind: SectionKind::Pin, ..shown(list.remove(i)) });
        }
    }
    if !pinned.is_empty() {
        out.push(Section {
            title: None,
            entries: pinned,
        });
    }
    // Раздел «по позиции курсора»: по одной записи на правило `[[applies]]`
    // с истинным `when` — самая короткая клавиша, при равенстве первая
    // по таблице; правила по порядку манифеста, не больше MAX_CURSOR.
    // Остальные применимые записи остаются в своих группах как обычные,
    // записи с ложным `when` — приглушёнными.
    let mut dims: HashSet<String> = HashSet::new();
    if let Some(rule) = extra.applies {
        let mut best: BTreeMap<usize, (usize, usize)> = BTreeMap::new();
        for (i, e) in list.iter().enumerate() {
            match rule(e) {
                Some((r, true)) => {
                    let w = e.key.chars().count();
                    let slot = best.entry(r).or_insert((w, i));
                    if w < slot.0 {
                        *slot = (w, i);
                    }
                }
                Some((_, false)) => {
                    dims.insert(e.key.clone());
                }
                None => {}
            }
        }
        let chosen: Vec<usize> = best.values().map(|&(_, i)| i).take(MAX_CURSOR).collect();
        if !chosen.is_empty() {
            let mut moved: Vec<Option<Entry>> = vec![None; chosen.len()];
            let mut rest = Vec::new();
            for (i, e) in list.into_iter().enumerate() {
                match chosen.iter().position(|&c| c == i) {
                    Some(p) => moved[p] = Some(e),
                    None => rest.push(e),
                }
            }
            list = rest;
            out.push(Section {
                title: Some(CURSOR_TITLE.to_string()),
                entries: moved
                    .into_iter()
                    .flatten()
                    .map(|e| Shown { kind: SectionKind::Cursor, ..shown(e) })
                    .collect(),
            });
        }
    }
    if !extra.completion.is_empty() {
        out.push(Section {
            title: Some(COMPLETION_TITLE.to_string()),
            entries: extra
                .completion
                .iter()
                .cloned()
                .map(|e| Shown { kind: SectionKind::Completion, ..shown(e) })
                .collect(),
        });
    }
    for o in &extra.origin_order {
        let (mut mine, rest): (Vec<Entry>, Vec<Entry>) = list.into_iter().partition(|e| &e.origin == o);
        list = rest;
        if mine.is_empty() {
            continue;
        }
        mine.sort_by(|a, b| a.key.cmp(&b.key));
        out.push(Section {
            title: Some(o.clone()),
            entries: mine.into_iter().map(|e| {
                let d = dims.contains(&e.key);
                Shown { dim: d, kind: SectionKind::Origin, ..shown(e) }
            }).collect(),
        });
    }
    let mut groups: BTreeMap<String, Vec<Entry>> = BTreeMap::new();
    for e in list {
        groups.entry(e.group.clone()).or_default().push(e);
    }
    let mut names: Vec<String> = groups.keys().cloned().collect();
    names.sort_by(|a, b| {
        let ia = eff.order.iter().position(|o| o == a);
        let ib = eff.order.iter().position(|o| o == b);
        match (ia, ib) {
            (Some(x), Some(y)) => x.cmp(&y),
            (Some(_), None) => std::cmp::Ordering::Less,
            (None, Some(_)) => std::cmp::Ordering::Greater,
            (None, None) => a.cmp(b),
        }
    });
    for n in names {
        let mut es = groups.remove(&n).unwrap_or_default();
        es.sort_by(|a, b| a.key.cmp(&b.key));
        out.push(Section {
            title: Some(n),
            entries: es
                .into_iter()
                .map(|e| {
                    let d = dims.contains(&e.key);
                    Shown { dim: d, ..shown(e) }
                })
                .collect(),
        });
    }
    out
}

/// Правка файла конфигурации из просмотрщика.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Edit {
    /// Дописать значение в список поля (`hide`, `hide_groups`) раздела контекста.
    Add { ctx: String, field: String, value: String },
    /// Убрать значение из списка поля раздела контекста.
    Remove { ctx: String, field: String, value: String },
}

/// Применяет правку к тексту, сохраняя комментарии и порядок.
pub fn edit_text(text: &str, edit: &Edit) -> Result<String, String> {
    use toml_edit::{Array, DocumentMut, Item, Table, Value};
    let mut doc: DocumentMut = text.parse().map_err(|e: toml_edit::TomlError| e.to_string())?;
    let (ctx, field, value, add) = match edit {
        Edit::Add { ctx, field, value } => (ctx, field, value, true),
        Edit::Remove { ctx, field, value } => (ctx, field, value, false),
    };
    if !doc.contains_key("context") {
        if !add {
            return Ok(doc.to_string());
        }
        let mut t = Table::new();
        t.set_implicit(true);
        doc.insert("context", Item::Table(t));
    }
    let contexts = doc["context"]
        .as_table_mut()
        .ok_or("context: нужна таблица")?;
    if !contexts.contains_key(ctx) {
        if !add {
            return Ok(doc.to_string());
        }
        contexts.insert(ctx, Item::Table(Table::new()));
    }
    let section = contexts[ctx.as_str()]
        .as_table_like_mut()
        .ok_or_else(|| format!("context.\"{ctx}\": нужна таблица"))?;
    if section.get(field).is_none() {
        if !add {
            return Ok(doc.to_string());
        }
        section.insert(field, Item::Value(Value::Array(Array::new())));
    }
    let arr = section
        .get_mut(field)
        .and_then(|i| i.as_array_mut())
        .ok_or_else(|| format!("context.\"{ctx}\".{field}: нужен список"))?;
    let pos = arr.iter().position(|v| v.as_str() == Some(value.as_str()));
    match (add, pos) {
        (true, None) => arr.push(value.as_str()),
        (false, Some(i)) => {
            arr.remove(i);
        }
        _ => {}
    }
    Ok(doc.to_string())
}

/// Настоящий путь файла: цель символической ссылки (в том числе висящей).
pub fn real_path(path: &Path) -> PathBuf {
    if let Ok(p) = std::fs::canonicalize(path) {
        return p;
    }
    let mut p = path.to_path_buf();
    for _ in 0..16 {
        match std::fs::read_link(&p) {
            Ok(t) => {
                p = if t.is_absolute() {
                    t
                } else {
                    p.parent().map(|d| d.join(&t)).unwrap_or(t)
                }
            }
            Err(_) => break,
        }
    }
    p
}

/// Записывает правку: чтение, правка, временный файл в каталоге настоящего
/// файла и `rename` поверх него (символическая ссылка остаётся ссылкой).
pub fn write_edit(path: &Path, edit: &Edit) -> Result<(), String> {
    let real = real_path(path);
    let text = std::fs::read_to_string(&real).unwrap_or_default();
    let new = edit_text(&text, edit)?;
    let dir = real.parent().ok_or("нет каталога файла конфигурации")?;
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let name = real
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "view.toml".to_string());
    let tmp = dir.join(format!(".{name}.{}.tmp", std::process::id()));
    std::fs::write(&tmp, new).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, &real).map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        e.to_string()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const EXAMPLE: &str = r#"
[defaults]
order = ["history", "completion", "edit", "motion"]
only_modifiers = false

[context."ble.vi_nmap"]
hide = ["h", "j", "k", "l", "w", "b", "e", "0", "$"]
pin  = ["C-r", "M-r", "M-h"]
hide_groups = ["motion"]

[context."ble.vi_imap"]
show_origin = ["readline", "ble"]
"#;

    fn e(key: &str, group: &str) -> Entry {
        Entry {
            key: key.into(),
            desc: key.into(),
            group: group.into(),
            origin: "ble".into(),
            ..Default::default()
        }
    }

    #[test]
    fn example_decision_6() {
        let cfg = parse(EXAMPLE).expect("parse");
        let eff = effective(&cfg, "ble.vi_nmap");
        let table = vec![
            e("h", "motion"),
            e("x", "edit"),
            e("C-r", "history"),
            e("M-h", "history"),
            e("TAB", "completion"),
            e("w", "motion"),
            e("M-r", "history"),
            e("u", "edit"),
            e("z", "zzz"),
        ];
        let s = apply(&table, &eff);
        assert_eq!(s[0].title, None);
        let pinned: Vec<&str> = s[0].entries.iter().map(|x| x.entry.key.as_str()).collect();
        assert_eq!(pinned, vec!["C-r", "M-r", "M-h"]);
        let titles: Vec<&str> = s[1..].iter().map(|x| x.title.as_deref().unwrap_or("")).collect();
        assert_eq!(titles, vec!["completion", "edit", "zzz"]);
    }

    #[test]
    fn patterns() {
        assert!(pattern_specificity("yazi.*", "yazi").is_some());
        assert!(pattern_specificity("yazi.*", "yazi.input").is_some());
        assert!(pattern_specificity("yazi", "yazi.input").is_some());
        assert!(pattern_specificity("*.generic", "htop.generic").is_some());
        assert!(pattern_specificity("yazi.input", "yazi.manager").is_none());
        let cfg = parse(
            "[context.\"yazi.*\"]\nhide_groups=[\"tabs\"]\n[context.\"yazi.input\"]\nhide=[\"C-a\"]\n",
        )
        .expect("p");
        let i = effective(&cfg, "yazi.input");
        assert_eq!(i.hide_groups, vec!["tabs"]);
        assert_eq!(i.hide, vec!["C-a"]);
        let m = effective(&cfg, "yazi.manager");
        assert!(m.hide.is_empty());
    }

    #[test]
    fn entry_added() {
        let cfg = parse("[entry.\"ble.vi_imap\".\"C-x C-k\"]\ndesc = \"проверка\"\ngroup = \"edit\"\n")
            .expect("p");
        let s = apply(&[], &effective(&cfg, "ble.vi_imap"));
        assert_eq!(s[0].title.as_deref(), Some("edit"));
        assert_eq!(s[0].entries[0].entry.origin, "user");
        assert_eq!(s[0].entries[0].entry.key, "C-x C-k");
    }

    #[test]
    fn edit_keeps_comments() {
        let text = "# комментарий\n[defaults]\norder = [\"a\"] # хвост\n";
        let add = Edit::Add {
            ctx: "ble.vi_nmap".into(),
            field: "hide".into(),
            value: "x".into(),
        };
        let out = edit_text(text, &add).expect("edit");
        assert!(out.contains("# комментарий"));
        assert!(out.contains("# хвост"));
        assert!(out.contains("[context.\"ble.vi_nmap\"]"));
        let cfg = parse(&out).expect("parse");
        assert_eq!(effective(&cfg, "ble.vi_nmap").hide, vec!["x"]);
        let back = edit_text(
            &out,
            &Edit::Remove {
                ctx: "ble.vi_nmap".into(),
                field: "hide".into(),
                value: "x".into(),
            },
        )
        .expect("edit");
        assert!(effective(&parse(&back).expect("p"), "ble.vi_nmap").hide.is_empty());
    }
}
