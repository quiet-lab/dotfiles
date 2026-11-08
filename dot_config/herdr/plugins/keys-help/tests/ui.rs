//! Задачи 6.11 и 6.12: раскладка колонок, показ ячеек, навигация, поиск, подробности.

use keys_help::entry::Entry;
use keys_help::ui::{
    self, columns_for_width, flatten, layout, parse_input, Action, Cell, Header, Key, UiState,
    PINNED_TITLE,
};
use keys_help::view::{Section, Shown};

fn shown(key: &str, desc: &str) -> Shown {
    Shown {
        entry: Entry {
            key: key.into(),
            desc: desc.into(),
            ..Default::default()
        },
        show_origin: false,
    }
}

fn sec(title: Option<&str>, items: &[(&str, &str)]) -> Section {
    Section {
        title: title.map(str::to_string),
        entries: items
            .iter()
            .map(|(k, d)| {
                let mut s = shown(k, d);
                s.entry.group = title.unwrap_or_default().to_string();
                s
            })
            .collect(),
    }
}

/// `n` записей `k0..` в одной группе.
fn numbered(n: usize) -> Vec<Section> {
    let items: Vec<(String, String)> = (0..n).map(|i| (format!("k{i}"), format!("действие {i}"))).collect();
    let refs: Vec<(&str, &str)> = items.iter().map(|(a, b)| (a.as_str(), b.as_str())).collect();
    vec![sec(Some("группа"), &refs)]
}

fn strip_ansi(s: &str) -> String {
    let mut out = String::new();
    let mut it = s.chars().peekable();
    while let Some(c) = it.next() {
        if c == '\x1b' {
            if it.peek() == Some(&'[') {
                it.next();
                for d in it.by_ref() {
                    if d.is_ascii_alphabetic() {
                        break;
                    }
                }
            }
        } else {
            out.push(c);
        }
    }
    out
}

fn width_of(s: &str) -> usize {
    unicode_width::UnicodeWidthStr::width(s)
}

// ---- 6.11 раскладка ----

#[test]
fn columns_by_width_spec() {
    assert_eq!(columns_for_width(140), 5);
    assert_eq!(columns_for_width(120), 4);
    assert_eq!(columns_for_width(90), 3);
    // Границы: 140 и 112.
    assert_eq!(columns_for_width(139), 4);
    assert_eq!(columns_for_width(141), 5);
    assert_eq!(columns_for_width(112), 4);
    assert_eq!(columns_for_width(111), 3);
    assert_eq!(columns_for_width(40), 3);
    assert_eq!(ui::CELL_MIN, 28);
}

#[test]
fn layout_ncols_follow_width() {
    let s = numbered(40);
    assert_eq!(layout(&s, 90).ncols, 3);
    assert_eq!(layout(&s, 120).ncols, 4);
    assert_eq!(layout(&s, 140).ncols, 5);
    assert_eq!(layout(&s, 90).col_width, 30);
    assert_eq!(layout(&s, 120).col_width, 30);
    assert_eq!(layout(&s, 140).col_width, 28);
}

#[test]
fn entries_flow_top_to_bottom_then_next_column() {
    for w in [90usize, 120, 140] {
        let s = numbered(30);
        let lay = layout(&s, w);
        assert!(lay.columns.len() <= lay.ncols, "w={w}");
        assert!(lay.columns.iter().all(|c| c.len() <= lay.rows));
        let mut prev = (0usize, 0usize);
        for (i, p) in lay.pos.iter().enumerate() {
            if i > 0 {
                assert!(*p > prev, "w={w}: порядок записей {i} нарушен {prev:?} -> {p:?}");
            }
            prev = *p;
        }
        // Все записи на месте ровно по разу.
        let n = lay.columns.iter().flatten().filter(|c| matches!(c, Cell::Entry(_))).count();
        assert_eq!(n, 30);
    }
}

