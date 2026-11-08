//! Вид просмотрщика (D13): шапка, ячейки «клавиша → действие» шириной
//! не меньше 33 символов (1–5 колонок), заголовки групп, подписи происхождения, прокрутка, навигация
//! `h j k l g G`, поиск `/` с `n`/`N`, окно подробностей `K`, скрытие `d D u`.

use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};

use crate::view::{Section, SectionKind, Shown};

/// Наименьшая ширина ячейки (D13).
pub const CELL_MIN: usize = 33;

/// Число колонок по ширине панели: `n = min(5, max(1, ⌊W / 33⌋))`.
pub fn columns_for_width(w: usize) -> usize {
    (w / CELL_MIN).clamp(1, 5)
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
    layout_rows(sections, width, usize::MAX)
}

/// Раскладка с высотой колонки не больше `max_rows` (видимые строки таблицы):
/// если записи не помещаются в `ncols` колонок этой высоты, колонок становится
/// больше, и экран сдвигается по колонкам вслед за выбором. Так первые
/// разделы (курсор, дополнение, происхождения) видны на первом экране.
pub fn layout_rows(sections: &[Section], width: usize, max_rows: usize) -> Layout {
    let ncols = columns_for_width(width);
    let col_width = (width / ncols).max(1);
    let total: usize = sections
        .iter()
        .filter(|s| !s.entries.is_empty())
        .map(|s| s.entries.len() + 1)
        .sum();
    let max_rows = max_rows.max(2);
    let mut rows = total.div_ceil(ncols).max(1).min(max_rows);
    let columns = loop {
        let c = fill(sections, rows);
        if c.len() <= ncols || rows >= max_rows {
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
    /// Сообщение в строке состояния без правки конфигурации.
    Message(String),
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
    /// Выбор до поиска: Esc возвращает его вместе с прежним видом.
    pub saved: Option<usize>,
    /// Первая видимая колонка (колонок больше, чем помещается на экран).
    pub left: usize,
}

/// Строк таблицы на экране высотой `height`: без шапки и строки поиска.
pub fn table_rows(st: &UiState, height: usize) -> usize {
    let extra = usize::from(st.input.is_some() || st.search.is_some());
    height.saturating_sub(1 + extra)
}

/// Поиск (D16): вместо таблицы — один раздел совпадений по убыванию
/// релевантности, при равенстве — в порядке таблицы, с подсветкой.
pub fn search_sections(base: &[Section], pat: &str) -> Vec<Section> {
    let flat = flatten(base);
    let ranked = crate::search::rank(flat.iter().map(|s| &s.entry), pat);
    vec![Section {
        title: Some(format!("поиск: {pat}")),
        entries: ranked
            .into_iter()
            .map(|(i, _, hl)| Shown {
                hl,
                dim: false,
                ..flat[i].clone()
            })
            .collect(),
    }]
}

/// Совпадает ли запись с образцом (любая ступень D16).
pub fn entry_matches(e: &Shown, pat: &str) -> bool {
    crate::search::score(&e.entry, pat).is_some()
}

impl UiState {
    /// Сброс при смене таблицы: выбор на первой записи, поиск снят.
    pub fn reset(&mut self) {
        *self = UiState::default();
    }

    /// Совпадения: при активном поиске записи к показу — это и есть список
    /// совпадений в порядке релевантности (D16).
    pub fn matches(&self, entries: &[&Shown]) -> Vec<usize> {
        match &self.search {
            Some(_) => (0..entries.len()).collect(),
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
                    if p.is_empty() {
                        return Action::Redraw;
                    }
                    if self.search.is_none() {
                        self.saved = Some(self.selected);
                    }
                    // Список совпадений строит вызывающий; выбор — на самое релевантное.
                    self.search = Some(p);
                    self.selected = 0;
                    self.top = 0;
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
                Key::Esc if self.search.is_some() => {
                    self.search = None;
                    self.selected = self.saved.take().unwrap_or(0);
                    Action::Redraw
                }
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
                if self.search.is_none() {
                    None
                } else if key == Key::Char('n') {
                    Some((sel + 1) % n)
                } else {
                    Some((sel + n - 1) % n)
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
                if self.search.take().is_some() {
                    self.selected = self.saved.take().unwrap_or(0);
                }
                Action::Redraw
            }
            Key::Char('K') => {
                self.details = Some(0);
                Action::Redraw
            }
            Key::Char('q') => Action::Focus,
            // Кандидат дополнения — не клавиша таблицы: в `hide` не пишется.
            Key::Char('d') if entries[sel].kind == SectionKind::Completion => {
                Action::Message("кандидата дополнения скрыть нельзя".to_string())
            }
            Key::Char('d') => Action::Hide(entries[sel].entry.key.clone()),
            // Скрыть группу можно только из раздела группы: у разделов
            // закреплённых записей, курсора, дополнения и происхождения
            // своего поля скрытия в view.toml нет (D15).
            Key::Char('D') if entries[sel].kind != SectionKind::Group => {
                Action::Message(format!("группу скрыть нельзя: {}", entries[sel].kind.label()))
            }
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

/// Подсветка символов с номерами `idx`; `base` — стиль остальных символов.
fn highlight(text: &str, idx: &[usize], base: &str) -> String {
    if idx.is_empty() {
        return format!("{base}{text}");
    }
    let mut out = String::from(base);
    let mut on = false;
    for (i, c) in text.chars().enumerate() {
        let want = idx.contains(&i);
        if want && !on {
            out.push_str(HL);
            on = true;
        } else if !want && on {
            out.push_str(RESET);
            out.push_str(base);
            on = false;
        }
        out.push(c);
    }
    if on {
        out.push_str(RESET);
        out.push_str(base);
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

fn render_cell(e: &Shown, key_w: usize, cw: usize, selected: bool) -> String {
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
    let base = match (selected, e.dim) {
        (true, _) => REV.to_string(),
        (false, true) => DIM.to_string(),
        (false, false) => String::new(),
    };
    let key_style = if e.dim && !selected { DIM.to_string() } else { format!("{base}{BOLD}") };
    let mut s = String::new();
    s.push_str(&highlight(&key, &e.hl.key, &key_style));
    s.push_str(RESET);
    s.push_str(&base);
    s.push(' ');
    s.push_str(&highlight(&desc, &e.hl.desc, &base));
    if !label.is_empty() {
        s.push_str(RESET);
        s.push_str(&base);
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
    let lay = layout_rows(sections, width, table_rows(st, height));
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
        let total = entries.len();
        let pos = if total == 0 { 0 } else { st.selected.min(total - 1) + 1 };
        let tail = if total == 0 { "  нет совпадений, Esc — назад" } else { "" };
        lines.push(format!("{DIM}/{p}  [{pos}/{total}]{tail}{RESET}"));
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
    let (scol, srow) = lay.pos[st.selected];
    if scol < st.left {
        st.left = scol;
    } else if scol >= st.left + lay.ncols {
        st.left = scol + 1 - lay.ncols;
    }
    st.left = st.left.min(lay.columns.len().saturating_sub(lay.ncols));
    if srow < st.top {
        st.top = srow;
    } else if avail > 0 && srow >= st.top + avail {
        st.top = srow + 1 - avail;
    }
    st.top = st.top.min(lay.rows.saturating_sub(avail));
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
        for (ci, col) in lay.columns.iter().enumerate().skip(st.left).take(lay.ncols) {
            let cw = lay.col_width;
            match col.get(row) {
                Some(Cell::Entry(i)) => {
                    line.push_str(&render_cell(entries[*i], key_ws[ci], cw, *i == st.selected))
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
                    ..Default::default()
                })
                .collect(),
        }
    }

    #[test]
    fn widths() {
        assert_eq!(columns_for_width(40), 1);
        assert_eq!(columns_for_width(80), 2);
        assert_eq!(columns_for_width(120), 3);
        assert_eq!(columns_for_width(140), 4);
        assert_eq!(columns_for_width(180), 5);
        assert_eq!(columns_for_width(260), 5);
    }

    #[test]
    fn nav_columns() {
        let s = vec![sec("a", &["1", "2", "3", "4", "5"]), sec("b", &["6", "7", "8"])];
        let lay = layout(&s, 120);
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
        // Список совпадений строит вызывающий: здесь он уже отсортирован.
        let s = vec![sec("a", &["x", "y", "xx"])];
        let lay = layout(&s, 120);
        let entries = flatten(&s);
        let mut st = UiState { selected: 2, ..Default::default() };
        st.handle(Key::Char('/'), &lay, &entries);
        st.handle(Key::Char('X'), &lay, &entries);
        st.handle(Key::Enter, &lay, &entries);
        assert_eq!((st.selected, st.search.as_deref()), (0, Some("X")));
        st.handle(Key::Char('n'), &lay, &entries);
        assert_eq!(st.selected, 1);
        st.handle(Key::Char('N'), &lay, &entries);
        st.handle(Key::Char('N'), &lay, &entries);
        assert_eq!(st.selected, 2);
        st.handle(Key::Char('n'), &lay, &entries);
        assert_eq!(st.selected, 0);
        // Esc — прежний вид и прежний выбор.
        st.handle(Key::Esc, &lay, &entries);
        assert!(st.search.is_none());
        assert_eq!(st.selected, 2);
        assert_eq!(st.handle(Key::Char('d'), &lay, &entries), Action::Hide("xx".into()));
        assert_eq!(st.handle(Key::Char('q'), &lay, &entries), Action::Focus);
    }

    #[test]
    fn hide_keys_by_section_kind() {
        let mut s = vec![sec("a", &["k1"]), sec("b", &["k2"])];
        s[0].entries[0].kind = SectionKind::Completion;
        s[1].entries[0].kind = SectionKind::Origin;
        let lay = layout(&s, 120);
        let entries = flatten(&s);
        let mut st = UiState::default();
        assert_eq!(
            st.handle(Key::Char('d'), &lay, &entries),
            Action::Message("кандидата дополнения скрыть нельзя".into())
        );
        assert!(matches!(st.handle(Key::Char('D'), &lay, &entries), Action::Message(_)));
        st.selected = 1;
        assert_eq!(st.handle(Key::Char('d'), &lay, &entries), Action::Hide("k2".into()));
        assert_eq!(
            st.handle(Key::Char('D'), &lay, &entries),
            Action::Message("группу скрыть нельзя: раздел по происхождению".into())
        );
    }

    #[test]
    fn short_panel_pages_columns() {
        // 30 записей, 3 колонки, 6 видимых строк: колонки высотой 6, их больше трёх.
        let keys: Vec<String> = (0..30).map(|i| format!("k{i}")).collect();
        let refs: Vec<&str> = keys.iter().map(String::as_str).collect();
        let s = vec![sec("a", &refs[..4]), sec("b", &refs[4..])];
        let lay = layout_rows(&s, 110, 6);
        assert_eq!((lay.ncols, lay.rows), (3, 6));
        assert!(lay.columns.len() > 3);
        // Второй раздел начинается на первом экране.
        assert!(lay.pos[4].0 < 3);
        let mut st = UiState { selected: 29, ..Default::default() };
        let lines = render(&mut st, &Header::default(), &s, 110, 7);
        assert_eq!(lines.len(), 7);
        assert!(st.left > 0, "экран сдвинут к выбранной колонке");
        assert!(lines.iter().any(|l| l.contains("k29")));
        st.selected = 0;
        let lines = render(&mut st, &Header::default(), &s, 110, 7);
        assert_eq!(st.left, 0);
        assert!(lines.iter().any(|l| l.contains("k0\x1b")), "{lines:?}");
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
