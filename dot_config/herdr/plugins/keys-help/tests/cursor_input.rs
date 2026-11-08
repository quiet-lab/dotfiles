//! Задача 12.8: переменные позиции и `when` (D17), разделы «по позиции курсора» и «дополнение»
//! по фикстурам `.line` / `.words` / `.cands`, игнор файлов старше отметки `viewer`.
//!
//! Тесты, читающие окружение процесса (кеш, `PATH`), идут под одним замком.

mod common;

use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::time::{Duration, SystemTime};

use common::*;
use keys_help::cursor::{self, Line, Pos, When};
use keys_help::entry::Entry;
use keys_help::input::{self, Input, MAX_COMPLETION};
use keys_help::view::{self, Extra, Section, COMPLETION_TITLE, CURSOR_TITLE};

static ENV: Mutex<()> = Mutex::new(());

fn pos(point: usize, text: &str) -> Pos {
    Pos::of(&Line { point, text: text.to_string() })
}

fn fx(name: &str) -> String {
    std::fs::read_to_string(fixtures().join("input").join(name)).unwrap()
}

// ---- переменные позиции ----

#[test]
fn position_start_end_middle() {
    let t = "echo abc";
    let start = pos(0, t);
    assert_eq!((start.point, start.len, start.row, start.rows, start.col, start.line_len), (0, 8, 0, 1, 0, 8));
    assert_eq!(start.word, "");
    assert_eq!(start.word_right, "echo");
    assert_eq!(start.word_index, 0);
    let end = pos(8, t);
    assert_eq!((end.col, end.line_len), (8, 8));
    assert_eq!(end.word, "abc");
    assert_eq!(end.word_right, "");
    assert_eq!(end.word_index, 1);
    let mid = pos(6, t); // echo a|bc
    assert_eq!(mid.col, 6);
    assert_eq!(mid.word, "a");
    assert_eq!(mid.word_right, "bc");
    assert_eq!(mid.var("word_len"), Some(1));
    assert_eq!(mid.var("rows_below"), Some(0));
    assert!(!mid.blank);
}

#[test]
fn position_multiline() {
    let t = "ab\ncd\nef";
    let a = pos(4, t); // c|d
    assert_eq!((a.row, a.rows, a.col, a.line_len), (1, 3, 1, 2));
    assert_eq!(a.var("rows_below"), Some(1));
    let first = pos(1, t);
    assert_eq!((first.row, first.var("rows_below")), (0, Some(2)));
    let last = pos(8, t);
    assert_eq!((last.row, last.var("rows_below"), last.col), (2, Some(0), 2));
    // Курсор в самом начале строки после перевода.
    let b = pos(3, t);
    assert_eq!((b.row, b.col), (1, 0));
    // Слово не пересекает перевод строки.
    assert_eq!(pos(3, t).word, "");
    assert_eq!(pos(2, t).word, "ab");
    assert_eq!(pos(2, t).word_right, "");
}

#[test]
fn position_empty_and_blank() {
    let e = pos(0, "");
    assert!(e.blank);
    assert_eq!((e.len, e.rows, e.row, e.col, e.line_len, e.word_index), (0, 1, 0, 0, 0, 0));
    assert_eq!(e.var("blank"), Some(1));
    assert!(pos(2, "  ").blank);
    assert!(pos(1, "\n\n").blank);
    assert!(!pos(0, " a").blank);
    assert_eq!(pos(3, "abc").var("blank"), Some(0));
}

#[test]
fn position_point_beyond_text_is_clamped_and_chars_not_bytes() {
    let p = pos(99, "привет");
    assert_eq!((p.point, p.len, p.col), (6, 6, 6));
    assert_eq!(p.word, "привет");
    let q = pos(3, "при вет");
    assert_eq!((q.col, q.word.as_str(), q.word_right.as_str()), (3, "при", ""));
}

