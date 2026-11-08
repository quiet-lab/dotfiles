//! Задача 12.8: ранжирование поиска (D16), порядок по происхождению (D15), раскладка колонок (D13).

mod common;

use common::*;
use keys_help::entry::Entry;
use keys_help::search::{rank, score};
use keys_help::ui::{self, columns_for_width, flatten, layout, Action, Key, UiState};
use keys_help::view::{self, Extra, Section, Shown};

fn e(key: &str, desc: &str) -> Entry {
    Entry { key: key.into(), desc: desc.into(), ..Default::default() }
}

fn pts(en: &Entry, pat: &str) -> Option<i64> {
    score(en, pat).map(|x| x.0)
}

// ---- D13: ширины ----

#[test]
fn columns_40_80_120_140_180() {
    let sections = vec![Section {
        title: Some("g".into()),
        entries: (0..60).map(|i| Shown { entry: e(&format!("k{i}"), "действие"), ..Default::default() }).collect(),
    }];
    for (w, n) in [(40usize, 1usize), (80, 2), (120, 3), (140, 4), (180, 5), (260, 5)] {
        assert_eq!(columns_for_width(w), n, "w={w}");
        let lay = layout(&sections, w);
        assert_eq!(lay.ncols, n, "w={w}");
        assert!(lay.columns.len() <= n);
        assert_eq!(lay.col_width, w / n);
    }
}

// ---- D16: ступени и очки ----

#[test]
fn step_points_exact() {
    // 1: ключ равен с учётом регистра.
    assert_eq!(pts(&e("C-r", "x"), "C-r"), Some(1000));
    // 2: равен без учёта регистра.
    assert_eq!(pts(&e("C-r", "x"), "c-R"), Some(900));
    // 3: ключ начинается с образца.
    assert_eq!(pts(&e("C-r C-x", "x"), "c-r"), Some(800));
    // 4: слово описания начинается с образца: 700 − 10 × номер слова.
    assert_eq!(pts(&e("Z", "история команд"), "ист"), Some(700));
    assert_eq!(pts(&e("Z", "поиск по истории"), "ист"), Some(680));
    // 5: подстрока ключа или описания: 500 − позиция / 4.
    assert_eq!(pts(&e("xxC-r", "y"), "c-r"), Some(500));
    assert_eq!(pts(&e("Z", "abcdefghijkl"), "ijk"), Some(500 - 2));
    // 6: подстрока desc_full или action.
    let mut full = e("Z", "y");
    full.desc_full = "Скрытый текст".into();
    assert_eq!(pts(&full, "рытый"), Some(300));
    let mut act = e("Z", "y");
    act.action = "kill-forward-cword".into();
    assert_eq!(pts(&act, "forward"), Some(300));
    // 7: нечёткое: 200 − число пропущенных символов, не ниже 1.
    assert_eq!(pts(&e("a-b", "y"), "ab"), Some(199));
    assert_eq!(pts(&e("Z", "удалить слово"), "удсл"), Some(200 - 6));
    let long = format!("a{}b", "x".repeat(400));
    assert_eq!(pts(&e("Z", &long), "ab"), Some(1));
    // Нет совпадения и пустой образец.
    assert_eq!(pts(&e("M-d", "удалить"), "zz"), None);
    assert_eq!(pts(&e("M-d", "удалить"), ""), None);
}

#[test]
fn best_step_wins_and_steps_are_ordered() {
    // Один образец, каждая запись попадает на свою ступень.
    let mut s6 = e("Z6", "nothing");
    s6.desc_full = "contains ab inside".into();
    let table = [
        e("q-a-b", "x"),              // 7 нечёткое (199)
        s6,                           // 6
        e("xxxxxxxxxab", "x"),        // 5 (позиция 9 → 498)
        e("Z", "a b ab"),             // 4: третье слово → 680 (слово «a», «b» не совпадают)
        e("ab-x", "x"),               // 3
        e("AB", "x"),                 // 2
        e("ab", "x"),                 // 1
    ];
    let r = rank(table.iter(), "ab");
    let order: Vec<usize> = r.iter().map(|x| x.0).collect();
    assert_eq!(order, vec![6, 5, 4, 3, 2, 1, 0], "{r:?}");
    let scores: Vec<i64> = r.iter().map(|x| x.1).collect();
    assert_eq!(scores, vec![1000, 900, 800, 680, 498, 300, 199]);
}

#[test]
fn equal_scores_keep_table_order() {
    let table = [e("a1", "поиск"), e("b1", "поиск"), e("c1", "поиск"), e("d1", "прочее")];
    let r = rank(table.iter(), "поиск");
    assert_eq!(r.iter().map(|x| x.0).collect::<Vec<_>>(), vec![0, 1, 2]);
    assert!(r.windows(2).all(|w| w[0].1 == w[1].1));
}