#[test]
fn group_headers_present_and_pinned_title() {
    let s = vec![
        sec(None, &[("C-r", "поиск")]),
        sec(Some("history"), &[("a", "a1"), ("b", "b1")]),
        sec(Some("edit"), &[("c", "c1")]),
    ];
    let lay = layout(&s, 120);
    let headers: Vec<&str> = lay
        .columns
        .iter()
        .flatten()
        .filter_map(|c| match c {
            Cell::Header(t) => Some(t.as_str()),
            _ => None,
        })
        .collect();
    assert_eq!(headers, vec![PINNED_TITLE, "history", "edit"]);
    // Заголовок идёт прямо перед записями своей группы в той же колонке.
    for (ci, col) in lay.columns.iter().enumerate() {
        for (ri, c) in col.iter().enumerate() {
            if matches!(c, Cell::Header(_)) {
                assert!(
                    matches!(col.get(ri + 1), Some(Cell::Entry(_))),
                    "заголовок без записи в колонке {ci}"
                );
            }
        }
    }
}

#[test]
fn empty_sections_skipped() {
    let s = vec![sec(Some("пусто"), &[]), sec(Some("g"), &[("a", "x")])];
    let lay = layout(&s, 90);
    let n = lay.columns.iter().flatten().filter(|c| matches!(c, Cell::Header(_))).count();
    assert_eq!(n, 1);
    assert_eq!(flatten(&s).len(), 1);
}

#[test]
fn render_truncates_long_description_with_ellipsis() {
    let long = "очень длинное описание действия которое не помещается в ячейку";
    let s = vec![sec(Some("g"), &[("C-x", long), ("q", "выйти")])];
    let mut st = UiState::default();
    let hd = Header { ctx: "demo.main".into(), target: "1-2".into(), message: None };
    let lines = ui::render(&mut st, &hd, &s, 90, 20);
    let plain: Vec<String> = lines.iter().map(|l| strip_ansi(l)).collect();
    let row = plain.iter().find(|l| l.contains("C-x")).expect("строка клавиши");
    assert!(row.contains('…'), "{row:?}");
    assert!(!row.contains("ячейку"), "описание не обрезано: {row:?}");
    assert!(row.contains("выйти"), "короткое описание обрезано: {row:?}");
    for l in &plain[1..] {
        assert!(width_of(l) <= 90, "строка шире панели: {l:?}");
    }
}

#[test]
fn render_header_has_context_and_target() {
    let s = numbered(3);
    let mut st = UiState::default();
    let hd = Header { ctx: "ble.vi_nmap".into(), target: "w1-3".into(), message: Some("ошибка конфигурации".into()) };
    let lines = ui::render(&mut st, &hd, &s, 120, 10);
    let head = strip_ansi(&lines[0]);
    assert!(head.contains("ble.vi_nmap") && head.contains("w1-3"), "{head}");
    assert!(head.contains("ошибка конфигурации"), "{head}");
}

#[test]
fn render_column_count_matches_width() {
    // 60 записей: на ширине 140 строка таблицы содержит 5 ячеек, на 90 — 3.
    let s = numbered(60);
    for (w, n) in [(90usize, 3usize), (120, 4), (140, 5)] {
        let mut st = UiState::default();
        let lines = ui::render(&mut st, &Header::default(), &s, w, 100);
        let plain: Vec<String> = lines.iter().map(|l| strip_ansi(l)).collect();
        let cells = plain
            .iter()
            .skip(1)
            .map(|l| l.matches("действие").count())
            .max()
            .unwrap();
        assert_eq!(cells, n, "w={w}");
    }
}

#[test]
fn parse_input_keys() {
    assert_eq!(parse_input(b"\x1b"), vec![Key::Esc]);
    assert_eq!(parse_input(b"\x1b[27u"), vec![Key::Esc]);
    assert_eq!(parse_input(b"\x1b[A\x1b[B\x1b[C\x1b[D"), vec![Key::Up, Key::Down, Key::Right, Key::Left]);
    assert_eq!(parse_input(b"jK\r"), vec![Key::Char('j'), Key::Char('K'), Key::Enter]);
    assert_eq!(parse_input(b"\x7f"), vec![Key::Backspace]);
    assert_eq!(parse_input("и".as_bytes()), vec![Key::Char('и')]);
}

// ---- 6.12 навигация ----

fn setup(n: usize, w: usize) -> (Vec<Section>, ui::Layout) {
    let s = numbered(n);
    let lay = layout(&s, w);
    (s, lay)
}