#[test]
fn word_index_resets_after_command_separator() {
    assert_eq!(pos(13, "git commit -m").word_index, 2);
    assert_eq!(pos(13, "git commit -m").word, "-m");
    assert_eq!(pos(12, "ls -l; git s").word_index, 1);
    assert_eq!(pos(7, "ls | gr").word_index, 0);
    assert_eq!(pos(6, "a && b").word_index, 0);
    assert_eq!(pos(5, "ls\ngi").word_index, 0, "перевод строки начинает команду");
}

#[test]
fn parse_line_format() {
    let l = cursor::parse_line(&fx("kh.line")).unwrap();
    assert_eq!((l.point, l.text.as_str()), (2, "kh"));
    let m = cursor::parse_line(&fx("multi.line")).unwrap();
    assert_eq!((m.point, m.text.as_str()), (4, "ab\ncd\nef"));
    // Только позиция — пустая строка; конечный перевод строки — часть текста.
    let e = cursor::parse_line(&fx("empty.line")).unwrap_or_default();
    assert_eq!(e.text, "");
    assert_eq!(cursor::parse_line("0\n").unwrap().text, "");
    assert_eq!(cursor::parse_line("1\nab\n").unwrap().text, "ab\n");
    assert_eq!(cursor::parse_line("3").unwrap(), Line { point: 3, text: String::new() });
    assert!(cursor::parse_line("не число\nтекст").is_none());
    assert!(cursor::parse_line("").is_none());
}

#[test]
fn parse_words_and_cands() {
    let w = cursor::parse_words(&fx("shell.words"));
    assert_eq!(w.len(), 5);
    assert_eq!((w[0].kind.as_str(), w[0].name.as_str(), w[0].value.as_str()), ("sabbrev", "gs", "git status --short"));
    assert_eq!(w[3].kind, "function");
    assert_eq!(w[3].value, "");
    assert!(cursor::parse_words("мусор без табуляций\n\t\tx\n").is_empty());
    let c = cursor::parse_cands(&fx("kh.cands"));
    assert_eq!(c.compv, "kh");
    assert_eq!(c.words, vec!["kh-tool", "kh-other"]);
    assert_eq!(cursor::parse_cands("").words.len(), 0);
}

// ---- when ----

fn w(s: &str) -> When {
    When::parse(s, "t").unwrap_or_else(|e| panic!("{s}: {e}"))
}

#[test]
fn when_operators_and_conjunction() {
    let p = pos(4, "ab\ncd\nef");
    for (src, want) in [
        ("col > 0", true),
        ("col == 1", true),
        ("col != 1", false),
        ("col >= 2", false),
        ("col <= 1", true),
        ("col < line_len", true),
        ("row > 0", true),
        ("rows_below > 0", true),
        ("point < len", true),
        ("point == len", false),
        ("blank == 0", true),
        ("row > 0 && col > 0 && rows_below == 1", true),
        ("row > 0 && col > 5", false),
        ("word_index == 0", true),
        ("col > -1", true),
    ] {
        assert_eq!(w(src).eval(&p), want, "{src}");
    }
}

#[test]
fn when_on_start_end_and_empty() {
    let t = "echo abc";
    assert!(!w("col > 0").eval(&pos(0, t)));
    assert!(w("col < line_len").eval(&pos(0, t)));
    assert!(w("col > 0").eval(&pos(8, t)));
    assert!(!w("col < line_len").eval(&pos(8, t)));
    assert!(w("col > 0 && col < line_len").eval(&pos(4, t)));
    assert!(w("blank == 1").eval(&pos(0, "")));
    assert!(!w("point < len").eval(&pos(0, "")));
}

#[test]
fn when_unknown_variable_is_error() {
    for bad in ["cursor > 0", "col > nope", "foo == bar", "col > 0 && zzz < 1", "word == 1"] {
        let e = When::parse(bad, "applies[0].when").unwrap_err();
        assert!(e.contains("applies[0].when"), "{e}");
        assert!(e.contains("неизвестная переменная"), "{bad}: {e}");
    }
    // Нет сравнения.
    assert!(When::parse("col", "t").is_err());
    assert!(When::parse("", "t").is_err());
}

