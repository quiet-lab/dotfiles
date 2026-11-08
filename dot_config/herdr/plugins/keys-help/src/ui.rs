//! Вид просмотрщика (D13): шапка, ячейки «клавиша → действие» в 3/4/5
//! колонок, заголовки групп, подписи происхождения, прокрутка, навигация
//! `h j k l g G`, поиск `/` с `n`/`N`, окно подробностей `K`, скрытие `d D u`.

use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};

use crate::view::{Section, Shown};

/// Наименьшая ширина ячейки.
pub const CELL_MIN: usize = 28;

/// Число колонок по ширине панели: 5 при W ≥ 140, 4 при W ≥ 112, иначе 3.
pub fn columns_for_width(w: usize) -> usize {
    if w >= 5 * CELL_MIN {
        5
    } else if w >= 4 * CELL_MIN {
        4
    } else {
        3
    }
}

/// Подпись блока закреплённых записей.
pub const PINNED_TITLE: &str = "закреплено";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Cell {
    Header(String),
    Entry(usize),
    Blank,
}

/// Раскладка таблицы по колонкам.
#[derive(Debug, Clone, PartialEq)]
pub struct Layout {
    pub ncols: usize,
    pub col_width: usize,
    /// Строк в колонке.
    pub rows: usize,
    pub columns: Vec<Vec<Cell>>,
    /// Позиция записи: (колонка, строка).
    pub pos: Vec<(usize, usize)>,
}

/// Записи по порядку показа.
pub fn flatten(sections: &[Section]) -> Vec<&Shown> {
    sections.iter().flat_map(|s| s.entries.iter()).collect()
}

fn fill(sections: &[Section], rows: usize) -> Vec<Vec<Cell>> {
    let mut cols: Vec<Vec<Cell>> = vec![Vec::new()];
    let mut idx = 0usize;
    let push = |cols: &mut Vec<Vec<Cell>>, c: Cell| {
        if cols.last().is_some_and(|l| l.len() >= rows) {
            cols.push(Vec::new());
        }
        if let Some(l) = cols.last_mut() {
            l.push(c);
        }
    };
    for s in sections {
        if s.entries.is_empty() {
            continue;
        }
        // Заголовок не остаётся последней строкой колонки без своих записей.
        if rows > 1 && cols.last().is_some_and(|l| l.len() + 1 == rows) {
            push(&mut cols, Cell::Blank);
        }
        let title = s.title.clone().unwrap_or_else(|| PINNED_TITLE.to_string());
        push(&mut cols, Cell::Header(title));
        for _ in &s.entries {
            push(&mut cols, Cell::Entry(idx));
            idx += 1;
        }
    }
    cols
}

/// Раскладка: записи сверху вниз по колонкам, колонки равной высоты.
pub fn layout(sections: &[Section], width: usize) -> Layout {
    let ncols = columns_for_width(width);
    let col_width = (width / ncols).max(1);
    let total: usize = sections
        .iter()
        .filter(|s| !s.entries.is_empty())
        .map(|s| s.entries.len() + 1)
        .sum();
    let mut rows = total.div_ceil(ncols).max(1);
    let columns = loop {
        let c = fill(sections, rows);
        if c.len() <= ncols {
            break c;
        }
        rows += 1;
    };
    let count = flatten(sections).len();
    let mut pos = vec![(0, 0); count];
    for (ci, col) in columns.iter().enumerate() {
        for (ri, cell) in col.iter().enumerate() {
            if let Cell::Entry(i) = cell {
                pos[*i] = (ci, ri);
            }
        }
    }
    Layout {
        ncols,
        col_width,
        rows,
        columns,
        pos,
    }
}

impl Layout {
    fn entry_at(&self, col: usize, row: usize) -> Option<usize> {
        match self.columns.get(col)?.get(row)? {
            Cell::Entry(i) => Some(*i),
            _ => None,
        }
    }