#[test]
fn hjkl_on_layouts_3_4_5() {
    for w in [90usize, 120, 140] {
        let (s, lay) = setup(30, w);
        let es = flatten(&s);
        assert_eq!(lay.ncols, columns_for_width(w));
        // h/l: ячейка той же строки в соседней колонке.
        for i in 0..es.len() {
            let (c, r) = lay.pos[i];
            let mut st = UiState { selected: i, ..Default::default() };
            st.handle(Key::Char('l'), &lay, &es);
            if c + 1 < lay.columns.len() && lay.columns[c + 1].len() > r {
                // Соседняя колонка имеет строку r — запись или заголовок.
                if let Some(Cell::Entry(j)) = lay.columns[c + 1].get(r) {
                    assert_eq!(st.selected, *j, "w={w} i={i}");
                    assert_eq!(lay.pos[st.selected], (c + 1, r));
                    let mut back = UiState { selected: *j, ..Default::default() };
                    back.handle(Key::Char('h'), &lay, &es);
                    assert_eq!(lay.pos[back.selected].0, c, "w={w}: h не вернул колонку");
                    assert_eq!(back.selected, i, "w={w}: h не вернул ту же строку");
                }
            }
        }
        // h в первой колонке остаётся на месте.
        let mut st = UiState::default();
        st.handle(Key::Char('h'), &lay, &es);
        assert_eq!(st.selected, 0);
        // l из последней колонки остаётся на месте.
        let last = es.len() - 1;
        let mut st = UiState { selected: last, ..Default::default() };
        st.handle(Key::Char('l'), &lay, &es);
        assert_eq!(lay.pos[st.selected].0, lay.pos[last].0, "w={w}");

        // j/k: следующая/предыдущая запись; края не выходят за таблицу.
        let mut st = UiState::default();
        assert_eq!(st.handle(Key::Char('j'), &lay, &es), Action::Redraw);
        assert_eq!(st.selected, 1);
        st.handle(Key::Char('k'), &lay, &es);
        assert_eq!(st.selected, 0);
        st.handle(Key::Char('k'), &lay, &es);
        assert_eq!(st.selected, 0);
        st.selected = last;
        st.handle(Key::Char('j'), &lay, &es);
        assert_eq!(st.selected, last);
    }
}

#[test]
fn spec_scenario_h_from_first_of_second_column() {
    for w in [90usize, 120, 140] {
        let (s, lay) = setup(30, w);
        let es = flatten(&s);
        let first_of_col1 = (0..es.len()).find(|&i| lay.pos[i].0 == 1).expect("вторая колонка");
        let first_of_col0 = (0..es.len()).find(|&i| lay.pos[i].0 == 0).unwrap();
        let mut st = UiState { selected: first_of_col1, ..Default::default() };
        st.handle(Key::Char('h'), &lay, &es);
        assert_eq!(st.selected, first_of_col0, "w={w}");
    }
}

#[test]
fn g_and_big_g() {
    let (s, lay) = setup(17, 120);
    let es = flatten(&s);
    let mut st = UiState::default();
    st.handle(Key::Char('G'), &lay, &es);
    assert_eq!(st.selected, 16);
    st.handle(Key::Char('g'), &lay, &es);
    assert_eq!(st.selected, 0);
}

#[test]
fn q_returns_focus() {
    let (s, lay) = setup(3, 90);
    let es = flatten(&s);
    assert_eq!(UiState::default().handle(Key::Char('q'), &lay, &es), Action::Focus);
}

#[test]
fn arrows_work_like_hjkl() {
    let (s, lay) = setup(30, 90);
    let es = flatten(&s);
    let mut a = UiState::default();
    let mut b = UiState::default();
    for (k1, k2) in [(Key::Down, 'j'), (Key::Down, 'j'), (Key::Right, 'l'), (Key::Up, 'k'), (Key::Left, 'h')] {
        a.handle(k1, &lay, &es);
        b.handle(Key::Char(k2), &lay, &es);
        assert_eq!(a.selected, b.selected);
    }
}

fn type_text(st: &mut UiState, text: &str, lay: &ui::Layout, es: &[&Shown]) {
    for c in text.chars() {
        st.handle(Key::Char(c), lay, es);
    }
}

fn history_table() -> Vec<Section> {
    vec![
        sec(Some("history"), &[("C-r", "поиск по истории назад"), ("M-h", "история (fzf)"), ("C-p", "запись выше")]),
        sec(Some("edit"), &[("C-k", "вырезать до конца"), ("x", "удалить символ"), ("h", "влево")]),
    ]
}