#[test]
fn all_documented_variables_are_known() {
    for v in ["point", "len", "row", "rows", "rows_below", "col", "line_len", "word_len", "word_index", "blank"] {
        assert!(When::parse(&format!("{v} >= 0"), "t").is_ok(), "{v}");
        assert!(pos(1, "ab").var(v).is_some(), "{v}");
    }
    assert!(pos(1, "ab").var("нет").is_none());
}

#[test]
fn manifest_with_unknown_when_variable_is_rejected() {
    let text = "program = \"x\"\n[[applies]]\naction = \"^a$\"\nwhen = \"unknown_var > 0\"\n";
    let e = keys_help::manifest::parse(text, Path::new("/x/x.toml")).unwrap_err();
    assert!(e.contains("unknown_var"), "{e}");
    assert!(keys_help::manifest::parse("program = \"x\"\n[[applies]]\naction = \"^a$\"\n", Path::new("/x/x.toml")).is_err());
    assert!(keys_help::manifest::parse("program = \"x\"\n[[applies]]\nwhen = \"col > 0\"\n", Path::new("/x/x.toml")).is_err());
    // Через load_dirs ошибочный манифест пропускается с сообщением.
    let d = tmpdir("when-bad");
    std::fs::write(d.join("x.toml"), text).unwrap();
    let (ms, errs) = keys_help::manifest::load_dirs(&[d]);
    assert!(ms.is_empty());
    assert!(errs.iter().any(|e| e.contains("unknown_var")), "{errs:?}");
}

// ---- раздел «по позиции курсора» (правила ble.toml) ----

fn ble_entry(key: &str, action: &str, group: &str) -> Entry {
    Entry { key: key.into(), desc: key.into(), action: action.into(), group: group.into(), origin: "ble".into(), ..Default::default() }
}

fn ble_table() -> Vec<Entry> {
    vec![
        ble_entry("C-b", "backward-char", "motion"),
        ble_entry("C-f", "forward-char", "motion"),
        ble_entry("C-a", "beginning-of-line", "motion"),
        ble_entry("C-e", "end-of-line", "motion"),
        ble_entry("C-k", "kill-forward-line", "edit"),
        ble_entry("C-p", "history-prev", "history"),
        ble_entry("C-n", "history-next", "history"),
        ble_entry("M-<", "beginning-of-text", "history"),
        ble_entry("C-r", "history-isearch-backward", "history"),
    ]
}

/// Разделы так же, как их собирает просмотрщик: правило — номер подошедшего `[[applies]]`
/// манифеста и значение его `when`.
fn sections_at(point: usize, text: &str, mode: &str) -> Vec<Section> {
    let m = manifest_named("ble");
    let p = pos(point, text);
    let rule = |e: &Entry| {
        m.applies.iter().position(|a| a.matches(&e.action, &[mode, mode])).map(|i| (i, m.applies[i].when.eval(&p)))
    };
    let extra = Extra { origin_order: vec![], applies: Some(&rule), completion: vec![] };
    let eff = view::effective(&view::parse("").unwrap(), "ble.vi_imap");
    view::apply_ext(&ble_table(), &eff, &extra)
}

fn section<'a>(s: &'a [Section], title: &str) -> Option<&'a Section> {
    s.iter().find(|x| x.title.as_deref() == Some(title))
}

fn keys_in(s: &Section) -> Vec<&str> {
    s.entries.iter().map(|x| x.entry.key.as_str()).collect()
}

fn dimmed(s: &[Section]) -> Vec<&str> {
    s.iter().flat_map(|x| x.entries.iter()).filter(|e| e.dim).map(|e| e.entry.key.as_str()).collect()
}

#[test]
fn cursor_section_at_start_of_line() {
    let s = sections_at(0, "echo abc", "vi_imap");
    let c = section(&s, CURSOR_TITLE).expect("раздел по позиции курсора");
    let k = keys_in(c);
    // В начале строки применимы движения вперёд; назад — приглушены на месте.
    assert!(k.contains(&"C-f") && k.contains(&"C-e") && k.contains(&"C-k"), "{k:?}");
    assert!(!k.contains(&"C-b") && !k.contains(&"C-a"), "{k:?}");
    let d = dimmed(&s);
    assert!(d.contains(&"C-b") && d.contains(&"C-a"), "{d:?}");
    // Приглушённая запись осталась в своей группе.
    assert!(keys_in(section(&s, "motion").unwrap()).contains(&"C-b"));
    // Разделы идут первыми.
    assert_eq!(s[0].title.as_deref(), Some(CURSOR_TITLE));
}

