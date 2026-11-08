//! Шаблоны `*` и `?` для имён процессов, команд, режимов и контекстов.

/// Совпадает ли `text` с шаблоном `pat` целиком (`*` — любая строка, `?` — символ).
pub fn matches(pat: &str, text: &str) -> bool {
    let p: Vec<char> = pat.chars().collect();
    let t: Vec<char> = text.chars().collect();
    let (mut pi, mut ti) = (0usize, 0usize);
    let mut star: Option<(usize, usize)> = None;
    while ti < t.len() {
        if pi < p.len() && (p[pi] == '?' || p[pi] == t[ti]) {
            pi += 1;
            ti += 1;
        } else if pi < p.len() && p[pi] == '*' {
            star = Some((pi, ti));
            pi += 1;
        } else if let Some((sp, st)) = star {
            pi = sp + 1;
            ti = st + 1;
            star = Some((sp, st + 1));
        } else {
            return false;
        }
    }
    while pi < p.len() && p[pi] == '*' {
        pi += 1;
    }
    pi == p.len()
}

/// Совпадает ли `text` хотя бы с одним шаблоном списка.
pub fn any(pats: &[String], text: &str) -> bool {
    pats.iter().any(|p| matches(p, text))
}

#[cfg(test)]
mod tests {
    use super::matches;

    #[test]
    fn basic() {
        assert!(matches("fzf-*", "fzf-file-widget"));
        assert!(matches("__fzf_*", "__fzf_history__"));
        assert!(!matches("fzf-*", "fzf"));
        assert!(matches("*", ""));
        assert!(matches("*.generic", "htop.generic"));
        assert!(matches("y?zi", "yazi"));
        assert!(!matches("yazi", "yazi2"));
    }
}
