//! Нормализация записи клавиш к виду ble.sh (D6): модификаторы `C-M-S-s-`
//! в этом порядке, именованные клавиши (`ESC`, `RET`, `TAB`, `SP`, `up`, `f1`),
//! последовательности — через пробел.

/// Подстановки манифеста (`[key] map`), применяются до разбора: сначала длинные.
pub fn apply_map(raw: &str, map: &[(String, String)]) -> String {
    if map.is_empty() {
        return raw.to_string();
    }
    let mut pairs: Vec<&(String, String)> = map.iter().collect();
    pairs.sort_by(|a, b| b.0.len().cmp(&a.0.len()).then(a.0.cmp(&b.0)));
    // Замена за один проход слева направо, чтобы подставленный текст не
    // попадал под следующие правила.
    let mut out = String::new();
    let mut i = 0;
    let bytes = raw.as_bytes();
    'outer: while i < bytes.len() {
        for (from, to) in &pairs {
            if !from.is_empty() && raw[i..].starts_with(from.as_str()) {
                out.push_str(to);
                i += from.len();
                continue 'outer;
            }
        }
        let ch = raw[i..].chars().next().unwrap_or(' ');
        out.push(ch);
        i += ch.len_utf8();
    }
    out
}

/// Нормализует клавишу или последовательность с подстановками манифеста.
pub fn normalize_with(raw: &str, map: &[(String, String)]) -> String {
    normalize(&apply_map(raw, map))
}

/// Нормализует клавишу или последовательность клавиш.
pub fn normalize(raw: &str) -> String {
    if raw.is_empty() {
        return String::new();
    }
    let tokens: Vec<String> = if raw == " " {
        vec!["SP".to_string()]
    } else if raw.trim() != raw {
        // Ведущий пробел — клавиша (leader в Neovim): разбор по символам.
        parse_vim(raw)
    } else if raw.contains(char::is_whitespace) {
        raw.split_whitespace().flat_map(normalize_token).collect()
    } else {
        normalize_token(raw)
    };
    tokens.join(" ")
}

/// Один «слитный» фрагмент: аккорд, имя клавиши, запись Vim или символы подряд.
fn normalize_token(tok: &str) -> Vec<String> {
    if let Some(name) = named_key(tok) {
        return vec![name];
    }
    // `ESC-v` в справке (less, more) — две клавиши подряд: ESC, затем v.
    if let Some(rest) = tok.strip_prefix("ESC-").or_else(|| tok.strip_prefix("Esc-")) {
        if !rest.is_empty() && (rest.chars().count() == 1 || named_key(rest).is_some()) {
            let mut v = vec!["ESC".to_string()];
            v.extend(normalize_token(rest));
            return v;
        }
    }
    if let Some(chord) = parse_chord(tok) {
        return vec![chord];
    }
    if tok.len() == 2 && tok.starts_with('^') {
        let c = tok.chars().nth(1).unwrap_or('?');
        if c.is_ascii_alphabetic() || "[]\\@_".contains(c) {
            return vec![format!("C-{}", c.to_ascii_lowercase())];
        }
    }
    if tok.contains('<') && tok.contains('>') {
        return parse_vim(tok);
    }
    if tok.chars().count() == 1 {
        return vec![single_char(tok.chars().next().unwrap_or(' '))];
    }
    // Ключ из нескольких символов без признаков аккорда — последовательность.
    tok.chars().map(single_char).collect()
}

fn single_char(c: char) -> String {
    match c {
        ' ' => "SP".to_string(),
        '\t' => "TAB".to_string(),
        '\r' | '\n' => "RET".to_string(),
        '\x1b' => "ESC".to_string(),
        '\x7f' => "DEL".to_string(),
        c if (c as u32) < 0x20 => {
            format!("C-{}", ((c as u8) + 0x60) as char)
        }
        c => c.to_string(),
    }
}

/// Разбор записи Vim: `<C-x>`, `<Esc>`, `<leader>`, обычные символы.
fn parse_vim(s: &str) -> Vec<String> {
    let chars: Vec<char> = s.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        if chars[i] == '<' {
            if let Some(end) = chars[i + 1..].iter().position(|&c| c == '>') {
                let inner: String = chars[i + 1..i + 1 + end].iter().collect();
                if !inner.is_empty() && !inner.contains('<') {
                    out.push(vim_bracket(&inner));
                    i += end + 2;
                    continue;
                }
            }
        }
        out.push(single_char(chars[i]));
        i += 1;
    }
    out
}