#[test]
fn cursor_section_at_end_of_line() {
    let s = sections_at(8, "echo abc", "vi_imap");
    let k = keys_in(section(&s, CURSOR_TITLE).unwrap());
    assert!(k.contains(&"C-b") && k.contains(&"C-a"), "{k:?}");
    assert!(!k.contains(&"C-f") && !k.contains(&"C-e") && !k.contains(&"C-k"), "{k:?}");
    let d = dimmed(&s);
    assert!(d.contains(&"C-f") && d.contains(&"C-k"), "{d:?}");
}

#[test]
fn cursor_section_in_middle_has_both_directions() {
    let s = sections_at(4, "echo abc", "emacs");
    let k = keys_in(section(&s, CURSOR_TITLE).unwrap());
    for key in ["C-b", "C-f", "C-a", "C-e", "C-k"] {
        assert!(k.contains(&key), "{key}: {k:?}");
    }
    // Приглушены только команды переходов по строкам (однострочный ввод).
    let mut d = dimmed(&s);
    d.sort();
    assert_eq!(d, vec!["C-n", "C-p", "M-<"]);
}

#[test]
fn cursor_section_multiline_history_rows() {
    // Первая строка многострочного ввода: history-prev (row > 0) неприменима, history-next — да.
    let first = sections_at(1, "ab\ncd\nef", "vi_imap");
    let k = keys_in(section(&first, CURSOR_TITLE).unwrap());
    assert!(k.contains(&"C-n") && !k.contains(&"C-p") && !k.contains(&"M-<"), "{k:?}");
    assert!(dimmed(&first).contains(&"C-p"));
    // Средняя — обе; последняя — history-prev и beginning-of-text, но не history-next.
    let mid = sections_at(4, "ab\ncd\nef", "vi_imap");
    let k = keys_in(section(&mid, CURSOR_TITLE).unwrap());
    assert!(k.contains(&"C-n") && k.contains(&"C-p") && k.contains(&"M-<"), "{k:?}");
    let last = sections_at(8, "ab\ncd\nef", "vi_imap");
    let k = keys_in(section(&last, CURSOR_TITLE).unwrap());
    assert!(k.contains(&"C-p") && !k.contains(&"C-n"), "{k:?}");
    // Однострочный ввод: переходов по строкам нет.
    let single = sections_at(2, "ab", "vi_imap");
    assert!(!keys_in(section(&single, CURSOR_TITLE).unwrap()).contains(&"C-p"));
}

#[test]
fn entries_without_rule_stay_in_groups_and_mode_filter() {
    let s = sections_at(2, "ab", "vi_imap");
    assert!(keys_in(section(&s, "history").unwrap()).contains(&"C-r"));
    assert!(!keys_in(section(&s, CURSOR_TITLE).unwrap()).contains(&"C-r"));
    // Режим вне `modes` правила (vi_nmap): правила не применяются, раздела нет.
    let n = sections_at(2, "ab", "vi_nmap");
    assert!(section(&n, CURSOR_TITLE).is_none());
    assert!(dimmed(&n).is_empty());
}

#[test]
fn no_cursor_section_without_position() {
    // Позиция неизвестна или строка пуста — раздела и приглушения нет.
    let eff = view::effective(&view::parse("").unwrap(), "ble.vi_imap");
    let s = view::apply_ext(&ble_table(), &eff, &Extra::default());
    assert!(section(&s, CURSOR_TITLE).is_none());
    assert!(dimmed(&s).is_empty());
}

// ---- Input: файлы и отметка viewer ----

fn mark(dir: &Path) {
    std::fs::create_dir_all(dir).unwrap();
    std::fs::write(dir.join(input::VIEWER_MARK), "").unwrap();
}

