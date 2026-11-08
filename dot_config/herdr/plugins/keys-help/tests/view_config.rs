//! Задачи 6.1–6.3: конфигурация представления — слияние, показ, запись файла.

mod common;

use keys_help::entry::Entry;
use keys_help::view::{self, Edit, ShowOrigin};

/// Пример из решения 6 записки задачи, дословно.
const DECISION_6: &str = r#"
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

fn e(key: &str, group: &str, origin: &str) -> Entry {
    Entry {
        key: key.into(),
        desc: format!("действие {key}"),
        group: group.into(),
        origin: origin.into(),
        ..Default::default()
    }
}

fn titles(s: &[view::Section]) -> Vec<Option<&str>> {
    s.iter().map(|x| x.title.as_deref()).collect()
}

fn shown_keys(s: &[view::Section]) -> Vec<&str> {
    s.iter()
        .flat_map(|x| x.entries.iter().map(|e| e.entry.key.as_str()))
        .collect()
}

fn nmap_table() -> Vec<Entry> {
    let mut t = Vec::new();
    for k in ["h", "j", "k", "l", "w", "b", "e", "0", "$"] {
        t.push(e(k, "motion", "ble"));
    }
    t.push(e("C-r", "history", "ble"));
    t.push(e("M-r", "history", "atuin"));
    t.push(e("M-h", "history", "fzf"));
    t.push(e("C-p", "history", "readline"));
    t.push(e("TAB", "completion", "ble"));
    t.push(e("x", "edit", "readline"));
    t.push(e("C-w", "other", "ble"));
    t.push(e("gg", "motion", "ble"));
    t
}

// ---- 6.1 слияние ----

#[test]
fn decision_6_example_ble_vi_nmap() {
    let cfg = view::parse(DECISION_6).expect("parse");
    let eff = view::effective(&cfg, "ble.vi_nmap");
    assert_eq!(eff.hide.len(), 9);
    assert_eq!(eff.hide_groups, vec!["motion"]);
    assert_eq!(eff.pin, vec!["C-r", "M-r", "M-h"]);
    // order взят из [defaults] (в разделе контекста его нет).
    assert_eq!(eff.order, vec!["history", "completion", "edit", "motion"]);
    assert!(!eff.only_modifiers);
    assert_eq!(eff.show_origin, ShowOrigin::None);

    let s = view::apply(&nmap_table(), &eff);
    // Скрытых записей и группы motion нет.
    let ks = shown_keys(&s);
    for hidden in ["h", "j", "k", "l", "w", "b", "e", "0", "$", "gg"] {
        assert!(!ks.contains(&hidden), "{hidden} показана");
    }
    // Первыми закреплённые в заданном порядке, затем группы history, completion, edit.
    assert_eq!(&ks[..3], ["C-r", "M-r", "M-h"]);
    assert_eq!(s[0].title, None);
    assert_eq!(
        titles(&s),
        vec![None, Some("history"), Some("completion"), Some("edit"), Some("other")]
    );
    assert!(!titles(&s).contains(&Some("motion")));
}

#[test]
fn decision_6_example_ble_vi_imap_show_origin_list() {
    let cfg = view::parse(DECISION_6).expect("parse");
    let eff = view::effective(&cfg, "ble.vi_imap");
    assert_eq!(
        eff.show_origin,
        ShowOrigin::List(vec!["readline".into(), "ble".into()])
    );
    assert!(eff.hide.is_empty());
    let s = view::apply(&nmap_table(), &eff);
    for sec in &s {
        for sh in &sec.entries {
            let want = matches!(sh.entry.origin.as_str(), "readline" | "ble");
            assert_eq!(sh.show_origin, want, "{}", sh.entry.key);
        }
    }
}