#[test]
fn search_by_description_case_insensitive_selects_first() {
    let s = history_table();
    let lay = layout(&s, 120);
    let es = flatten(&s);
    let mut st = UiState { selected: 5, ..Default::default() };
    st.handle(Key::Char('/'), &lay, &es);
    assert_eq!(st.input.as_deref(), Some(""));
    type_text(&mut st, "ИСТОР", &lay, &es);
    st.handle(Key::Enter, &lay, &es);
    assert_eq!(st.input, None);
    assert_eq!(st.search.as_deref(), Some("ИСТОР"));
    assert_eq!(st.matches(&es), vec![0, 1]);
    assert_eq!(st.selected, 0);
}

#[test]
fn search_by_key_and_not_by_full_description() {
    let mut s = history_table();
    s[0].entries[2].entry.desc_full = "скрытый текст про истории".into();
    let lay = layout(&s, 120);
    let es = flatten(&s);
    let mut st = UiState::default();
    st.handle(Key::Char('/'), &lay, &es);
    type_text(&mut st, "c-k", &lay, &es);
    st.handle(Key::Enter, &lay, &es);
    assert_eq!(st.matches(&es), vec![3]);
    assert_eq!(st.selected, 3);
    // desc_full не участвует в поиске (по спецификации — клавиша и короткое описание).
    let mut st2 = UiState::default();
    st2.handle(Key::Char('/'), &lay, &es);
    type_text(&mut st2, "скрытый", &lay, &es);
    st2.handle(Key::Enter, &lay, &es);
    assert!(st2.matches(&es).is_empty());
}

#[test]
fn n_and_big_n_cycle() {
    let s = history_table();
    let lay = layout(&s, 120);
    let es = flatten(&s);
    let mut st = UiState::default();
    st.handle(Key::Char('/'), &lay, &es);
    type_text(&mut st, "истор", &lay, &es);
    st.handle(Key::Enter, &lay, &es);
    assert_eq!(st.selected, 0);
    st.handle(Key::Char('n'), &lay, &es);
    assert_eq!(st.selected, 1);
    st.handle(Key::Char('n'), &lay, &es);
    assert_eq!(st.selected, 0, "по кругу вперёд");
    st.handle(Key::Char('N'), &lay, &es);
    assert_eq!(st.selected, 1, "по кругу назад");
    st.handle(Key::Char('N'), &lay, &es);
    assert_eq!(st.selected, 0);
}

#[test]
fn esc_resets_search_and_highlight() {
    let s = history_table();
    let lay = layout(&s, 120);
    let es = flatten(&s);
    let mut st = UiState::default();
    st.handle(Key::Char('/'), &lay, &es);
    type_text(&mut st, "истор", &lay, &es);
    st.handle(Key::Enter, &lay, &es);
    let hd = Header::default();
    let with = ui::render(&mut st, &hd, &s, 120, 20).join("\n");
    assert!(with.contains("\x1b[1;33m"), "подсветки нет");
    st.handle(Key::Esc, &lay, &es);
    assert_eq!(st.search, None);
    assert!(st.matches(&es).is_empty());
    let without = ui::render(&mut st, &hd, &s, 120, 20).join("\n");
    assert!(!without.contains("\x1b[1;33m"), "подсветка осталась");
}

#[test]
fn esc_in_input_cancels_without_search_and_nav_letters_go_to_input() {
    let s = history_table();
    let lay = layout(&s, 120);
    let es = flatten(&s);
    let mut st = UiState::default();
    st.handle(Key::Char('/'), &lay, &es);
    type_text(&mut st, "jkd", &lay, &es);
    assert_eq!(st.input.as_deref(), Some("jkd"));
    assert_eq!(st.selected, 0, "j/k в вводе не двигают выбор");
    st.handle(Key::Backspace, &lay, &es);
    assert_eq!(st.input.as_deref(), Some("jk"));
    st.handle(Key::Esc, &lay, &es);
    assert_eq!(st.input, None);
    assert_eq!(st.search, None);
}

#[test]
fn context_change_resets_search() {
    let s = history_table();
    let lay = layout(&s, 120);
    let es = flatten(&s);
    let mut st = UiState::default();
    st.handle(Key::Char('/'), &lay, &es);
    type_text(&mut st, "истор", &lay, &es);
    st.handle(Key::Enter, &lay, &es);
    st.handle(Key::Char('K'), &lay, &es);
    st.reset();
    assert_eq!(st, UiState::default());
}

