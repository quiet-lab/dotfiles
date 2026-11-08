//! Строка ввода оболочки (D17): файлы `.line`, `.words`, `.cands` поставщика,
//! переменные позиции курсора, условия `when` правил `[[applies]]`, разбор
//! параметров команды из `--help` и `man`. Имён программ здесь нет.

use std::collections::BTreeMap;

/// Имена переменных позиции, известные ядру.
pub const VARS: &[&str] = &[
    "point",
    "len",
    "row",
    "rows",
    "rows_below",
    "col",
    "line_len",
    "word_len",
    "word_index",
    "blank",
];

/// Строка ввода: позиция курсора (в символах) и текст.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Line {
    pub point: usize,
    pub text: String,
}

/// Разбор файла `.line`: первая строка — позиция, остальное — текст как есть.
pub fn parse_line(s: &str) -> Option<Line> {
    let (first, rest) = match s.split_once('\n') {
        Some((a, b)) => (a, b),
        None => (s, ""),
    };
    let point = first.trim().parse::<usize>().ok()?;
    Some(Line {
        point,
        text: rest.to_string(),
    })
}

/// Переменные позиции курсора.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Pos {
    pub point: usize,
    pub len: usize,
    pub row: usize,
    pub rows: usize,
    pub col: usize,
    pub line_len: usize,
    pub word: String,
    pub word_index: usize,
    pub blank: bool,
}

impl Pos {
    pub fn of(line: &Line) -> Pos {
        let chars: Vec<char> = line.text.chars().collect();
        let len = chars.len();
        let point = line.point.min(len);
        let before = &chars[..point];
        let row = before.iter().filter(|&&c| c == '\n').count();
        let rows = chars.iter().filter(|&&c| c == '\n').count() + 1;
        let line_start = before.iter().rposition(|&c| c == '\n').map(|i| i + 1).unwrap_or(0);
        let line_end = chars[point..]
            .iter()
            .position(|&c| c == '\n')
            .map(|i| point + i)
            .unwrap_or(len);
        let col = point - line_start;
        let line_len = line_end - line_start;
        let ws = |c: &char| c.is_whitespace();
        let wstart = before.iter().rposition(ws).map(|i| i + 1).unwrap_or(0);
        let word: String = chars[wstart..point].iter().collect();
        // Номер слова в текущей команде: слова до курсора после последнего
        // разделителя команд (`;`, `|`, `&`, перевод строки).
        let cmd_start = before
            .iter()
            .rposition(|&c| c == ';' || c == '|' || c == '&' || c == '\n')
            .map(|i| i + 1)
            .unwrap_or(0);
        let head: String = chars[cmd_start..wstart].iter().collect();
        let word_index = head.split_whitespace().count();
        Pos {
            point,
            len,
            row,
            rows,
            col,
            line_len,
            word,
            word_index,
            blank: chars.iter().all(|c| c.is_whitespace()),
        }
    }