    /// Ближайшая запись колонки к строке (сначала вниз, затем вверх).
    fn nearest_in(&self, col: usize, row: usize) -> Option<usize> {
        let c = self.columns.get(col)?;
        for d in 0..c.len().max(1) {
            if let Some(i) = self.entry_at(col, row + d) {
                return Some(i);
            }
            if d <= row {
                if let Some(i) = self.entry_at(col, row - d) {
                    return Some(i);
                }
            }
        }
        None
    }
}

/// Клавиши ввода.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Key {
    Char(char),
    Esc,
    Enter,
    Backspace,
    Up,
    Down,
    Left,
    Right,
    Other,
}

/// Разбор байтов терминала. Одиночный ESC в отдельном чтении — Esc,
/// последовательность CSI/SS3 в том же чтении — стрелка или прочее.
pub fn parse_input(bytes: &[u8]) -> Vec<Key> {
    let mut out = Vec::new();
    let s = String::from_utf8_lossy(bytes);
    let chars: Vec<char> = s.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        match c {
            '\x1b' => {
                if i + 1 >= chars.len() {
                    out.push(Key::Esc);
                    i += 1;
                } else if chars[i + 1] == '[' || chars[i + 1] == 'O' {
                    let mut j = i + 2;
                    while j < chars.len() && !(chars[j].is_ascii_alphabetic() || chars[j] == '~') {
                        j += 1;
                    }
                    let fin = chars.get(j).copied().unwrap_or(' ');
                    let params: String = chars[i + 2..j.min(chars.len())].iter().collect();
                    out.push(match fin {
                        'A' => Key::Up,
                        'B' => Key::Down,
                        'C' => Key::Right,
                        'D' => Key::Left,
                        // Протокол kitty: ESC [ 27 u — Esc, ESC [ 13 u — Enter.
                        'u' if params == "27" => Key::Esc,
                        'u' if params == "13" => Key::Enter,
                        'u' if params == "127" => Key::Backspace,
                        _ => Key::Other,
                    });
                    i = j + 1;
                } else if chars[i + 1] == '\x1b' {
                    out.push(Key::Esc);
                    i += 1;
                } else {
                    // Alt+клавиша — не наша.
                    out.push(Key::Other);
                    i += 2;
                }
            }
            '\r' | '\n' => {
                out.push(Key::Enter);
                i += 1;
            }
            '\x7f' | '\x08' => {
                out.push(Key::Backspace);
                i += 1;
            }
            c if (c as u32) < 0x20 => {
                out.push(Key::Other);
                i += 1;
            }
            c => {
                out.push(Key::Char(c));
                i += 1;
            }
        }
    }
    out
}

/// Действие, которое выполняет просмотрщик после клавиши.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    None,
    Redraw,
    /// Вернуть фокус цели.
    Focus,
    /// Скрыть запись (клавиша).
    Hide(String),
    /// Скрыть группу.
    HideGroup(String),
    /// Отменить последнее скрытие.
    Undo,
}

/// Состояние навигации.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct UiState {
    pub selected: usize,
    pub top: usize,
    /// Применённый образец поиска.
    pub search: Option<String>,
    /// Ввод образца (после `/`, до Enter).
    pub input: Option<String>,
    /// Окно подробностей: прокрутка.
    pub details: Option<usize>,
}

/// Совпадает ли запись с образцом (клавиша или короткое описание, без учёта регистра).
pub fn entry_matches(e: &Shown, pat: &str) -> bool {
    let p = pat.to_lowercase();
    !p.is_empty()
        && (e.entry.key.to_lowercase().contains(&p)
            || e.entry.shown_desc().to_lowercase().contains(&p))
}

impl UiState {
    /// Сброс при смене таблицы: выбор на первой записи, поиск снят.
    pub fn reset(&mut self) {
        *self = UiState::default();
    }