fn vim_bracket(inner: &str) -> String {
    let lower = inner.to_ascii_lowercase();
    match lower.as_str() {
        "lt" => return "<".to_string(),
        "gt" => return ">".to_string(),
        "bar" => return "|".to_string(),
        "bslash" => return "\\".to_string(),
        _ => {}
    }
    if let Some(name) = named_key(inner) {
        return name;
    }
    if let Some(chord) = parse_chord(inner) {
        return chord;
    }
    // Неизвестное имя (`<leader>`, `<Plug>`) остаётся как есть.
    format!("<{inner}>")
}

/// Именованная клавиша в виде ble.sh или `None`.
pub fn named_key(s: &str) -> Option<String> {
    // Имена ble.sh в верхнем регистре: DEL — клавиша Backspace (0x7f), BS — C-h.
    if matches!(s, "DEL" | "BS" | "ESC" | "RET" | "TAB" | "SP") {
        return Some(s.to_string());
    }
    let l = s.to_ascii_lowercase();
    let name = match l.as_str() {
        "esc" | "escape" => "ESC",
        "enter" | "return" | "cr" | "ret" => "RET",
        "tab" => "TAB",
        "space" | "spc" | "sp" => "SP",
        "backspace" | "bs" | "bspace" => "BS",
        "del" | "delete" => "delete",
        "ins" | "insert" => "insert",
        "up" | "arrowup" => "up",
        "down" | "arrowdown" => "down",
        "left" | "arrowleft" => "left",
        "right" | "arrowright" => "right",
        "home" => "home",
        "end" => "end",
        "pageup" | "page-up" | "pgup" | "prior" => "prior",
        "pagedown" | "page-down" | "pgdn" | "pgdown" | "next" => "next",
        "nl" | "linefeed" => "C-j",
        "backtab" => "S-TAB",
        "nul" => "C-@",
        _ => {
            if let Some(n) = l.strip_prefix('f') {
                if !n.is_empty() && n.len() <= 2 && n.chars().all(|c| c.is_ascii_digit()) {
                    let v: u32 = n.parse().unwrap_or(0);
                    if (1..=35).contains(&v) {
                        return Some(format!("f{v}"));
                    }
                }
            }
            return None;
        }
    };
    Some(name.to_string())
}

/// Модификатор по имени: `C`, `M`, `S`, `s` (super) или `None`.
fn modifier(name: &str) -> Option<char> {
    match name.to_ascii_lowercase().as_str() {
        "c" | "ctrl" | "control" | "ctl" => Some('C'),
        "m" | "a" | "alt" | "meta" | "opt" | "option" => Some('M'),
        "s" | "shift" => Some('S'),
        "d" | "super" | "cmd" | "win" | "command" => Some('s'),
        _ => None,
    }
}

/// Аккорд с модификаторами: `ctrl-alt-t`, `Ctrl+X`, `C-M-a`, `S-Tab`.
fn parse_chord(s: &str) -> Option<String> {
    // Разделитель — `-` или `+`; последний фрагмент — клавиша (может быть `-`
    // или `+` сама по себе: `C--`, `ctrl++`).
    let bytes = s.as_bytes();
    let mut mods: Vec<char> = Vec::new();
    let mut start = 0;
    let mut i = 0;
    while i < bytes.len() {
        let c = bytes[i];
        if (c == b'-' || c == b'+') && i > start && i + 1 < bytes.len() {
            mods.push(modifier(&s[start..i])?);
            start = i + 1;
            i += 1;
            continue;
        }
        i += 1;
    }
    if mods.is_empty() {
        return None;
    }
    let base_raw = &s[start..];
    if base_raw.is_empty() {
        return None;
    }
    let mut base = if let Some(n) = named_key(base_raw) {
        n
    } else if base_raw.chars().count() == 1 {
        single_char(base_raw.chars().next().unwrap_or(' '))
    } else {
        punct_name(base_raw)?.to_string()
    };
    // Имя может уже содержать модификатор (backtab → S-TAB).
    if let Some(rest) = base.strip_prefix("S-") {
        mods.push('S');
        base = rest.to_string();
    }
    let has_c = mods.contains(&'C');
    // Буква с Control регистра не различает: Ctrl+X — это C-x.
    if has_c && base.len() == 1 {
        let c = base.chars().next().unwrap_or(' ');
        if c.is_ascii_uppercase() && !mods.contains(&'S') {
            base = c.to_ascii_lowercase().to_string();
        }
    }
    let mut out = String::new();
    for m in ['C', 'M', 'S', 's'] {
        if mods.contains(&m) {
            out.push(m);
            out.push('-');
        }
    }
    out.push_str(&base);
    Some(out)
}