#[test]
fn levels_apply_defaults_program_mode() {
    let cfg = view::parse(
        r#"
[defaults]
hide = ["a"]
hide_groups = ["g0"]
order = ["d1"]
pin = ["z"]
only_modifiers = true
show_origin = true

[context."yazi.*"]
hide = ["b"]
hide_groups = ["g1"]
order = ["y1"]
show_origin = false

[context."yazi.input"]
hide = ["c", "a"]
order = ["i1"]
only_modifiers = false
"#,
    )
    .expect("parse");
    let eff = view::effective(&cfg, "yazi.input");
    // hide и hide_groups объединяются без повторов.
    assert_eq!(eff.hide, vec!["a", "b", "c"]);
    assert_eq!(eff.hide_groups, vec!["g0", "g1"]);
    // Прочие поля заменяются более частным уровнем.
    assert_eq!(eff.order, vec!["i1"]);
    assert!(!eff.only_modifiers);
    assert_eq!(eff.show_origin, ShowOrigin::None);
    assert_eq!(eff.pin, vec!["z"]);

    let man = view::effective(&cfg, "yazi.manager");
    assert_eq!(man.hide, vec!["a", "b"]);
    assert_eq!(man.order, vec!["y1"]);
    assert!(man.only_modifiers);

    let other = view::effective(&cfg, "nvim.normal");
    assert_eq!(other.hide, vec!["a"]);
    assert_eq!(other.order, vec!["d1"]);
    assert_eq!(other.show_origin, ShowOrigin::All);
}

#[test]
fn program_pattern_matches_program_and_modes() {
    let cfg = view::parse(
        "[context.\"yazi.*\"]\nhide_groups=[\"tabs\"]\n[context.\"yazi.input\"]\nhide=[\"C-a\"]\n",
    )
    .expect("parse");
    let input = view::effective(&cfg, "yazi.input");
    assert_eq!(input.hide_groups, vec!["tabs"]);
    assert_eq!(input.hide, vec!["C-a"]);
    let man = view::effective(&cfg, "yazi.manager");
    assert_eq!(man.hide_groups, vec!["tabs"]);
    assert!(man.hide.is_empty());
    // `x.*` подходит и к самой программе без режима.
    assert_eq!(view::effective(&cfg, "yazi").hide_groups, vec!["tabs"]);
    assert!(view::effective(&cfg, "nvim.normal").hide_groups.is_empty());
}

#[test]
fn generic_pattern() {
    let cfg = view::parse("[context.\"*.generic\"]\nonly_modifiers = true\n").expect("parse");
    assert!(view::effective(&cfg, "htop.generic").only_modifiers);
    assert!(view::effective(&cfg, "less.generic").only_modifiers);
    assert!(!view::effective(&cfg, "ble.vi_imap").only_modifiers);
    let t = vec![
        e("C-x", "g", "generic"),
        e("M-f", "g", "generic"),
        e("q", "g", "generic"),
        e("C-x C-k", "g", "generic"),
        e("g g", "g", "generic"),
    ];
    let s = view::apply(&t, &view::effective(&cfg, "htop.generic"));
    assert_eq!(shown_keys(&s), vec!["C-x", "C-x C-k", "M-f"]);
}

#[test]
fn entry_section_and_errors() {
    let cfg = view::parse(
        "[entry.\"ble.vi_imap\".\"C-x C-k\"]\ndesc = \"проверка\"\ngroup = \"edit\"\n\
         [entry.\"ble.*\".\"<C-r>\"]\ndesc = \"мой поиск\"\n",
    )
    .expect("parse");
    let eff = view::effective(&cfg, "ble.vi_imap");
    let table = vec![e("C-r", "history", "ble")];
    let s = view::apply(&table, &eff);
    let all: Vec<&Entry> = s.iter().flat_map(|x| x.entries.iter().map(|e| &e.entry)).collect();
    let cr = all.iter().find(|x| x.key == "C-r").expect("C-r");
    assert_eq!(cr.desc, "мой поиск");
    assert_eq!(cr.group, "history");
    let added = all.iter().find(|x| x.key == "C-x C-k").expect("добавленная");
    assert_eq!(added.desc, "проверка");
    assert_eq!(added.group, "edit");
    assert_eq!(added.origin, "user");
    assert_eq!(added.source, "user");

    // Ошибки разбора возвращаются, а не паникуют.
    assert!(view::parse("[defaults\n").is_err());
    assert!(view::parse("[defaults]\nbogus = 1\n").is_err());
    assert!(view::parse("[nothing]\n").is_err());
    assert!(view::parse("[defaults]\nhide = 5\n").is_err());
}

// ---- 6.2 фильтрация и порядок ----