    /// Значение числовой переменной; `None` — неизвестное имя.
    pub fn var(&self, name: &str) -> Option<i64> {
        Some(match name {
            "point" => self.point as i64,
            "len" => self.len as i64,
            "row" => self.row as i64,
            "rows" => self.rows as i64,
            "rows_below" => self.rows as i64 - 1 - self.row as i64,
            "col" => self.col as i64,
            "line_len" => self.line_len as i64,
            "word_len" => self.word.chars().count() as i64,
            "word_index" => self.word_index as i64,
            "blank" => i64::from(self.blank),
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Op {
    Lt,
    Le,
    Gt,
    Ge,
    Eq,
    Ne,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum Operand {
    Var(String),
    Num(i64),
}

/// Условие `when`: сравнения, соединённые `&&`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct When {
    terms: Vec<(Operand, Op, Operand)>,
}

fn operand(s: &str, what: &str) -> Result<Operand, String> {
    let s = s.trim();
    if let Ok(n) = s.parse::<i64>() {
        return Ok(Operand::Num(n));
    }
    if VARS.contains(&s) {
        return Ok(Operand::Var(s.to_string()));
    }
    Err(format!("{what}: неизвестная переменная «{s}»"))
}

impl When {
    pub fn parse(text: &str, what: &str) -> Result<When, String> {
        let mut terms = Vec::new();
        for part in text.split("&&") {
            let p = part.trim();
            let ops = [("<=", Op::Le), (">=", Op::Ge), ("==", Op::Eq), ("!=", Op::Ne), ("<", Op::Lt), (">", Op::Gt)];
            let found = ops.iter().find_map(|(t, op)| p.find(t).map(|i| (i, *t, *op)));
            let Some((i, t, op)) = found else {
                return Err(format!("{what}: нет сравнения в «{p}»"));
            };
            let l = operand(&p[..i], what)?;
            let r = operand(&p[i + t.len()..], what)?;
            terms.push((l, op, r));
        }
        Ok(When { terms })
    }

    pub fn eval(&self, pos: &Pos) -> bool {
        let val = |o: &Operand| match o {
            Operand::Num(n) => *n,
            Operand::Var(v) => pos.var(v).unwrap_or(0),
        };
        self.terms.iter().all(|(l, op, r)| {
            let (a, b) = (val(l), val(r));
            match op {
                Op::Lt => a < b,
                Op::Le => a <= b,
                Op::Gt => a > b,
                Op::Ge => a >= b,
                Op::Eq => a == b,
                Op::Ne => a != b,
            }
        })
    }
}

/// Слово оболочки из `.words`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Word {
    pub kind: String,
    pub name: String,
    pub value: String,
}

pub fn parse_words(s: &str) -> Vec<Word> {
    s.lines()
        .filter_map(|l| {
            let mut it = l.splitn(3, '\t');
            let kind = it.next()?.to_string();
            let name = it.next()?.to_string();
            let value = it.next().unwrap_or("").to_string();
            (!kind.is_empty() && !name.is_empty()).then_some(Word { kind, name, value })
        })
        .collect()
}

/// Кандидаты дополнения ble.sh из `.cands`: `COMPV` и слова.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Cands {
    pub compv: String,
    pub words: Vec<String>,
}

pub fn parse_cands(s: &str) -> Cands {
    let mut it = s.split('\n');
    let compv = it.next().unwrap_or("").to_string();
    let words = it.filter(|w| !w.is_empty()).map(str::to_string).collect();
    Cands { compv, words }
}

/// Параметр команды: имена (`-x`, `--long`) и описание.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Opt {
    pub names: Vec<String>,
    pub desc: String,
}

/// Параметры из текста `--help` или `man` (D7): строка с отступом, начинающаяся
/// с `-`, имена через запятую или пробел, описание — после двух пробелов
/// или на следующей строке с большим отступом.
pub fn parse_options(text: &str) -> Vec<Opt> {
    let clean = crate::shorten::strip_man_markup(text);
    let lines: Vec<&str> = clean.lines().collect();
    let mut out: Vec<Opt> = Vec::new();
    let mut seen: BTreeMap<String, ()> = BTreeMap::new();
    for (i, l) in lines.iter().enumerate() {
        let indent = l.len() - l.trim_start().len();
        let t = l.trim_start();
        if indent == 0 || !t.starts_with('-') || t.starts_with("--- ") || t == "-" || t == "--" {
            continue;
        }
        let (head, desc) = match t.find("  ").or_else(|| t.find('\t')) {
            Some(p) => (&t[..p], t[p..].trim().to_string()),
            None => (t, String::new()),
        };
        let mut names = Vec::new();
        for part in head.split([',', ' ']) {
            let p = part.trim();
            if !p.starts_with('-') || p.len() < 2 {
                if names.is_empty() {
                    break;
                }
                continue;
            }
            let name: String = p
                .chars()
                .take_while(|c| c.is_alphanumeric() || *c == '-' || *c == '_')
                .collect();
            if name.len() >= 2 && name.chars().nth(1).is_some_and(|c| c.is_alphanumeric() || c == '-') && name != "--" {
                names.push(name);
            }
        }
        if names.is_empty() {
            continue;
        }
        let desc = if desc.is_empty() {
            lines
                .get(i + 1)
                .filter(|n| {
                    let ni = n.len() - n.trim_start().len();
                    ni > indent && !n.trim_start().starts_with('-')
                })
                .map(|n| n.trim().to_string())
                .unwrap_or_default()
        } else {
            desc
        };
        if names.iter().any(|n| seen.contains_key(n)) {
            continue;
        }
        for n in &names {
            seen.insert(n.clone(), ());
        }
        out.push(Opt { names, desc });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pos(point: usize, text: &str) -> Pos {
        Pos::of(&Line {
            point,
            text: text.to_string(),
        })
    }

    #[test]
    fn line_file() {
        assert_eq!(parse_line("3\nls -l"), Some(Line { point: 3, text: "ls -l".into() }));
        assert_eq!(parse_line("0\na\nb").map(|l| l.text), Some("a\nb".into()));
        assert_eq!(parse_line("x\n"), None);
    }

    #[test]
    fn position_vars() {
        let p = pos(4, "git sta");
        assert_eq!((p.col, p.line_len, p.word.as_str(), p.word_index), (4, 7, "", 1));
        let p = pos(7, "git sta");
        assert_eq!((p.word.as_str(), p.word_index, p.blank), ("sta", 1, false));
        let p = pos(2, "gs");
        assert_eq!((p.word.as_str(), p.word_index), ("gs", 0));
        let p = pos(6, "ab\ncdef\ng");
        assert_eq!((p.row, p.rows, p.col, p.line_len, p.var("rows_below")), (1, 3, 3, 4, Some(1)));
        let p = pos(0, "  ");
        assert!(p.blank);
        let p = pos(9, "ls | gre");
        assert_eq!((p.word.as_str(), p.word_index), ("gre", 0));
    }

    #[test]
    fn when_parse_eval() {
        let w = When::parse("col > 0 && col < line_len", "t").expect("when");
        assert!(w.eval(&pos(1, "ab")));
        assert!(!w.eval(&pos(0, "ab")));
        assert!(!w.eval(&pos(2, "ab")));
        assert!(When::parse("rows_below > 0", "t").expect("w").eval(&pos(0, "a\nb")));
        assert!(When::parse("colx > 0", "t").is_err());
        assert!(When::parse("col", "t").is_err());
    }

    #[test]
    fn words_and_cands() {
        let w = parse_words("sabbrev\tL\t| less\nalias\tll\tls -l\nfunction\tmkcd\t\n");
        assert_eq!(w.len(), 3);
        assert_eq!(w[0].value, "| less");
        let c = parse_cands("gi\ngit\ngitk\n");
        assert_eq!(c.compv, "gi");
        assert_eq!(c.words, vec!["git", "gitk"]);
    }

    #[test]
    fn options() {
        let t = "Usage: ls [OPTION]...\n  -a, --all                  do not ignore entries starting with .\n      --color[=WHEN]         color the output\n  -l                         use a long listing format\n";
        let o = parse_options(t);
        assert_eq!(o[0].names, vec!["-a", "--all"]);
        assert_eq!(o[1].names, vec!["--color"]);
        assert_eq!(o[1].desc, "color the output");
        assert_eq!(o[2].names, vec!["-l"]);
        let m = "OPTIONS\n       -v, --verbose\n              explain what is being done\n";
        let o = parse_options(m);
        assert_eq!(o[0].desc, "explain what is being done");
    }
}