/// Имена знаков препинания в записях вида `ctrl+slash`.
fn punct_name(s: &str) -> Option<&'static str> {
    Some(match s.to_ascii_lowercase().as_str() {
        "slash" => "/",
        "backslash" => "\\",
        "minus" => "-",
        "plus" => "+",
        "equal" | "equals" => "=",
        "comma" => ",",
        "period" | "dot" => ".",
        "semicolon" => ";",
        "quote" | "apostrophe" => "'",
        "backquote" | "grave" => "`",
        "lbracket" | "bracketleft" => "[",
        "rbracket" | "bracketright" => "]",
        _ => return None,
    })
}

/// Первая клавиша последовательности содержит `C-` или `M-` (`only_modifiers`).
pub fn has_modifier(key: &str) -> bool {
    let first = key.split(' ').next().unwrap_or("");
    let mut rest = first;
    while rest.len() > 2 && rest.as_bytes()[1] == b'-' {
        let m = rest.as_bytes()[0];
        if m == b'C' || m == b'M' {
            return true;
        }
        rest = &rest[2..];
    }
    false
}

/// Похожа ли строка на клавишу (признак универсального разбора справки).
pub fn looks_like_key(s: &str) -> bool {
    let s = s.trim();
    if s.is_empty() || s.chars().count() > 24 {
        return false;
    }
    if s.chars().count() == 1 {
        return !s.chars().next().unwrap_or(' ').is_whitespace();
    }
    if named_key(s).is_some() || parse_chord(s).is_some() {
        return true;
    }
    if s.len() == 2 && s.starts_with('^') {
        return true;
    }
    if let Some(rest) = s.strip_prefix("ESC-") {
        if rest.chars().count() == 1 || named_key(rest).is_some() {
            return true;
        }
    }
    if s.starts_with('<') && s.ends_with('>') && s.len() > 2 && !s[1..s.len() - 1].contains(' ') {
        return true;
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spec_examples() {
        assert_eq!(normalize("<C-x>"), "C-x");
        assert_eq!(normalize("ctrl-alt-t"), "C-M-t");
        assert_eq!(normalize("<Esc>"), "ESC");
    }

    #[test]
    fn forms() {
        assert_eq!(normalize("Ctrl+X"), "C-x");
        assert_eq!(normalize("^X"), "C-x");
        assert_eq!(normalize("M-f"), "M-f");
        assert_eq!(normalize("C-x C-k"), "C-x C-k");
        assert_eq!(normalize("<C-x><C-k>"), "C-x C-k");
        assert_eq!(normalize("<A-x>"), "M-x");
        assert_eq!(normalize("<S-Tab>"), "S-TAB");
        assert_eq!(normalize("shift-tab"), "S-TAB");
        assert_eq!(normalize("alt-shift-up"), "M-S-up");
        assert_eq!(normalize("gg"), "g g");
        assert_eq!(normalize(" ff"), "SP f f");
        assert_eq!(normalize("<leader>ff"), "<leader> f f");
        assert_eq!(normalize("enter"), "RET");
        assert_eq!(normalize("F5"), "f5");
        assert_eq!(normalize("ctrl+alt+shift+slash"), "C-M-S-/");
        assert_eq!(normalize("C--"), "C--");
        assert_eq!(normalize("G"), "G");
        assert_eq!(normalize("pageup"), "prior");
        assert_eq!(normalize("ESC-v"), "ESC v");
    }

    #[test]
    fn map_applies_first() {
        let map = vec![("ctrl-".to_string(), "C-".to_string())];
        assert_eq!(normalize_with("ctrl-r", &map), "C-r");
    }

    #[test]
    fn modifiers() {
        assert!(has_modifier("C-r"));
        assert!(has_modifier("S-M-x"));
        assert!(!has_modifier("S-TAB"));
        assert!(!has_modifier("g g"));
        assert!(has_modifier("C-x C-k"));
    }

    #[test]
    fn key_like() {
        assert!(looks_like_key("q"));
        assert!(looks_like_key("Ctrl-X"));
        assert!(looks_like_key("<Esc>"));
        assert!(looks_like_key("F1"));
        assert!(looks_like_key("^L"));
        assert!(!looks_like_key("--help"));
        assert!(!looks_like_key("quit"));
    }
}