#[test]
fn hide_and_hide_groups() {
    let cfg = view::parse("[context.\"c\"]\nhide = [\"<C-a>\", \"x\"]\nhide_groups = [\"g2\"]\n").expect("p");
    let t = vec![
        e("C-a", "g1", ""),
        e("x", "g1", ""),
        e("y", "g1", ""),
        e("z", "g2", ""),
    ];
    let s = view::apply(&t, &view::effective(&cfg, "c"));
    // Ключи hide нормализуются: <C-a> скрывает C-a.
    assert_eq!(shown_keys(&s), vec!["y"]);
    assert_eq!(titles(&s), vec![Some("g1")]);
}

#[test]
fn pin_goes_first_in_given_order_and_skips_missing() {
    let cfg = view::parse("[context.\"c\"]\npin = [\"z\", \"nope\", \"a\"]\n").expect("p");
    let t = vec![e("a", "g", ""), e("m", "g", ""), e("z", "h", "")];
    let s = view::apply(&t, &view::effective(&cfg, "c"));
    assert_eq!(s[0].title, None);
    assert_eq!(shown_keys(&s[..1]), vec!["z", "a"]);
    assert_eq!(shown_keys(&s[1..]), vec!["m"]);
}

#[test]
fn order_then_alphabetical() {
    let cfg = view::parse("[defaults]\norder = [\"history\", \"edit\"]\n").expect("p");
    let t = vec![
        e("1", "zeta", ""),
        e("2", "edit", ""),
        e("3", "alpha", ""),
        e("4", "history", ""),
    ];
    let s = view::apply(&t, &view::effective(&cfg, "c"));
    assert_eq!(titles(&s), vec![Some("history"), Some("edit"), Some("alpha"), Some("zeta")]);
}

#[test]
fn only_modifiers_checks_first_key() {
    let cfg = view::parse("[defaults]\nonly_modifiers = true\n").expect("p");
    let t = vec![
        e("C-r", "g", ""),
        e("M-f", "g", ""),
        e("C-M-t", "g", ""),
        e("q", "g", ""),
        e("S-TAB", "g", ""),
        e("g C-x", "g", ""),
        e("C-x C-k", "g", ""),
    ];
    let s = view::apply(&t, &view::effective(&cfg, "c"));
    assert_eq!(shown_keys(&s), vec!["C-M-t", "C-r", "C-x C-k", "M-f"]);
}

#[test]
fn show_origin_variants() {
    let t = vec![e("a", "g", "ble"), e("b", "g", "user")];
    for (toml, want) in [
        ("[defaults]\nshow_origin = true\n", [true, true]),
        ("[defaults]\nshow_origin = false\n", [false, false]),
        ("[defaults]\nshow_origin = [\"user\"]\n", [false, true]),
        ("", [false, false]),
    ] {
        let cfg = view::parse(toml).expect("p");
        let s = view::apply(&t, &view::effective(&cfg, "c"));
        let got: Vec<bool> = s[0].entries.iter().map(|x| x.show_origin).collect();
        assert_eq!(got, want, "{toml}");
    }
}

// ---- 6.3 запись d/D/u ----

const WITH_COMMENTS: &str = "# шапка файла\n[defaults]\norder = [\"a\"] # хвост строки\n\n# про контекст\n[context.\"ble.vi_nmap\"]\nhide = [\"h\"] # скрыто\n";

fn add(ctx: &str, field: &str, v: &str) -> Edit {
    Edit::Add { ctx: ctx.into(), field: field.into(), value: v.into() }
}

fn remove(ctx: &str, field: &str, v: &str) -> Edit {
    Edit::Remove { ctx: ctx.into(), field: field.into(), value: v.into() }
}

#[test]
fn edit_keeps_comments_and_order() {
    let out = view::edit_text(WITH_COMMENTS, &add("ble.vi_nmap", "hide", "x")).expect("edit");
    for c in ["# шапка файла", "# хвост строки", "# про контекст", "# скрыто"] {
        assert!(out.contains(c), "потерян комментарий {c}:\n{out}");
    }
    assert!(out.find("[defaults]").unwrap() < out.find("[context").unwrap());
    let eff = view::effective(&view::parse(&out).expect("parse"), "ble.vi_nmap");
    assert_eq!(eff.hide, vec!["h", "x"]);
    // Повторное добавление не дублирует.
    let again = view::edit_text(&out, &add("ble.vi_nmap", "hide", "x")).expect("edit");
    assert_eq!(view::effective(&view::parse(&again).unwrap(), "ble.vi_nmap").hide, vec!["h", "x"]);
}