#[test]
fn fuzzy_match_and_highlight() {
    let en = e("M-d", "удалить слово");
    let (p, hl) = score(&en, "уд сл".replace(' ', "").as_str()).unwrap();
    assert_eq!(p, 194);
    assert_eq!(hl.desc, vec![0, 1, 8, 9]); // у д с л
    assert!(hl.key.is_empty());
    // Подсветка ступени 5 по ключу.
    let (_, hl) = score(&e("xxC-r", "y"), "c-r").unwrap();
    assert_eq!(hl.key, vec![2, 3, 4]);
    // Ступень 1 — вся клавиша; ступень 6 — без подсветки.
    assert_eq!(score(&e("C-r", "x"), "C-r").unwrap().1.key, vec![0, 1, 2]);
    let mut a = e("Z", "y");
    a.action = "kill-line".into();
    assert_eq!(score(&a, "kill").unwrap().1, Default::default());
}

#[test]
fn case_insensitive_cyrillic() {
    assert_eq!(pts(&e("M-h", "История"), "истор"), Some(700));
    assert_eq!(pts(&e("M-h", "история"), "ИСТОР"), Some(700));
}

fn search_view() -> Vec<Section> {
    let items = [
        ("C-a", "в начало строки"),
        ("C-r", "история"),
        ("M-r", "строка истории"),
        ("C-x C-r", "x"),
        ("M-d", "вырезать строку"),
    ];
    vec![Section {
        title: Some("g".into()),
        entries: items.iter().map(|(k, d)| Shown { entry: e(k, d), ..Default::default() }).collect(),
    }]
}

#[test]
fn search_sections_sorted_with_highlight() {
    let base = search_view();
    let ss = ui::search_sections(&base, "стро");
    assert_eq!(ss.len(), 1, "вместо таблицы — один список совпадений");
    let keys: Vec<&str> = ss[0].entries.iter().map(|x| x.entry.key.as_str()).collect();
    // Слово «строки» первым словом описания (700) у M-r? «строка истории» — первое слово → 700;
    // «вырезать строку» — второе → 690; «в начало строки» — третье → 680.
    assert_eq!(keys, vec!["M-r", "M-d", "C-a"]);
    assert!(ss[0].entries.iter().all(|x| !x.hl.desc.is_empty()));
    assert!(ss[0].title.as_deref().unwrap().contains("стро"));
    // Базовая таблица не изменена.
    assert_eq!(flatten(&base).len(), 5);
}

#[test]
fn n_and_big_n_follow_relevance_order_circularly() {
    let base = search_view();
    let mut st = UiState { selected: 3, ..Default::default() };
    let lay0 = layout(&base, 200);
    let es0 = flatten(&base);
    st.handle(Key::Char('/'), &lay0, &es0);
    for c in "стро".chars() {
        st.handle(Key::Char(c), &lay0, &es0);
    }
    st.handle(Key::Enter, &lay0, &es0);
    let ss = ui::search_sections(&base, st.search.as_deref().unwrap());
    let lay = layout(&ss, 200);
    let es = flatten(&ss);
    assert_eq!(st.selected, 0, "выбор — на самом релевантном");
    let sel_key = |st: &UiState| es[st.selected].entry.key.clone();
    assert_eq!(sel_key(&st), "M-r");
    st.handle(Key::Char('n'), &lay, &es);
    assert_eq!(sel_key(&st), "M-d");
    st.handle(Key::Char('n'), &lay, &es);
    assert_eq!(sel_key(&st), "C-a");
    st.handle(Key::Char('n'), &lay, &es);
    assert_eq!(sel_key(&st), "M-r", "по кругу вперёд");
    st.handle(Key::Char('N'), &lay, &es);
    assert_eq!(sel_key(&st), "C-a", "по кругу назад");
    st.handle(Key::Char('N'), &lay, &es);
    assert_eq!(sel_key(&st), "M-d");
    // Esc: поиск снят, прежний выбор возвращён.
    assert_eq!(st.handle(Key::Esc, &lay, &es), Action::Redraw);
    assert!(st.search.is_none());
    assert_eq!(st.selected, 3);
}

#[test]
fn key_equal_beats_description_matches() {
    // «C-r» точно — выше всех записей, где образец только в описании.
    let table = [e("M-x", "C-r в тексте"), e("C-r C-x", "y"), e("C-r", "история")];
    let r = rank(table.iter(), "C-r");
    assert_eq!(r[0].0, 2);
    assert_eq!(r[1].0, 1);
}

// ---- D15: порядок по происхождению ----

fn origin(key: &str, group: &str, origin: &str) -> Entry {
    Entry { key: key.into(), desc: key.into(), group: group.into(), origin: origin.into(), ..Default::default() }
}