    pub fn matches(&self, entries: &[&Shown]) -> Vec<usize> {
        match &self.search {
            Some(p) => entries
                .iter()
                .enumerate()
                .filter(|(_, e)| entry_matches(e, p))
                .map(|(i, _)| i)
                .collect(),
            None => Vec::new(),
        }
    }

    /// Обработка клавиши.
    pub fn handle(&mut self, key: Key, lay: &Layout, entries: &[&Shown]) -> Action {
        let n = entries.len();
        if let Some(scroll) = self.details {
            return match key {
                Key::Char('q') | Key::Esc => {
                    self.details = None;
                    Action::Redraw
                }
                Key::Char('j') | Key::Down => {
                    self.details = Some(scroll + 1);
                    Action::Redraw
                }
                Key::Char('k') | Key::Up => {
                    self.details = Some(scroll.saturating_sub(1));
                    Action::Redraw
                }
                _ => Action::None,
            };
        }
        if let Some(inp) = &mut self.input {
            match key {
                Key::Esc => {
                    self.input = None;
                }
                Key::Enter => {
                    let p = inp.clone();
                    self.input = None;
                    self.search = (!p.is_empty()).then_some(p);
                    if let Some(&first) = self.matches(entries).first() {
                        self.selected = first;
                    }
                }
                Key::Backspace => {
                    inp.pop();
                }
                Key::Char(c) => inp.push(c),
                _ => return Action::None,
            }
            return Action::Redraw;
        }
        if n == 0 {
            return match key {
                Key::Char('q') => Action::Focus,
                Key::Char('/') => {
                    self.input = Some(String::new());
                    Action::Redraw
                }
                Key::Char('u') => Action::Undo,
                _ => Action::None,
            };
        }
        let sel = self.selected.min(n - 1);
        let (col, row) = lay.pos.get(sel).copied().unwrap_or((0, 0));
        let new_sel = match key {
            Key::Char('j') | Key::Down => Some((sel + 1).min(n - 1)),
            Key::Char('k') | Key::Up => Some(sel.saturating_sub(1)),
            Key::Char('h') | Key::Left => {
                Some(if col == 0 { sel } else { lay.nearest_in(col - 1, row).unwrap_or(sel) })
            }
            Key::Char('l') | Key::Right => Some(lay.nearest_in(col + 1, row).unwrap_or(sel)),
            Key::Char('g') => Some(0),
            Key::Char('G') => Some(n - 1),
            Key::Char('n') | Key::Char('N') => {
                let m = self.matches(entries);
                if m.is_empty() {
                    None
                } else if key == Key::Char('n') {
                    Some(m.iter().copied().find(|&i| i > sel).unwrap_or(m[0]))
                } else {
                    Some(
                        m.iter()
                            .rev()
                            .copied()
                            .find(|&i| i < sel)
                            .unwrap_or(m[m.len() - 1]),
                    )
                }
            }
            _ => None,
        };
        if let Some(s) = new_sel {
            self.selected = s;
            return Action::Redraw;
        }
        match key {
            Key::Char('/') => {
                self.input = Some(String::new());
                Action::Redraw
            }
            Key::Esc => {
                self.search = None;
                Action::Redraw
            }
            Key::Char('K') => {
                self.details = Some(0);
                Action::Redraw
            }
            Key::Char('q') => Action::Focus,
            Key::Char('d') => Action::Hide(entries[sel].entry.key.clone()),
            Key::Char('D') => Action::HideGroup(entries[sel].entry.group.clone()),
            Key::Char('u') => Action::Undo,
            _ => Action::None,
        }
    }
}

/// Обрезка по ширине экрана с `…`.
pub fn truncate(s: &str, width: usize) -> String {
    if s.width() <= width {
        return s.to_string();
    }
    if width == 0 {
        return String::new();
    }
    let mut out = String::new();
    let mut w = 0;
    for c in s.chars() {
        let cw = c.width().unwrap_or(0);
        if w + cw + 1 > width {
            break;
        }
        out.push(c);
        w += cw;
    }
    out.push('…');
    out
}

