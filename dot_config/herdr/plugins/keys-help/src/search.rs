//! Ранжирование поиска (D16): ступени совпадения образца с записью, очки,
//! подсветка совпавших символов. Ступени и веса не зависят от программ.

use crate::entry::Entry;

/// Подсветка: номера символов клавиши и короткого описания.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Hl {
    pub key: Vec<usize>,
    pub desc: Vec<usize>,
}

/// Посимвольный нижний регистр с сохранением числа символов (номера
/// символов совпадают с исходной строкой).
fn lower(s: &str) -> Vec<char> {
    s.chars().map(|c| c.to_lowercase().next().unwrap_or(c)).collect()
}

fn find(hay: &[char], pat: &[char]) -> Option<usize> {
    if pat.is_empty() || pat.len() > hay.len() {
        return None;
    }
    (0..=hay.len() - pat.len()).find(|&i| hay[i..i + pat.len()] == *pat)
}

/// Нечёткое совпадение: символы образца по порядку; номера символов
/// и число пропущенных символов между первым и последним совпадением.
fn fuzzy(hay: &[char], pat: &[char]) -> Option<(Vec<usize>, usize)> {
    let mut idx = Vec::new();
    let mut j = 0;
    for (i, c) in hay.iter().enumerate() {
        if j < pat.len() && *c == pat[j] {
            idx.push(i);
            j += 1;
        }
    }
    if j < pat.len() || idx.is_empty() {
        return None;
    }
    let skipped = idx[idx.len() - 1] - idx[0] + 1 - idx.len();
    Some((idx, skipped))
}

/// Лучшая ступень совпадения: очки и подсветка; `None` — нет совпадения.
pub fn score(e: &Entry, pat: &str) -> Option<(i64, Hl)> {
    if pat.is_empty() {
        return None;
    }
    let key = &e.key;
    let desc = e.shown_desc();
    let kc: Vec<char> = key.chars().collect();
    let kl = lower(key);
    let dl = lower(desc);
    let pl = lower(pat);
    let all = |n: usize| (0..n).collect::<Vec<_>>();
    if key == pat {
        return Some((1000, Hl { key: all(kc.len()), desc: vec![] }));
    }
    if kl == pl {
        return Some((900, Hl { key: all(kc.len()), desc: vec![] }));
    }
    if kl.starts_with(&pl) {
        return Some((800, Hl { key: all(pl.len()), desc: vec![] }));
    }
    // Ступень 4: слово короткого описания начинается с образца.
    let mut start = None;
    for (i, c) in dl.iter().enumerate() {
        let at_word = i == 0 || !dl[i - 1].is_alphanumeric();
        if at_word && c.is_alphanumeric() {
            let n = start.map_or(0, |(n, _)| n + 1);
            start = Some((n, i));
            if dl[i..].starts_with(&pl) {
                let n = n as i64;
                return Some((700 - 10 * n, Hl { key: vec![], desc: (i..i + pl.len()).collect() }));
            }
        }
    }
    // Ступень 5: подстрока клавиши или короткого описания.
    let sk = find(&kl, &pl).map(|p| (500 - p as i64 / 4, Hl { key: (p..p + pl.len()).collect(), desc: vec![] }));
    let sd = find(&dl, &pl).map(|p| (500 - p as i64 / 4, Hl { key: vec![], desc: (p..p + pl.len()).collect() }));
    let best5 = match (sk, sd) {
        (Some(a), Some(b)) => Some(if a.0 >= b.0 { a } else { b }),
        (a, b) => a.or(b),
    };
    if best5.is_some() {
        return best5;
    }
    // Ступень 6: полное описание или действие.
    if find(&lower(&e.desc_full), &pl).is_some() || find(&lower(&e.action), &pl).is_some() {
        return Some((300, Hl::default()));
    }
    // Ступень 7: нечёткое совпадение.
    let fk = fuzzy(&kl, &pl).map(|(i, s)| ((200 - s as i64).max(1), Hl { key: i, desc: vec![] }));
    let fd = fuzzy(&dl, &pl).map(|(i, s)| ((200 - s as i64).max(1), Hl { key: vec![], desc: i }));
    match (fk, fd) {
        (Some(a), Some(b)) => Some(if a.0 >= b.0 { a } else { b }),
        (a, b) => a.or(b),
    }
}

/// Номера совпавших записей по убыванию очков, при равенстве — по порядку таблицы.
pub fn rank<'a>(entries: impl Iterator<Item = &'a Entry>, pat: &str) -> Vec<(usize, i64, Hl)> {
    let mut v: Vec<(usize, i64, Hl)> = entries
        .enumerate()
        .filter_map(|(i, e)| score(e, pat).map(|(s, h)| (i, s, h)))
        .collect();
    v.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    fn e(key: &str, desc: &str) -> Entry {
        Entry {
            key: key.into(),
            desc: desc.into(),
            ..Default::default()
        }
    }

    #[test]
    fn steps() {
        assert_eq!(score(&e("C-r", "история"), "C-r").map(|x| x.0), Some(1000));
        assert_eq!(score(&e("C-r", "история"), "c-R").map(|x| x.0), Some(900));
        assert_eq!(score(&e("C-r C-x", "x"), "c-r").map(|x| x.0), Some(800));
        assert_eq!(score(&e("M-d", "удалить слово вперёд"), "сло").map(|x| x.0), Some(690));
        assert_eq!(score(&e("M-d", "удалить слово"), "лово").map(|x| x.0), Some(500 - 2));
        let mut x = e("M-d", "x");
        x.action = "kill-forward-cword".into();
        assert_eq!(score(&x, "forward").map(|x| x.0), Some(300));
        assert_eq!(score(&e("M-d", "удалить слово"), "удсл").map(|x| x.0), Some(200 - 6));
        assert!(score(&e("M-d", "удалить"), "zz").is_none());
    }

    #[test]
    fn ordering() {
        let t = [e("C-a", "в начало строки"), e("C-r", "история"), e("M-r", "строка истории"), e("C-x C-r", "x")];
        let r = rank(t.iter(), "C-r");
        assert_eq!(r.iter().map(|x| x.0).collect::<Vec<_>>(), vec![1, 3]);
        let r = rank(t.iter(), "стро");
        assert_eq!(r.iter().map(|x| x.0).collect::<Vec<_>>(), vec![2, 0]);
    }
}