fn put(dir: &Path, name: &str, fixture: &str) {
    std::fs::write(dir.join(name), fx(fixture)).unwrap();
}

fn set_age(path: &Path, secs_ago: u64) {
    let f = std::fs::File::options().write(true).open(path).unwrap();
    f.set_modified(SystemTime::now() - Duration::from_secs(secs_ago)).unwrap();
}

#[test]
fn files_older_than_mark_are_ignored() {
    let d = tmpdir("in-old");
    mark(&d);
    put(&d, "ble-1.line", "kh.line");
    put(&d, "ble-1.words", "shell.words");
    put(&d, "ble-1.cands", "kh.cands");
    // Файлы от прежней панели: старше отметки.
    for n in ["ble-1.line", "ble-1.words", "ble-1.cands"] {
        set_age(&d.join(n), 3600);
    }
    let mut i = Input::default();
    assert!(i.set_active(&d, Some("ble-1".into())));
    assert!(i.line.is_none() && i.words.is_empty() && i.cands.is_none());
    assert!(i.pos().is_none());
    // Свежая запись после отметки читается по событию файла.
    put(&d, "ble-1.line", "kh.line");
    assert!(i.on_file("ble-1.line"));
    assert_eq!(i.line.as_ref().map(|l| l.text.as_str()), Some("kh"));
    // Старые слова так и не прочитаны.
    assert!(i.words.is_empty());
}

#[test]
fn no_mark_means_no_data() {
    let d = tmpdir("in-nomark");
    put(&d, "ble-1.line", "kh.line");
    let mut i = Input::default();
    i.set_active(&d, Some("ble-1".into()));
    assert!(i.line.is_none());
}

#[test]
fn files_read_by_events_and_other_records_ignored() {
    let d = tmpdir("in-events");
    mark(&d);
    let mut i = Input::default();
    assert!(i.set_active(&d, Some("ble-1".into())));
    assert!(!i.set_active(&d, Some("ble-1".into())), "повторный выбор той же записи — без изменений");
    put(&d, "ble-1.line", "multi.line");
    assert!(i.on_file("ble-1.line"));
    put(&d, "ble-1.words", "shell.words");
    assert!(i.on_file("ble-1.words"));
    put(&d, "ble-1.cands", "kh.cands");
    assert!(i.on_file("ble-1.cands"));
    assert_eq!(i.words.len(), 5);
    assert_eq!(i.cands.as_ref().unwrap().compv, "kh");
    // Файлы другой записи и посторонние имена событий не меняют состояние.
    assert!(!i.on_file("ble-2.line"));
    assert!(!i.on_file("ble-1.json"));
    assert!(!i.on_file("viewer"));
    // Пустая строка — раздела нет.
    put(&d, "ble-1.line", "empty.line");
    i.on_file("ble-1.line");
    assert!(i.pos().is_none());
    // Смена активной записи сбрасывает данные.
    assert!(i.set_active(&d, Some("ble-9".into())));
    assert!(i.line.is_none() && i.words.is_empty() && i.cands.is_none());
}

#[test]
fn remove_mark_deletes_mark_and_input_files_only() {
    let d = tmpdir("in-rm");
    mark(&d);
    for (n, f) in [("ble-1.line", "kh.line"), ("ble-1.words", "shell.words"), ("ble-1.cands", "kh.cands")] {
        put(&d, n, f);
    }
    std::fs::write(d.join("ble-1.json"), "{}").unwrap();
    input::remove_mark(&d);
    for n in ["viewer", "ble-1.line", "ble-1.words", "ble-1.cands"] {
        assert!(!d.join(n).exists(), "{n} остался");
    }
    assert!(d.join("ble-1.json").exists(), "запись поставщика не трогается");
}

// ---- раздел «дополнение» ----