fn pad(s: &str, width: usize) -> String {
    let w = s.width();
    if w >= width {
        s.to_string()
    } else {
        format!("{s}{}", " ".repeat(width - w))
    }
}

const RESET: &str = "\x1b[0m";
const REV: &str = "\x1b[7m";
const DIM: &str = "\x1b[2m";
const BOLD: &str = "\x1b[1m";
const HL: &str = "\x1b[1;33m";

/// Подсветка вхождений образца (без учёта регистра); `base` — стиль вне вхождений.
fn highlight(text: &str, pat: Option<&str>, base: &str) -> String {
    let Some(p) = pat.filter(|p| !p.is_empty()) else {
        return format!("{base}{text}");
    };
    let lower = text.to_lowercase();
    let pl = p.to_lowercase();
    // Сопоставление по символам: нижний регистр может менять длину в байтах.
    let tc: Vec<char> = text.chars().collect();
    let lc: Vec<char> = lower.chars().collect();
    let pc: Vec<char> = pl.chars().collect();
    if lc.len() != tc.len() {
        return format!("{base}{text}");
    }
    let mut out = String::from(base);
    let mut i = 0;
    while i < tc.len() {
        if i + pc.len() <= lc.len() && lc[i..i + pc.len()] == pc[..] {
            out.push_str(HL);
            out.extend(&tc[i..i + pc.len()]);
            out.push_str(RESET);
            out.push_str(base);
            i += pc.len();
        } else {
            out.push(tc[i]);
            i += 1;
        }
    }
    out
}

/// Текст шапки.
#[derive(Debug, Clone, Default)]
pub struct Header {
    pub ctx: String,
    pub target: String,
    /// Сообщение (ошибка конфигурации, «клавиши … не найдены»).
    pub message: Option<String>,
}

fn render_cell(e: &Shown, key_w: usize, cw: usize, selected: bool, pat: Option<&str>) -> String {
    let inner = cw.saturating_sub(1);
    let key = pad(&truncate(&e.entry.key, key_w), key_w);
    let label = if e.show_origin && !e.entry.origin.is_empty() {
        format!(" ·{}", e.entry.origin)
    } else {
        String::new()
    };
    let desc_room = inner.saturating_sub(key_w + 1);
    let desc_room_text = desc_room.saturating_sub(label.width());
    let desc = truncate(e.entry.shown_desc(), desc_room_text);
    let plain_w = key.width() + 1 + desc.width() + label.width();
    let fill = " ".repeat(cw.saturating_sub(plain_w));
    let base = if selected { REV } else { "" };
    let mut s = String::new();
    s.push_str(&highlight(&key, pat, &format!("{base}{BOLD}")));
    s.push_str(RESET);
    s.push_str(base);
    s.push(' ');
    s.push_str(&highlight(&desc, pat, base));
    if !label.is_empty() {
        s.push_str(RESET);
        s.push_str(base);
        s.push_str(DIM);
        s.push_str(&label);
    }
    s.push_str(RESET);
    // Заливка выбранной ячейки до конца колонки, кроме разделительного пробела.
    if selected && fill.len() > 1 {
        s.push_str(REV);
        s.push_str(&fill[1..]);
        s.push_str(RESET);
        s.push(' ');
    } else {
        s.push_str(&fill);
    }
    s
}

/// Строки подробностей записи.
pub fn details_lines(e: &Shown, ctx: &str, width: usize) -> Vec<String> {
    let mut out = Vec::new();
    let mut field = |name: &str, value: &str| {
        if value.is_empty() {
            return;
        }
        let prefix = format!("{name}: ");
        let room = width.saturating_sub(prefix.width()).max(10);
        let mut first = true;
        for line in value.lines() {
            for chunk in wrap(line, room) {
                if first {
                    out.push(format!("{BOLD}{prefix}{RESET}{chunk}"));
                    first = false;
                } else {
                    out.push(format!("{}{chunk}", " ".repeat(prefix.width())));
                }
            }
        }
    };
    let en = &e.entry;
    field("клавиша", &en.key);
    field("описание", &en.desc);
    field("полностью", &en.desc_full);
    field("действие", &en.action);
    field("группа", &en.group);
    field("происхождение", &en.origin);
    field("источник", &en.source);
    field("контекст", ctx);
    field("исходно", &en.raw);
    out
}