#[test]
fn search_status_line_shows_position() {
    let s = history_table();
    let lay = layout(&s, 120);
    let es = flatten(&s);
    let mut st = UiState::default();
    st.handle(Key::Char('/'), &lay, &es);
    type_text(&mut st, "истор", &lay, &es);
    st.handle(Key::Enter, &lay, &es);
    let lines = ui::render(&mut st, &Header::default(), &s, 120, 20);
    assert!(strip_ansi(&lines[1]).contains("[1/2]"), "{:?}", strip_ansi(&lines[1]));
}

// ---- подробности ----

fn detailed() -> Vec<Section> {
    vec![Section {
        title: Some("user".into()),
        entries: vec![Shown {
            entry: Entry {
                key: "M-f".into(),
                desc: "поиск файла (fzf)".into(),
                desc_full: "Полное описание из источника".into(),
                group: "user".into(),
                origin: "fzf".into(),
                action: "fzf-file-widget".into(),
                source: "manifest:ble.toml".into(),
                raw: "ble-bind -m 'vi_imap' -x M-f fzf-file-widget".into(),
            },
            show_origin: true,
        }],
    }]
}

#[test]
fn details_window_shows_all_fields_and_closes() {
    let s = detailed();
    let lay = layout(&s, 120);
    let es = flatten(&s);
    let mut st = UiState::default();
    assert_eq!(st.handle(Key::Char('K'), &lay, &es), Action::Redraw);
    assert!(st.details.is_some());
    let hd = Header { ctx: "ble.vi_imap".into(), target: "1-1".into(), message: None };
    let text = ui::render(&mut st, &hd, &s, 120, 20)
        .iter()
        .map(|l| strip_ansi(l))
        .collect::<Vec<_>>()
        .join("\n");
    for want in [
        "M-f",
        "Полное описание из источника",
        "fzf-file-widget",
        "manifest:ble.toml",
        "ble.vi_imap",
        "ble-bind -m 'vi_imap' -x M-f fzf-file-widget",
    ] {
        assert!(text.contains(want), "нет «{want}» в:\n{text}");
    }
    // q закрывает окно, фокус остаётся (Action не Focus).
    assert_eq!(st.handle(Key::Char('q'), &lay, &es), Action::Redraw);
    assert!(st.details.is_none());
    // Esc закрывает окно.
    st.handle(Key::Char('K'), &lay, &es);
    assert_eq!(st.handle(Key::Esc, &lay, &es), Action::Redraw);
    assert!(st.details.is_none());
    let table = ui::render(&mut st, &hd, &s, 120, 20).join("\n");
    assert!(!strip_ansi(&table).contains("ble-bind -m"), "видна не таблица");
}

#[test]
fn details_lines_wrap_to_width() {
    let s = detailed();
    let es = flatten(&s);
    let lines = ui::details_lines(es[0], "ble.vi_imap", 30);
    assert!(lines.iter().all(|l| width_of(&strip_ansi(l)) <= 30), "{lines:?}");
}

// ---- клавиши навигации и скрытия не пересекаются ----

#[test]
fn nav_and_hide_keys_disjoint() {
    let items = [("a", "один"), ("b", "два"), ("c", "три")];
    let s = vec![sec(Some("grp"), &items)];
    let lay = layout(&s, 90);
    let es = flatten(&s);
    for c in ['h', 'j', 'k', 'l', 'g', 'G', '/', 'n', 'N', 'q', 'K'] {
        let mut st = UiState::default();
        let a = st.handle(Key::Char(c), &lay, &es);
        assert!(
            !matches!(a, Action::Hide(_) | Action::HideGroup(_) | Action::Undo),
            "{c} вызвала скрытие"
        );
    }
    let mut st = UiState { selected: 1, ..Default::default() };
    assert_eq!(st.handle(Key::Char('d'), &lay, &es), Action::Hide("b".into()));
    assert_eq!(st.handle(Key::Char('D'), &lay, &es), Action::HideGroup("grp".into()));
    assert_eq!(st.handle(Key::Char('u'), &lay, &es), Action::Undo);
    // Клавиши скрытия не двигают выбор.
    assert_eq!(st.selected, 1);
    assert_eq!(UiState::default().handle(Key::Esc, &lay, &es), Action::Redraw);
}
