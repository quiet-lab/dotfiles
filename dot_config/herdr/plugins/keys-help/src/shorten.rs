//! Правило сокращения описаний D7а: короткое описание из полного текста
//! источника для записей без короткого описания в манифесте.

/// Предел длины короткого описания в символах.
pub const MAX_DESC: usize = 32;

/// Начальные служебные слова (в нижнем регистре, без конечного пробела).
const LEADING_WORDS: &[&str] = &[
    "allows you to",
    "allows to",
    "lets you",
    "used to",
    "the",
    "a",
    "an",
    "this",
    "will",
    "позволяет",
    "используется для",
    "служит для",
];

/// Снимает разметку man: `\fB…\fR` и наложение символов через возврат каретки.
pub fn strip_man_markup(s: &str) -> String {
    let mut out: Vec<char> = Vec::with_capacity(s.len());
    let chars: Vec<char> = s.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '\u{8}' {
            // «X\bX» и «_\bX»: символ перед возвратом заменяется следующим.
            out.pop();
            i += 1;
            continue;
        }
        if c == '\\' && i + 2 < chars.len() + 1 && chars.get(i + 1) == Some(&'f') {
            if let Some(n) = chars.get(i + 2) {
                if "BIRP".contains(*n) {
                    i += 3;
                    continue;
                }
            }
        }
        out.push(c);
        i += 1;
    }
    out.into_iter().collect()
}

/// Схлопывает пробельные символы в один пробел.
pub fn collapse_ws(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Удаляет скобочные пояснения `( … )` с пробелом перед ними.
fn drop_parens(s: &str) -> String {
    let mut out = String::new();
    let mut depth = 0usize;
    for c in s.chars() {
        match c {
            '(' => depth += 1,
            ')' if depth > 0 => depth -= 1,
            _ if depth == 0 => out.push(c),
            _ => {}
        }
    }
    collapse_ws(&out)
}

/// Первое предложение: до `. `, `; `, `: ` или конца текста.
fn first_sentence(s: &str) -> &str {
    let mut end = s.len();
    for sep in [". ", "; ", ": "] {
        if let Some(p) = s.find(sep) {
            end = end.min(p);
        }
    }
    &s[..end]
}

fn strip_leading_words(mut s: String) -> String {
    loop {
        let lower = s.to_lowercase();
        let mut changed = false;
        for w in LEADING_WORDS {
            if lower.starts_with(w) {
                let rest = &s[w.len()..];
                // Только целое слово: дальше пробел или конец.
                if rest.is_empty() || rest.starts_with(' ') {
                    if rest.trim().is_empty() {
                        // Служебное слово — весь текст: оставить как есть.
                        return s;
                    }
                    s = rest.trim_start().to_string();
                    changed = true;
                    break;
                }
            }
        }
        if !changed {
            return s;
        }
    }
}

/// Обрезка до `max` символов по границе слова с `…`.
pub fn truncate_words(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        return s.to_string();
    }
    let limit = max.saturating_sub(1);
    let prefix: String = s.chars().take(limit).collect();
    // Граница слова: если следующий символ — пробел, слово целое.
    let next_is_space = s.chars().nth(limit).is_some_and(|c| c == ' ');
    let cut = if next_is_space {
        prefix.trim_end().to_string()
    } else if let Some(p) = prefix.rfind(' ') {
        prefix[..p].trim_end().to_string()
    } else {
        prefix
    };
    let cut = cut.trim_end_matches([',', ';', ':', '.', '-', ' ']).to_string();
    format!("{cut}…")
}

/// Короткое описание по правилу D7а.
pub fn shorten(full: &str) -> String {
    let s = collapse_ws(&strip_man_markup(full));
    let s = first_sentence(&s).to_string();
    let s = drop_parens(&s);
    let s = strip_leading_words(s);
    let s = s.trim_end_matches(['.', ';', ':']).trim().to_string();
    truncate_words(&s, MAX_DESC)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spec_example() {
        assert_eq!(
            shorten("This will quit the program immediately. Unsaved changes are lost."),
            "quit the program immediately"
        );
    }

    #[test]
    fn long_text() {
        let d = shorten("Move the cursor to the beginning of the current logical line in the buffer");
        assert!(d.chars().count() <= MAX_DESC, "{d}");
        assert!(d.ends_with('…'));
        assert!(!d.contains("  "));
        assert_eq!(d, "Move the cursor to the…");
    }

    #[test]
    fn parens_and_words() {
        assert_eq!(shorten("Allows you to scroll (one line) up."), "scroll up");
        assert_eq!(shorten("Позволяет открыть файл."), "открыть файл");
        assert_eq!(shorten("Используется для поиска; дальше"), "поиска");
        assert_eq!(shorten("URL of page"), "URL of page");
    }

    #[test]
    fn markup() {
        assert_eq!(shorten("\\fBQuit\\fR now"), "Quit now");
        assert_eq!(strip_man_markup("Q\u{8}Qu\u{8}u"), "Qu");
    }
}
