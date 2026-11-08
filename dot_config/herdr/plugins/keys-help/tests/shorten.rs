//! Задача 6.10: правило сокращения описаний D7а.

use keys_help::shorten::{shorten, MAX_DESC};

fn len(s: &str) -> usize {
    s.chars().count()
}

#[test]
fn spec_scenario_generic() {
    assert_eq!(
        shorten("This will quit the program immediately. Unsaved changes are lost."),
        "quit the program immediately"
    );
}

#[test]
fn first_sentence_only() {
    assert_eq!(shorten("scroll down. Repeats with a count"), "scroll down");
    assert_eq!(shorten("open file; close the old one"), "open file");
    assert_eq!(shorten("search: forward or backward"), "search");
}

#[test]
fn parentheses_removed() {
    assert_eq!(shorten("scroll (one line) up"), "scroll up");
    assert_eq!(
        shorten("move to start (home) of line"),
        "move to start of line"
    );
    assert_eq!(shorten("копировать (в буфер) строку"), "копировать строку");
}

#[test]
fn leading_service_words_english() {
    for (src, want) in [
        ("Allows you to scroll up", "scroll up"),
        ("lets you open the file", "open the file"),
        ("used to filter results", "filter results"),
        ("the cursor to the end", "cursor to the end"),
        ("an item is selected", "item is selected"),
        ("This will quit now", "quit now"),
    ] {
        assert_eq!(shorten(src), want, "{src}");
    }
}

#[test]
fn leading_service_words_russian() {
    assert_eq!(shorten("Позволяет открыть файл"), "открыть файл");
    assert_eq!(shorten("Используется для поиска"), "поиска");
    assert_eq!(
        shorten("Служит для выхода из программы"),
        "выхода из программы"
    );
}

#[test]
fn service_word_only_inside_word_boundary() {
    // «another» начинается с «an», но не служебное слово.
    assert_eq!(shorten("another window"), "another window");
    assert_eq!(shorten("theory of keys"), "theory of keys");
}

#[test]
fn trailing_period_removed() {
    assert_eq!(shorten("quit."), "quit");
    assert_eq!(shorten("quit the program."), "quit the program");
    assert!(!shorten("Открыть файл.").ends_with('.'));
}

#[test]
fn limit_32_with_ellipsis_on_word_boundary() {
    let src = "move the cursor to the beginning of the current logical line in the buffer";
    let d = shorten(src);
    assert!(len(&d) <= MAX_DESC, "{d}");
    assert_eq!(MAX_DESC, 32);
    assert!(d.ends_with('…'));
    let body = d.trim_end_matches('…');
    // Обрезка по границе слова: тело — целые слова исходного текста.
    assert!(src.starts_with(body), "{d}");
    assert!(
        src[body.len()..].starts_with(' '),
        "разрез внутри слова: {d}"
    );
    assert!(!body.ends_with(' '));
}

#[test]
fn exactly_at_limit_is_not_truncated() {
    let s = "a".repeat(10) + " " + &"b".repeat(10) + " " + &"c".repeat(10); // 32 символа
    assert_eq!(len(&s), 32);
    assert_eq!(shorten(&s), s);
    let s33 = s.clone() + "d";
    let d = shorten(&s33);
    assert!(len(&d) <= 32 && d.ends_with('…'), "{d}");
}

#[test]
fn long_single_word_is_cut_hard_with_ellipsis() {
    let d = shorten(&"x".repeat(60));
    assert!(len(&d) <= 32 && d.ends_with('…'), "{d}");
}

#[test]
fn russian_text_limit_counts_chars_not_bytes() {
    let d = shorten("переместить курсор в начало текущей логической строки буфера");
    assert!(len(&d) <= 32, "{d}");
    assert!(d.ends_with('…'));
    assert!(d.is_char_boundary(d.len()));
}

#[test]
fn whitespace_collapsed() {
    assert_eq!(shorten("quit   the \n program"), "quit the program");
}

#[test]
fn empty_and_short() {
    assert_eq!(shorten(""), "");
    assert_eq!(shorten("quit"), "quit");
}