struct Env {
    _g: std::sync::MutexGuard<'static, ()>,
    old: Vec<(&'static str, Option<String>)>,
}

impl Env {
    fn set(vars: &[(&'static str, String)]) -> Env {
        let g = ENV.lock().unwrap_or_else(|e| e.into_inner());
        let old = vars.iter().map(|(k, _)| (*k, std::env::var(k).ok())).collect();
        for (k, v) in vars {
            std::env::set_var(k, v);
        }
        Env { _g: g, old }
    }
}

impl Drop for Env {
    fn drop(&mut self) {
        for (k, v) in &self.old {
            match v {
                Some(v) => std::env::set_var(k, v),
                None => std::env::remove_var(k),
            }
        }
    }
}

/// Процесс «оболочки» с заданным `PATH` в окружении (`/proc/<pid>/environ`).
fn shell_with_path(bin: &Path) -> Child {
    Command::new("/usr/bin/cat")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .env("PATH", bin.display().to_string())
        .spawn()
        .unwrap()
}

fn exe(dir: &Path, name: &str) {
    let p = dir.join(name);
    std::fs::write(&p, "#!/bin/sh\nexit 0\n").unwrap();
    std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
}

fn completion_input(d: &Path, line_fixture: &str, bin: &Path, shell: &Child) -> Input {
    mark(d);
    put(d, "ble-1.line", line_fixture);
    put(d, "ble-1.words", "shell.words");
    put(d, "ble-1.cands", "kh.cands");
    let mut i = Input::default();
    i.set_active(d, Some("ble-1".into()));
    let (_, new) = i.refresh_path(Some(shell.id() as i32)).expect("PATH процесса оболочки");
    assert!(new.contains(&bin.to_path_buf()), "{new:?}");
    assert!(i.is_path_dir(bin));
    i
}

fn names(v: &[Entry]) -> Vec<&str> {
    v.iter().map(|e| e.key.as_str()).collect()
}

#[test]
fn completion_for_command_word_order_and_sources() {
    let d = tmpdir("cmp-cmd");
    let bin = d.join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    for n in ["kh-tool", "kh-bin", "other-bin"] {
        exe(&bin, n);
    }
    std::fs::write(bin.join("kh-data"), "не исполняемый").unwrap();
    let mut shell = shell_with_path(&bin);
    let mut i = completion_input(&d, "kh.line", &bin, &shell);
    let (c, need) = i.completion();
    assert!(need.is_none());
    // Кандидаты ble.sh (COMPV = kh), затем псевдонимы, функции, команды PATH; без повторов.
    assert_eq!(names(&c), vec!["kh-tool", "kh-other", "khal", "kh_func", "kh-bin"], "{c:?}");
    assert!(c.iter().all(|e| e.group == COMPLETION_TITLE));
    assert_eq!(c[0].origin, "кандидат");
    assert!(c.iter().find(|e| e.key == "khal").unwrap().desc.starts_with("= "));
    assert_eq!(c.iter().find(|e| e.key == "kh-bin").unwrap().source, "PATH");
    assert!(c.iter().all(|e| e.key != "kh-data"), "неисполняемый файл — не команда");
    drop(shell.stdin.take());
    let _ = shell.wait();
}

#[test]
fn completion_abbreviation_and_cands_only_for_same_compv() {
    let d = tmpdir("cmp-abbr");
    let bin = d.join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    exe(&bin, "gsutil");
    let mut shell = shell_with_path(&bin);
    let mut i = completion_input(&d, "gs.line", &bin, &shell);
    let (c, _) = i.completion();
    // Аббревиатура первой, с раскрытием; кандидаты с COMPV «kh» к слову «gs» не относятся.
    assert_eq!(c[0].key, "gs");
    assert!(c[0].desc.starts_with("→ "), "{}", c[0].desc);
    assert_eq!(c[0].desc_full, "git status --short");
    assert!(c.iter().all(|e| e.key != "kh-tool"));
    assert!(names(&c).contains(&"gsutil"));
    drop(shell.stdin.take());
    let _ = shell.wait();
}

#[test]
fn completion_empty_word_or_blank_line_is_empty() {
    let d = tmpdir("cmp-empty");
    let bin = d.join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    exe(&bin, "kh-tool");
    let mut shell = shell_with_path(&bin);
    let mut i = completion_input(&d, "empty.line", &bin, &shell);
    assert!(i.completion().0.is_empty());
    // Курсор после пробела: слова нет.
    std::fs::write(d.join("ble-1.line"), "3\nkh ").unwrap();
    i.on_file("ble-1.line");
    assert!(i.completion().0.is_empty());
    drop(shell.stdin.take());
    let _ = shell.wait();
}

#[test]
fn completion_is_limited_to_20_cells() {
    let d = tmpdir("cmp-limit");
    let bin = d.join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    for n in 0..40 {
        exe(&bin, &format!("kh-cmd{n:02}"));
    }
    let mut shell = shell_with_path(&bin);
    let mut i = completion_input(&d, "kh.line", &bin, &shell);
    let (c, _) = i.completion();
    assert_eq!(MAX_COMPLETION, 20);
    assert_eq!(c.len(), 20);
    drop(shell.stdin.take());
    let _ = shell.wait();
}

#[test]
fn completion_of_options_of_first_word() {
    let d = tmpdir("cmp-opt");
    let bin = d.join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    exe(&bin, "kh-tool");
    let mut shell = shell_with_path(&bin);
    let _env = Env::set(&[("XDG_CACHE_HOME", d.join("cache").display().to_string())]);
    let mut i = completion_input(&d, "opt.line", &bin, &shell);
    // Параметров ещё нет: нужен вывод man (команда извлечения), раздел пока пуст.
    let (c, need) = i.completion();
    assert!(c.is_empty());
    let need = need.expect("нужен man");
    assert_eq!(need.command, "kh-tool");
    assert_eq!(need.argv, vec!["man", "-P", "cat", "kh-tool"]);
    // Повторный запрос ту же команду не просит.
    assert!(i.completion().1.is_none());
    // man без параметров — следующий шаг: --help.
    let next = i.opts_done("kh-tool", &need.argv, "KH-TOOL(1)\n\nNAME\n       kh-tool\n").expect("--help");
    assert_eq!(next, vec!["kh-tool", "--help"]);
    let help = "Usage: kh-tool [OPTIONS]\n\nOptions:\n  -c, --color      Colorize the output when printing\n  -v, --verbose    Be verbose\n      --colors-off  Disable colors\n";
    assert!(i.opts_done("kh-tool", &next, help).is_none());
    let (c, need) = i.completion();
    assert!(need.is_none());
    // Слово «--co»: подходят --color и --colors-off, но не -v, --verbose.
    assert_eq!(names(&c), vec!["--color", "--colors-off"], "{c:?}");
    assert_eq!(c[0].origin, "параметр");
    assert!(c[0].desc_full.contains("Colorize"));
    assert!(c[0].desc.chars().count() <= 32);
    drop(shell.stdin.take());
    let _ = shell.wait();
}

#[test]
fn options_parse_help_text() {
    let o = cursor::parse_options("Usage: x\n\nOptions:\n  -h, --help   Show help\n  -q           Quiet\n--no-indent  skipped\n");
    assert_eq!(o.len(), 2);
    assert_eq!(o[0].names, vec!["-h", "--help"]);
    assert_eq!(o[0].desc, "Show help");
    assert_eq!(o[1].names, vec!["-q"]);
}

#[test]
fn path_commands_follow_directory_changes() {
    let d = tmpdir("cmp-path");
    let bin = d.join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    exe(&bin, "kh-one");
    let mut shell = shell_with_path(&bin);
    let mut i = completion_input(&d, "kh.line", &bin, &shell);
    std::fs::write(d.join("ble-1.cands"), "zzz\n").unwrap();
    i.on_file("ble-1.cands");
    assert_eq!(names(&i.completion().0), vec!["khal", "kh_func", "kh-one"]);
    // Новая команда в каталоге PATH: пересборка по событию каталога.
    exe(&bin, "kh-two");
    i.rebuild_path();
    assert!(names(&i.completion().0).contains(&"kh-two"));
    // Тот же pid — каталоги не пересчитываются.
    assert!(i.refresh_path(Some(shell.id() as i32)).is_none());
    drop(shell.stdin.take());
    let _ = shell.wait();
}