fn titles(s: &[Section]) -> Vec<Option<&str>> {
    s.iter().map(|x| x.title.as_deref()).collect()
}

#[test]
fn ble_manifest_declares_origin_order() {
    let m = manifest_named("ble");
    assert_eq!(m.origin_order, vec!["atuin", "tv", "fzf", "user"]);
}

#[test]
fn origin_sections_after_pin_in_given_order_then_groups() {
    let cfg = view::parse("[context.\"ble.*\"]\npin = [\"C-r\"]\n").unwrap();
    let eff = view::effective(&cfg, "ble.vi_imap");
    let table = [
        origin("C-r", "history", "ble"),
        origin("C-a", "edit", "readline"),
        origin("M-f", "tools", "fzf"),
        origin("M-r", "history", "atuin"),
        origin("M-t", "tools", "tv"),
        origin("M-h", "history", "fzf"),
        origin("M-z", "tools", "user"),
        origin("C-b", "edit", "ble"),
    ];
    let extra = Extra { origin_order: manifest_named("ble").origin_order, ..Default::default() };
    let s = view::apply_ext(&table, &eff, &extra);
    assert_eq!(titles(&s), vec![None, Some("atuin"), Some("tv"), Some("fzf"), Some("user"), Some("edit")]);
    let keys = |i: usize| s[i].entries.iter().map(|x| x.entry.key.as_str()).collect::<Vec<_>>();
    assert_eq!(keys(0), vec!["C-r"]);
    assert_eq!(keys(1), vec!["M-r"]);
    assert_eq!(keys(3), vec!["M-f", "M-h"], "внутри происхождения — по клавише");
    // Происхождения вне origin_order остаются в группах.
    assert_eq!(keys(5), vec!["C-a", "C-b"]);
}

#[test]
fn origin_order_with_hide_and_empty_origin() {
    let cfg = view::parse("[defaults]\nhide = [\"M-r\"]\n").unwrap();
    let table = [origin("M-r", "g", "atuin"), origin("M-t", "g", "tv")];
    let extra = Extra { origin_order: vec!["atuin".into(), "tv".into()], ..Default::default() };
    let s = view::apply_ext(&table, &view::effective(&cfg, "c"), &extra);
    // Скрытая запись раздел не создаёт.
    assert_eq!(titles(&s), vec![Some("tv")]);
}

#[test]
fn view_levels_defaults_then_manifest_then_context() {
    let cfg = view::parse(
        r#"
[defaults]
order = ["d"]
hide = ["a"]
only_modifiers = true

[context."ble.*"]
hide = ["c"]
order = ["ctx"]
"#,
    )
    .unwrap();
    let man = view::parse_level(
        &"order = [\"m\"]\nhide = [\"b\"]\nhide_groups = [\"gm\"]\nonly_modifiers = false\n"
            .parse::<toml::Table>()
            .unwrap(),
        "view",
    )
    .unwrap();
    // Без манифеста — только умолчания и контекст.
    let none = view::effective_with(&cfg, "ble.vi_imap", None);
    assert_eq!(none.order, vec!["ctx"]);
    assert_eq!(none.hide, vec!["a", "c"]);
    // С [view] манифеста: уровень между defaults и контекстом.
    let eff = view::effective_with(&cfg, "ble.vi_imap", Some(&man));
    assert_eq!(eff.hide, vec!["a", "b", "c"], "hide объединяются");
    assert_eq!(eff.hide_groups, vec!["gm"]);
    assert_eq!(eff.order, vec!["ctx"], "контекст заменяет order манифеста");
    assert!(!eff.only_modifiers, "манифест заменяет defaults");
    // Контекст, к которому шаблон не подходит: порядок манифеста выше умолчаний файла.
    let other = view::effective_with(&cfg, "nvim.normal", Some(&man));
    assert_eq!(other.order, vec!["m"]);
    assert_eq!(other.hide, vec!["a", "b"]);
}

#[test]
fn manifest_view_section_errors() {
    use std::path::Path;
    let bad_order = "program = \"x\"\n[view]\norigin_order = \"atuin\"\n";
    assert!(keys_help::manifest::parse(bad_order, Path::new("/x/x.toml")).is_err());
    let bad_field = "program = \"x\"\n[view]\nnope = 1\n";
    assert!(keys_help::manifest::parse(bad_field, Path::new("/x/x.toml")).is_err());
    let ok = "program = \"x\"\n[view]\norigin_order = [\"a\"]\nhide = [\"q\"]\n";
    let m = keys_help::manifest::parse(ok, Path::new("/x/x.toml")).unwrap();
    assert_eq!(m.origin_order, vec!["a"]);
    assert_eq!(m.view.hide.as_deref(), Some(&["q".to_string()][..]));
}