fn wrap(s: &str, width: usize) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    for word in s.split(' ') {
        let add = if cur.is_empty() { word.width() } else { cur.width() + 1 + word.width() };
        if add > width && !cur.is_empty() {
            out.push(std::mem::take(&mut cur));
        }
        if !cur.is_empty() {
            cur.push(' ');
        }
        cur.push_str(word);
        while cur.width() > width {
            let head: String = truncate(&cur, width + 1).trim_end_matches('…').to_string();
            let rest = cur[head.len()..].to_string();
            out.push(head);
            cur = rest;
        }
    }
    if !cur.is_empty() || out.is_empty() {
        out.push(cur);
    }
    out
}

/// Полный кадр: строки экрана без завершающего перевода строки.
pub fn render(
    st: &mut UiState,
    header: &Header,
    sections: &[Section],
    width: usize,
    height: usize,
) -> Vec<String> {
    let entries = flatten(sections);
    let lay = layout(sections, width);
    let mut lines = Vec::new();
    let hint = "/ поиск  K подробно  d/D скрыть  u вернуть  q назад";
    let mut head = format!("{BOLD}{}{RESET} · {}", header.ctx, header.target);
    let mut head_w = header.ctx.width() + 3 + header.target.width();
    if let Some(m) = &header.message {
        head.push_str(&format!("  {HL}{}{RESET}", truncate(m, width.saturating_sub(head_w + 2))));
        head_w += 2 + m.width();
    }
    // Последний столбец не занимается: запись в него переносит строку в части терминалов.
    if head_w + 3 + hint.width() <= width {
        head.push_str(&" ".repeat(width - 1 - head_w - hint.width()));
        head.push_str(&format!("{DIM}{hint}{RESET}"));
    }
    lines.push(head);
    if let Some(inp) = &st.input {
        lines.push(format!("/{inp}\x1b[7m \x1b[0m"));
    } else if let Some(p) = &st.search {
        let m = st.matches(&entries);
        let pos = m.iter().position(|&i| i == st.selected).map(|x| x + 1).unwrap_or(0);
        lines.push(format!("{DIM}/{p}  [{pos}/{}]{RESET}", m.len()));
    }
    let avail = height.saturating_sub(lines.len());
    if entries.is_empty() {
        return lines;
    }
    st.selected = st.selected.min(entries.len() - 1);
    if let Some(scroll) = st.details {
        let dl = details_lines(entries[st.selected], &header.ctx, width.saturating_sub(2));
        let max = dl.len().saturating_sub(avail);
        let scroll = scroll.min(max);
        st.details = Some(scroll);
        for l in dl.iter().skip(scroll).take(avail) {
            lines.push(format!(" {l}"));
        }
        return lines;
    }
    let (_, srow) = lay.pos[st.selected];
    if srow < st.top {
        st.top = srow;
    } else if avail > 0 && srow >= st.top + avail {
        st.top = srow + 1 - avail;
    }
    st.top = st.top.min(lay.rows.saturating_sub(avail));
    let pat = st.search.as_deref();
    // Ширина клавиши — по самой длинной клавише колонки, не больше половины ячейки.
    let key_ws: Vec<usize> = lay
        .columns
        .iter()
        .map(|c| {
            c.iter()
                .filter_map(|cell| match cell {
                    Cell::Entry(i) => Some(entries[*i].entry.key.width()),
                    _ => None,
                })
                .max()
                .unwrap_or(1)
                .min(lay.col_width / 2)
        })
        .collect();
    for row in st.top..(st.top + avail).min(lay.rows) {
        let mut line = String::new();
        for (ci, col) in lay.columns.iter().enumerate() {
            let cw = lay.col_width;
            match col.get(row) {
                Some(Cell::Entry(i)) => {
                    line.push_str(&render_cell(entries[*i], key_ws[ci], cw, *i == st.selected, pat))
                }
                Some(Cell::Header(t)) => {
                    let t = truncate(t, cw.saturating_sub(1));
                    line.push_str(&format!("{DIM}{BOLD}{}{RESET}", pad(&t, cw)));
                }
                _ => line.push_str(&" ".repeat(cw)),
            }
        }
        lines.push(line);
    }
    lines
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entry::Entry;

    fn sec(title: &str, keys: &[&str]) -> Section {
        Section {
            title: Some(title.to_string()),
            entries: keys
                .iter()
                .map(|k| Shown {
                    entry: Entry {
                        key: k.to_string(),
                        desc: format!("действие {k}"),
                        ..Default::default()
                    },
                    show_origin: false,
                })
                .collect(),
        }
    }

    #[test]
    fn widths() {
        assert_eq!(columns_for_width(90), 3);
        assert_eq!(columns_for_width(120), 4);
        assert_eq!(columns_for_width(140), 5);
        assert_eq!(columns_for_width(112), 4);
    }

    #[test]
    fn nav_columns() {
        let s = vec![sec("a", &["1", "2", "3", "4", "5"]), sec("b", &["6", "7", "8"])];
        let lay = layout(&s, 90);
        assert!(lay.columns.len() <= 3);
        let entries = flatten(&s);
        let mut st = UiState::default();
        // Первая запись второй колонки.
        let second = (0..entries.len()).find(|&i| lay.pos[i].0 == 1).expect("col1");
        st.selected = second;
        assert_eq!(st.handle(Key::Char('h'), &lay, &entries), Action::Redraw);
        assert_eq!(lay.pos[st.selected].0, 0);
        st.handle(Key::Char('G'), &lay, &entries);
        assert_eq!(st.selected, entries.len() - 1);
        st.handle(Key::Char('g'), &lay, &entries);
        assert_eq!(st.selected, 0);
    }

    #[test]
    fn search_cycle() {
        let s = vec![sec("a", &["x", "y", "xx"])];
        let lay = layout(&s, 120);
        let entries = flatten(&s);
        let mut st = UiState::default();
        st.handle(Key::Char('/'), &lay, &entries);
        st.handle(Key::Char('X'), &lay, &entries);
        st.handle(Key::Enter, &lay, &entries);
        assert_eq!(st.selected, 0);
        st.handle(Key::Char('n'), &lay, &entries);
        assert_eq!(st.selected, 2);
        st.handle(Key::Char('n'), &lay, &entries);
        assert_eq!(st.selected, 0);
        st.handle(Key::Char('N'), &lay, &entries);
        assert_eq!(st.selected, 2);
        st.handle(Key::Esc, &lay, &entries);
        assert!(st.search.is_none());
        assert_eq!(st.handle(Key::Char('d'), &lay, &entries), Action::Hide("xx".into()));
        assert_eq!(st.handle(Key::Char('q'), &lay, &entries), Action::Focus);
    }

    #[test]
    fn keys_parse() {
        assert_eq!(parse_input(b"\x1b"), vec![Key::Esc]);
        assert_eq!(parse_input(b"\x1b[A"), vec![Key::Up]);
        assert_eq!(parse_input(b"jK\r"), vec![Key::Char('j'), Key::Char('K'), Key::Enter]);
    }

    #[test]
    fn truncation() {
        assert_eq!(truncate("абвгдеж", 5), "абвг…");
        assert_eq!(truncate("abc", 5), "abc");
    }
}