#[test]
fn edit_creates_missing_section_and_hide_groups() {
    let out = view::edit_text("# только комментарий\n", &add("yazi.manager", "hide_groups", "tabs")).expect("e");
    assert!(out.contains("# только комментарий"));
    assert!(out.contains("[context.\"yazi.manager\"]"));
    let eff = view::effective(&view::parse(&out).expect("p"), "yazi.manager");
    assert_eq!(eff.hide_groups, vec!["tabs"]);

    let out2 = view::edit_text("", &add("c", "hide", "x")).expect("e");
    assert_eq!(view::effective(&view::parse(&out2).expect("p"), "c").hide, vec!["x"]);

    // Новый раздел рядом с существующим другого контекста.
    let out3 = view::edit_text(WITH_COMMENTS, &add("nvim.normal", "hide", "q")).expect("e");
    let cfg = view::parse(&out3).expect("p");
    assert_eq!(view::effective(&cfg, "nvim.normal").hide, vec!["q"]);
    assert_eq!(view::effective(&cfg, "ble.vi_nmap").hide, vec!["h"]);
}

#[test]
fn edit_undo_removes_and_keeps_rest() {
    let out = view::edit_text(WITH_COMMENTS, &add("ble.vi_nmap", "hide", "x")).expect("e");
    let back = view::edit_text(&out, &remove("ble.vi_nmap", "hide", "x")).expect("e");
    assert!(back.contains("# скрыто"));
    assert_eq!(view::effective(&view::parse(&back).unwrap(), "ble.vi_nmap").hide, vec!["h"]);
    // Отмена того, чего нет, ничего не портит.
    let same = view::edit_text(WITH_COMMENTS, &remove("zzz", "hide", "x")).expect("e");
    assert_eq!(same, WITH_COMMENTS);
}

#[test]
fn edit_rejects_broken_file() {
    assert!(view::edit_text("[defaults\n", &add("c", "hide", "x")).is_err());
}

#[test]
fn write_edit_creates_file_and_dirs() {
    let d = common::tmpdir("view-new");
    let p = d.join("sub/view.toml");
    view::write_edit(&p, &add("c", "hide", "x")).expect("write");
    let eff = view::effective(&view::parse(&std::fs::read_to_string(&p).unwrap()).unwrap(), "c");
    assert_eq!(eff.hide, vec!["x"]);
}

#[test]
fn write_edit_keeps_symlink() {
    use std::os::unix::fs::symlink;
    let d = common::tmpdir("view-link");
    let real_dir = d.join("source");
    std::fs::create_dir_all(&real_dir).unwrap();
    let real = real_dir.join("view.toml");
    std::fs::write(&real, WITH_COMMENTS).unwrap();
    let home_dir = d.join("home");
    std::fs::create_dir_all(&home_dir).unwrap();
    let link = home_dir.join("view.toml");
    symlink(&real, &link).unwrap();

    view::write_edit(&link, &add("ble.vi_nmap", "hide", "x")).expect("write");

    let meta = std::fs::symlink_metadata(&link).unwrap();
    assert!(meta.file_type().is_symlink(), "ссылка заменена файлом");
    assert_eq!(std::fs::read_link(&link).unwrap(), real);
    let text = std::fs::read_to_string(&real).unwrap();
    assert!(text.contains("# шапка файла") && text.contains("# хвост строки"));
    assert_eq!(view::effective(&view::parse(&text).unwrap(), "ble.vi_nmap").hide, vec!["h", "x"]);
    // Временных файлов не осталось.
    let left: Vec<_> = std::fs::read_dir(&real_dir).unwrap().flatten().collect();
    assert_eq!(left.len(), 1, "{left:?}");
}

#[test]
fn write_edit_keeps_relative_symlink() {
    use std::os::unix::fs::symlink;
    let d = common::tmpdir("view-rel");
    std::fs::create_dir_all(d.join("a")).unwrap();
    std::fs::write(d.join("a/real.toml"), "# c\n").unwrap();
    symlink("a/real.toml", d.join("view.toml")).unwrap();
    view::write_edit(&d.join("view.toml"), &add("c", "hide", "x")).expect("write");
    assert!(std::fs::symlink_metadata(d.join("view.toml")).unwrap().file_type().is_symlink());
    assert!(std::fs::read_to_string(d.join("a/real.toml")).unwrap().contains("# c"));
}
