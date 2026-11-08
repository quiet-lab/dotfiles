//! Просмотрщик (D3, D4): один поток, цикл `poll` по подписке herdr,
//! inotify, signalfd, pidfd записей и команд извлечения и вводу терминала.
//! Таймеров нет: каждое действие — ответ на событие.

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::os::fd::{AsRawFd, OwnedFd, RawFd};
use std::path::{Path, PathBuf};

use serde_json::{json, Value};

use crate::channel::{self, Inotify, Records};
use crate::cmdrun::{self, Job};
use crate::context::{self, Facts, Proc, Resolution, Resolved};
use crate::engine::Engine;
use crate::entry::Entry;
use crate::extract::Build;
use crate::herdr::{event_data, event_name, s, Client, Incoming, Subscription};
use crate::input::{Input, VIEWER_MARK};
use crate::ui::{self, Action, Header, UiState};
use crate::view::{self, Edit, ViewConfig};
use crate::{paths, term, toggle, unknown};

/// Доля верхнего потомка split при открытии: нижней панели — треть (D4).
const TOP_RATIO: f32 = 0.667;
/// Наименьшее число строк содержимого просмотрщика.
const MIN_ROWS: usize = 5;
/// Наименьшая высота верхней панели, при которой просмотрщик ещё увеличивается.
const MIN_TOP_ROWS: usize = 3;

/// Прочитанный экран цели по источнику и числу строк.
type ScreenCache = HashMap<(String, Option<u32>), Option<String>>;

struct Viewer {
    client: Client,
    sub: Option<Subscription>,
    /// Подписки `pane.output_matched` цели (отдельное соединение).
    msub: Option<Subscription>,
    self_id: String,
    ws: String,
    tab: String,
    target: String,
    ino: Inotify,
    sig: Option<OwnedFd>,
    engine: Engine,
    manifest_dirs: Vec<PathBuf>,
    view_path: PathBuf,
    view_cfg: ViewConfig,
    view_err: Option<String>,
    records: Records,
    pidfds: HashMap<i32, OwnedFd>,
    job: Option<Job>,
    job_n: u64,
    resolution: Option<Resolution>,
    ctx: String,
    table: Vec<Entry>,
    message: Option<String>,
    ui: UiState,
    undo: Vec<Edit>,
    input_dirs: Vec<PathBuf>,
    counted: HashSet<(String, i32)>,
    forgotten: HashSet<String>,
    shown_key: String,
    /// Строка ввода цели (D17).
    input: Input,
    /// Ячейки раздела «дополнение».
    completion: Vec<Entry>,
    /// Извлечение параметров первого слова: команда и процесс.
    opt_job: Option<(String, Job)>,
}

fn str_list(v: &Value, key: &str) -> Vec<Value> {
    v.get(key).and_then(Value::as_array).cloned().unwrap_or_default()
}

/// Split, вторым (или первым) потомком которого является панель: путь,
/// высота split, высота панели и признак «панель — второй потомок».
pub fn parent_split(layout: &Value, pane_id: &str) -> Option<(Vec<bool>, usize, usize, bool)> {
    let panes = str_list(layout, "panes");
    let rect = panes
        .iter()
        .find(|p| s(p, "pane_id") == Some(pane_id))?
        .get("rect")?
        .clone();
    let n = |v: &Value, k: &str| v.get(k).and_then(Value::as_u64).unwrap_or(0) as usize;
    let (px, py, pw, ph) = (n(&rect, "x"), n(&rect, "y"), n(&rect, "width"), n(&rect, "height"));
    let mut best: Option<(usize, Vec<bool>, usize, bool)> = None;
    for sp in str_list(layout, "splits") {
        if s(&sp, "direction") != Some("down") {
            continue;
        }
        let r = sp.get("rect").cloned().unwrap_or(Value::Null);
        let (x, y, w, h) = (n(&r, "x"), n(&r, "y"), n(&r, "width"), n(&r, "height"));
        if x != px || w != pw || h <= ph {
            continue;
        }
        let second = y + h == py + ph;
        let first = y == py;
        if !second && !first {
            continue;
        }
        let id = s(&sp, "id").unwrap_or("");
        // Идентификатор split_<n>_<путь>: путь из 0 и 1 или root.
        let path_s = id.rsplit('_').next().unwrap_or("");
        let path: Vec<bool> = if path_s == "root" {
            Vec::new()
        } else {
            path_s.chars().map(|c| c == '1').collect()
        };
        let area = w * h;
        if best.as_ref().is_none_or(|b| area < b.0) {
            best = Some((area, path, h, second));
        }
    }
    best.map(|(_, p, h, second)| (p, h, ph, second))
}

impl Viewer {
    fn header(&self) -> Header {
        let mut msg: Vec<String> = Vec::new();
        if let Some(m) = &self.message {
            msg.push(m.clone());
        }
        if let Some(e) = &self.view_err {
            msg.push(format!("view.toml: {e}"));
        }
        if !self.engine.errors.is_empty() {
            msg.push(format!("ошибок манифестов: {} (журнал)", self.engine.errors.len()));
        }
        Header {
            ctx: if self.ctx.is_empty() { "—".to_string() } else { self.ctx.clone() },
            target: self.target.clone(),
            message: (!msg.is_empty()).then(|| msg.join("; ")),
        }
    }

    fn sections(&self) -> Vec<view::Section> {
        let manifest = self.resolution.as_ref().and_then(|r| self.engine.manifests.get(r.manifest));
        let eff = view::effective_with(&self.view_cfg, &self.ctx, manifest.map(|m| &m.view));
        let pos = self.input.pos();
        let modes: Vec<&str> = self
            .resolution
            .as_ref()
            .map(|r| vec![r.mode_native.as_str(), r.mode.as_str()])
            .unwrap_or_default();
        let rule = |e: &Entry| -> Option<(usize, bool)> {
            let (m, p) = (manifest?, pos.as_ref()?);
            m.applies
                .iter()
                .position(|a| a.matches(&e.action, &modes))
                .map(|i| (i, m.applies[i].when.eval(p)))
        };
        let has_rules = manifest.is_some_and(|m| !m.applies.is_empty()) && pos.is_some();
        let extra = view::Extra {
            origin_order: manifest.map(|m| m.origin_order.clone()).unwrap_or_default(),
            applies: if has_rules { Some(&rule) } else { None },
            completion: if pos.is_some() { self.completion.clone() } else { Vec::new() },
        };
        let base = view::apply_ext(&self.table, &eff, &extra);
        let Some(p) = &self.ui.search else {
            return base;
        };
        // Поиск: список совпадений по релевантности вместо таблицы (D16).
        ui::search_sections(&base, p)
    }

    fn render(&mut self) -> bool {
        let (w, h) = term::size();
        let sections = self.sections();
        let header = self.header();
        let lines = ui::render(&mut self.ui, &header, &sections, w, h);
        let mut out = String::from("\x1b[H");
        for (i, l) in lines.iter().enumerate() {
            if i > 0 {
                out.push_str("\r\n");
            }
            out.push_str(l);
            out.push_str("\x1b[K");
        }
        out.push_str("\x1b[J");
        term::write_out(&out)
    }

    fn load_view(&mut self) {
        match std::fs::read_to_string(view::real_path(&self.view_path)) {
            Ok(t) => match view::parse(&t) {
                Ok(c) => {
                    self.view_cfg = c;
                    self.view_err = None;
                }
                Err(e) => self.view_err = Some(e),
            },
            Err(_) => {
                self.view_cfg = ViewConfig::default();
                self.view_err = None;
            }
        }
    }

    fn view_dirs(&self) -> Vec<PathBuf> {
        let mut v = Vec::new();
        if let Some(d) = self.view_path.parent() {
            v.push(d.to_path_buf());
        }
        if let Some(d) = view::real_path(&self.view_path).parent() {
            v.push(d.to_path_buf());
        }
        v.dedup();
        v
    }

    fn subscribe(&mut self) {
        self.sub = Subscription::open(json!([
            {"type": "pane.focused"},
            {"type": "pane.updated"},
            {"type": "pane.closed"},
            {"type": "pane.moved"},
            {"type": "layout.updated"},
        ]))
        .ok();
    }

    /// Подписки на экран цели по правилам манифестов (только как повод для пересчёта).
    fn subscribe_screen(&mut self) {
        self.msub = None;
        let mut subs = Vec::new();
        for m in &self.engine.manifests {
            for r in m.detect.screen.iter().chain(m.modes.screen.iter()) {
                let mut o = json!({"type": "pane.output_matched", "pane_id": self.target,
                                   "source": r.source,
                                   "match": {"type": "regex", "value": r.regex.as_str()}});
                if let Some(l) = r.lines {
                    o["lines"] = json!(l);
                }
                subs.push(o);
            }
        }
        if !subs.is_empty() {
            self.msub = Subscription::open(Value::Array(subs)).ok();
        }
    }

    fn set_target(&mut self, pane: &str) {
        if !self.target.is_empty() {
            let old = paths::pane_dir(&self.target);
            self.ino.unwatch(&old);
            crate::input::remove_mark(&old);
        }
        self.target = pane.to_string();
        self.records = Records::default();
        if !self.target.is_empty() {
            self.watch_target_dir();
        }
        self.pidfds.clear();
        let pids: Vec<i32> = self.records.slots.iter().map(|s| s.record.pid).collect();
        for pid in pids {
            self.track_pid(pid);
        }
        self.subscribe_screen();
        self.kill_job();
        self.recompute();
    }

    /// Наблюдение каталога записей цели и перечитывание записей. Каталог
    /// создаётся здесь, до наблюдения; если его позже удалят и создадут
    /// заново (оболочка делает `mkdir -p` перед записью), событие IN_CREATE
    /// наблюдаемого каталога `panes/` вызывает эту функцию снова.
    fn watch_target_dir(&mut self) {
        let dir = paths::pane_dir(&self.target);
        let _ = std::fs::create_dir_all(&dir);
        self.ino.unwatch(&dir);
        self.ino.watch(&dir);
        // Отметка открытой панели: по ней поставщик пишет строку ввода (D17).
        let _ = std::fs::write(dir.join(VIEWER_MARK), b"");
        self.records = Records::scan(&dir);
    }

    /// Строка ввода активной записи, команды `PATH`, раздел «дополнение».
    fn update_input(&mut self) {
        let dir = paths::pane_dir(&self.target);
        let pidfds: HashSet<i32> = self.pidfds.keys().copied().collect();
        let name = self.records.active_name(|p| pidfds.contains(&p)).map(str::to_string);
        let pid = self.records.active(|p| pidfds.contains(&p)).map(|r| r.pid);
        let stem = name.and_then(|n| n.strip_suffix(".json").map(str::to_string));
        self.input.set_active(&dir, stem);
        if self.input.line.is_some() {
            if let Some((old, new)) = self.input.refresh_path(pid) {
                let keep = self.keep_dirs();
                for d in old {
                    if !keep.contains(&d) && !self.input_dirs.contains(&d) {
                        self.ino.unwatch(&d);
                    }
                }
                for d in new {
                    self.ino.watch(&d);
                }
            }
        }
        let (c, need) = self.input.completion();
        self.completion = c;
        if let Some(n) = need {
            if self.opt_job.is_none() {
                self.job_n += 1;
                match cmdrun::spawn(&n.argv, self.job_n) {
                    Some(j) => self.opt_job = Some((n.command, j)),
                    None => {
                        let _ = self.input.opts_done(&n.command, &n.argv, "");
                    }
                }
            }
        }
    }

    /// Завершилось извлечение параметров: следующий шаг или новый раздел.
    fn opt_job_done(&mut self) {
        let Some((cmd, j)) = self.opt_job.take() else { return };
        let argv = j.argv.clone();
        let out = j.finish();
        if let Some(next) = self.input.opts_done(&cmd, &argv, &out) {
            self.job_n += 1;
            match cmdrun::spawn(&next, self.job_n) {
                Some(j) => self.opt_job = Some((cmd, j)),
                None => {
                    let _ = self.input.opts_done(&cmd, &next, "");
                }
            }
        }
        self.update_input();
        self.render();
    }

    /// Каталоги, наблюдение которых не снимается сменой входов таблицы.
    fn keep_dirs(&self) -> HashSet<PathBuf> {
        self.view_dirs()
            .into_iter()
            .chain(self.manifest_dirs.iter().cloned())
            .chain(std::iter::once(paths::pane_dir(&self.target)))
            .chain(std::iter::once(paths::panes_dir()))
            .collect()
    }

    /// pidfd процесса записи; умерший процесс — удаление его записей.
    fn track_pid(&mut self, pid: i32) -> bool {
        if self.pidfds.contains_key(&pid) {
            return true;
        }
        match channel::pidfd_open(pid) {
            Some(fd) => {
                self.pidfds.insert(pid, fd);
                true
            }
            None => {
                self.drop_pid(pid);
                false
            }
        }
    }

    fn drop_pid(&mut self, pid: i32) {
        self.pidfds.remove(&pid);
        let dir = paths::pane_dir(&self.target);
        for name in self.records.remove_pid(pid) {
            let _ = std::fs::remove_file(dir.join(name));
        }
    }

    fn kill_job(&mut self) {
        if let Some(j) = self.job.take() {
            j.kill();
        }
    }

    fn procs(&mut self) -> (Vec<Proc>, Option<i32>) {
        let Ok(r) = self
            .client
            .call("pane.process_info", json!({"pane_id": self.target}))
        else {
            return (Vec::new(), None);
        };
        let info = r.get("process_info").cloned().unwrap_or(Value::Null);
        let shell = info.get("shell_pid").and_then(Value::as_i64).map(|p| p as i32);
        let procs = str_list(&info, "foreground_processes")
            .iter()
            .map(|p| Proc {
                pid: p.get("pid").and_then(Value::as_i64).unwrap_or(0) as i32,
                name: s(p, "name").unwrap_or("").to_string(),
                argv0: p
                    .get("argv")
                    .and_then(Value::as_array)
                    .and_then(|a| a.first())
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string(),
            })
            .collect();
        (procs, shell)
    }

    fn title(&mut self) -> String {
        self.client
            .call("pane.current", json!({"caller_pane_id": self.target}))
            .ok()
            .and_then(|r| r.get("pane").and_then(|p| s(p, "terminal_title_stripped")).map(str::to_string))
            .unwrap_or_default()
    }

    /// Пересчёт контекста и таблицы (ответ на событие).
    fn recompute(&mut self) {
        let (procs, shell) = self.procs();
        let title = self.title();
        let pidfds: HashSet<i32> = self.pidfds.keys().copied().collect();
        let active = self.records.active(|p| pidfds.contains(&p)).cloned();
        let target = self.target.clone();
        let client = RefCell::new(&mut self.client);
        let cache: RefCell<ScreenCache> = RefCell::new(HashMap::new());
        let screen = |source: &str, lines: Option<u32>| -> Option<String> {
            let k = (source.to_string(), lines);
            if let Some(v) = cache.borrow().get(&k) {
                return v.clone();
            }
            let mut params = json!({"pane_id": target, "source": source});
            if let Some(l) = lines {
                params["lines"] = json!(l);
            }
            let v = client
                .borrow_mut()
                .call("pane.read", params)
                .ok()
                .and_then(|r| r.get("read").and_then(|x| s(x, "text")).map(str::to_string));
            cache.borrow_mut().insert(k, v.clone());
            v
        };
        let facts = Facts {
            active: active.as_ref(),
            procs: &procs,
            shell_pid: shell,
            title: &title,
            screen: &screen,
        };
        let resolved = context::resolve(&self.engine.manifests, &facts, &paths::home());
        self.message = None;
        match resolved {
            Resolved::Nothing(cmd) => {
                self.kill_job();
                self.resolution = None;
                self.table.clear();
                self.ctx = cmd.clone().map(|c| format!("{c}.?")).unwrap_or_default();
                if let Some(c) = cmd {
                    self.note_unknown(&c, procs.iter().find(|p| p.name == c).map(|p| p.pid));
                }
            }
            Resolved::Manifest(res) => {
                let res = *res;
                if self.resolution.as_ref() != Some(&res) {
                    self.kill_job();
                }
                self.ctx = res.ctx.clone();
                self.resolution = Some(res.clone());
                self.step(&res);
            }
        }
        self.update_input();
        self.show();
    }

    /// Шаг построения: готовая таблица или запуск команды источника.
    fn step(&mut self, res: &Resolution) {
        match self.engine.step(res) {
            Build::Done(b) => {
                self.kill_job();
                self.table = b.entries;
                let dirs: Vec<PathBuf> = b
                    .files
                    .iter()
                    .filter_map(|(p, _)| p.parent().map(Path::to_path_buf))
                    .collect();
                self.watch_inputs(dirs);
                let fallback = self.engine.manifests[res.manifest].detect.fallback;
                if self.table.is_empty() && fallback {
                    self.note_unknown(&res.command, res.pid);
                } else if !self.table.is_empty() && self.forgotten.insert(res.command.clone()) {
                    let _ = unknown::forget(&unknown::default_path(), &res.command);
                }
            }
            Build::Need(argv) => {
                if self.job.as_ref().is_some_and(|j| j.argv == argv) {
                    self.message = Some("чтение таблицы…".to_string());
                    return;
                }
                self.kill_job();
                self.job_n += 1;
                match cmdrun::spawn(&argv, self.job_n) {
                    Some(j) => {
                        self.job = Some(j);
                        self.message = Some("чтение таблицы…".to_string());
                    }
                    None => {
                        self.engine.outputs.insert(argv, None);
                        self.step(res);
                    }
                }
            }
        }
    }

    fn note_unknown(&mut self, command: &str, pid: Option<i32>) {
        self.message = Some(format!("клавиши {command} не найдены"));
        let key = (command.to_string(), pid.unwrap_or(0));
        if self.counted.insert(key) {
            self.forgotten.remove(command);
            if let Err(e) = unknown::record(&unknown::default_path(), command, &unknown::today()) {
                paths::log(&format!("файл неизвестных программ: {e}"));
            }
        }
    }

    fn watch_inputs(&mut self, dirs: Vec<PathBuf>) {
        let mut keep = self.keep_dirs();
        keep.extend(self.input.path_dirs.iter().cloned());
        for d in std::mem::take(&mut self.input_dirs) {
            if !keep.contains(&d) {
                self.ino.unwatch(&d);
            }
        }
        for d in dirs {
            if !keep.contains(&d) && self.ino.watch(&d).is_some() {
                self.input_dirs.push(d);
            }
        }
    }

    /// Перерисовка; новая таблица или контекст сбрасывают выбор и поиск.
    fn show(&mut self) {
        let key = format!(
            "{}|{}",
            self.ctx,
            self.table.iter().map(|e| e.key.as_str()).collect::<Vec<_>>().join(" ")
        );
        if key != self.shown_key {
            self.ui.reset();
            self.shown_key = key;
        }
        self.render();
    }

    fn job_done(&mut self) {
        let Some(j) = self.job.take() else { return };
        let argv = j.argv.clone();
        let out = j.finish();
        self.engine.outputs.insert(argv, Some(out));
        if let Some(res) = self.resolution.clone() {
            self.message = None;
            self.step(&res);
            self.show();
        }
    }

    /// Начальная доля и минимум строк (D4).
    fn size_initial(&mut self) {
        if let Ok(r) = self.client.call("pane.layout", json!({"pane_id": self.self_id})) {
            let layout = r.get("layout").cloned().unwrap_or(Value::Null);
            if let Some((path, _, _, true)) = parent_split(&layout, &self.self_id) {
                let _ = self.client.call(
                    "layout.set_split_ratio",
                    json!({"tab_id": self.tab, "path": path, "ratio": TOP_RATIO}),
                );
            }
        }
    }

    fn ensure_min_rows(&mut self) {
        let (_, rows) = term::size();
        if rows >= MIN_ROWS {
            return;
        }
        let Ok(r) = self.client.call("pane.layout", json!({"pane_id": self.self_id})) else {
            return;
        };
        let layout = r.get("layout").cloned().unwrap_or(Value::Null);
        let Some((_, split_h, pane_h, second)) = parent_split(&layout, &self.self_id) else {
            return;
        };
        // Рамка панели: разница высоты прямоугольника и строк содержимого.
        let frame = pane_h.saturating_sub(rows);
        if split_h < MIN_ROWS + frame + MIN_TOP_ROWS || split_h == 0 {
            return;
        }
        let need = (MIN_ROWS - rows) as f32 + 0.5;
        let amount = need / split_h as f32;
        let dir = if second { "up" } else { "down" };
        let _ = self.client.call(
            "pane.resize",
            json!({"pane_id": self.self_id, "direction": dir, "amount": amount}),
        );
    }

    fn handle_event(&mut self, ev: &Value) -> bool {
        let name = event_name(ev);
        let d = event_data(ev);
        match name.as_str() {
            "pane_focused" => {
                let pane = s(d, "pane_id").unwrap_or("");
                if s(d, "workspace_id") == Some(self.ws.as_str()) && pane != self.self_id && pane != self.target {
                    // Панель другого просмотрщика целью не становится.
                    let is_viewer = self
                        .client
                        .call("pane.current", json!({"caller_pane_id": pane}))
                        .ok()
                        .and_then(|r| r.get("pane").and_then(|p| p.get("tokens")).and_then(|t| t.get(toggle::TOKEN)).cloned())
                        .is_some();
                    if !is_viewer {
                        let p = pane.to_string();
                        self.set_target(&p);
                    }
                }
            }
            "pane_updated" => {
                if d.get("pane").and_then(|p| s(p, "pane_id")) == Some(self.target.as_str()) {
                    self.recompute();
                }
            }
            "pane_closed" => {
                let pane = s(d, "pane_id").unwrap_or("");
                if pane == self.self_id {
                    return false;
                }
                if pane == self.target {
                    let next = self
                        .client
                        .call("pane.layout", json!({"pane_id": self.self_id}))
                        .ok()
                        .and_then(|r| {
                            let l = r.get("layout").cloned()?;
                            let f = s(&l, "focused_pane_id").map(str::to_string);
                            f.filter(|f| f != &self.self_id).or_else(|| {
                                str_list(&l, "panes")
                                    .iter()
                                    .filter_map(|p| s(p, "pane_id").map(str::to_string))
                                    .find(|p| p != &self.self_id)
                            })
                        });
                    if let Some(n) = next {
                        self.set_target(&n);
                    }
                }
                // Каталог записей закрытой панели (и ссылки прежних id на него)
                // больше не нужен: оболочка панели уже завершена.
                channel::remove_pane_dir(pane);
            }
            "pane_moved" => {
                let prev = s(d, "previous_pane_id").unwrap_or("").to_string();
                let new = d.get("pane").and_then(|p| s(p, "pane_id")).unwrap_or("").to_string();
                if prev == self.self_id && !new.is_empty() {
                    self.self_id = new.clone();
                    if let Some(p) = d.get("pane") {
                        self.ws = s(p, "workspace_id").unwrap_or(&self.ws).to_string();
                        self.tab = s(p, "tab_id").unwrap_or(&self.tab).to_string();
                    }
                } else if prev == self.target && !new.is_empty() {
                    channel::move_pane_dir(&prev, &new);
                    self.set_target(&new);
                }
            }
            "layout_updated"
                if d.get("layout").and_then(|l| s(l, "tab_id")) == Some(self.tab.as_str()) =>
            {
                self.ensure_min_rows();
            }
            _ => {}
        }
        true
    }

    fn handle_fs(&mut self) {
        let events = self.ino.read();
        let target_dir = paths::pane_dir(&self.target);
        let view_real = view::real_path(&self.view_path);
        let view_names: Vec<String> = [&self.view_path, &view_real]
            .iter()
            .filter_map(|p| p.file_name().map(|n| n.to_string_lossy().to_string()))
            .collect();
        let mut recompute = false;
        let mut reload_view = false;
        let mut reload_manifests = false;
        let mut input_changed = false;
        let mut path_changed = false;
        let panes_dir = paths::panes_dir();
        for e in events {
            if e.dir == panes_dir && e.dir != target_dir {
                if !self.target.is_empty()
                    && e.name == self.target
                    && e.mask & (libc::IN_CREATE | libc::IN_MOVED_TO) != 0
                {
                    self.watch_target_dir();
                    let pids: Vec<i32> = self.records.slots.iter().map(|s| s.record.pid).collect();
                    for pid in pids {
                        self.track_pid(pid);
                    }
                    recompute = true;
                }
                continue;
            }
            if e.dir == target_dir {
                if !e.name.ends_with(".json") {
                    if e.mask & (libc::IN_CLOSE_WRITE | libc::IN_MOVED_TO | libc::IN_DELETE | libc::IN_MOVED_FROM) != 0
                        && self.input.on_file(&e.name)
                    {
                        input_changed = true;
                    }
                    continue;
                }
                if e.mask & (libc::IN_CLOSE_WRITE | libc::IN_MOVED_TO) != 0 {
                    let p = target_dir.join(&e.name);
                    if let Some(r) = std::fs::read_to_string(&p).ok().and_then(|t| channel::parse_record(&t)) {
                        let pid = r.pid;
                        self.records.put(e.name.clone(), r);
                        self.track_pid(pid);
                        recompute = true;
                    }
                } else if e.mask & (libc::IN_DELETE | libc::IN_MOVED_FROM) != 0 {
                    self.records.remove(&e.name);
                    recompute = true;
                }
                continue;
            }
            if self.manifest_dirs.contains(&e.dir) && e.name.ends_with(".toml") {
                reload_manifests = true;
            }
            if self.view_dirs().contains(&e.dir) && view_names.contains(&e.name) {
                reload_view = true;
            }
            if self.input_dirs.contains(&e.dir) {
                recompute = true;
            }
            if self.input.is_path_dir(&e.dir) {
                path_changed = true;
            }
        }
        if reload_manifests {
            self.engine.reload(&self.manifest_dirs);
            for err in &self.engine.errors {
                paths::log(err);
            }
            channel::write_env_vars(&self.engine.env_names());
            self.subscribe_screen();
            recompute = true;
        }
        if reload_view {
            self.load_view();
        }
        if path_changed {
            self.input.rebuild_path();
            input_changed = true;
        }
        if recompute {
            self.recompute();
        } else if input_changed {
            // Строка ввода меняет только верхние разделы, без пересчёта контекста.
            self.update_input();
            self.render();
        } else if reload_view {
            self.render();
        }
    }

    fn handle_action(&mut self, a: Action) {
        match a {
            Action::None => {}
            Action::Redraw => {
                self.render();
            }
            Action::Focus => {
                let _ = self.client.call("pane.focus", json!({"pane_id": self.target}));
            }
            Action::Hide(key) => self.edit(Edit::Add {
                ctx: self.ctx.clone(),
                field: "hide".to_string(),
                value: key,
            }),
            Action::HideGroup(g) => self.edit(Edit::Add {
                ctx: self.ctx.clone(),
                field: "hide_groups".to_string(),
                value: g,
            }),
            Action::Undo => {
                if let Some(e) = self.undo.pop() {
                    let rev = match e {
                        Edit::Add { ctx, field, value } => Edit::Remove { ctx, field, value },
                        r => r,
                    };
                    self.write(rev);
                }
            }
        }
    }

    fn edit(&mut self, e: Edit) {
        if self.ctx.is_empty() {
            return;
        }
        if self.write(e.clone()) {
            self.undo.push(e);
        }
    }

    fn write(&mut self, e: Edit) -> bool {
        match view::write_edit(&self.view_path, &e) {
            Ok(()) => {
                // Изменение придёт и событием inotify; применяем сразу.
                self.load_view();
                self.render();
                true
            }
            Err(err) => {
                self.message = Some(format!("запись view.toml: {err}"));
                self.render();
                false
            }
        }
    }

    /// Уборка каталогов панелей, закрытых без просмотрщика. Снимок имён —
    /// до запроса списка панелей, подписка на `pane.closed` уже открыта.
    fn sweep_pane_dirs(&mut self) {
        let panes = paths::panes_dir();
        let names = channel::pane_dir_names_in(&panes);
        let Ok(r) = self.client.call("pane.list", json!({})) else {
            return;
        };
        let live: HashSet<String> = str_list(&r, "panes")
            .iter()
            .filter_map(|p| s(p, "pane_id").map(str::to_string))
            .collect();
        if live.is_empty() {
            return;
        }
        channel::sweep_pane_dirs_in(&panes, &names, &live);
    }

    fn cleanup(&mut self) {
        self.kill_job();
        if let Some((_, j)) = self.opt_job.take() {
            j.kill();
        }
        if !self.target.is_empty() {
            crate::input::remove_mark(&paths::pane_dir(&self.target));
        }
    }
}

enum Tag {
    Stdin,
    Sub,
    MSub,
    Ino,
    Sig,
    Job,
    OptJob,
    Pid(i32),
}

pub fn run() -> Result<(), String> {
    let self_id = std::env::var("HERDR_PANE_ID").map_err(|_| "нет HERDR_PANE_ID".to_string())?;
    let mut client = Client::connect().map_err(|e| e.to_string())?;
    let _ = toggle::mark(&mut client, &self_id);
    let cur = client
        .call("pane.current", json!({"caller_pane_id": self_id}))
        .map_err(|e| e.to_string())?;
    let info = cur.get("pane").cloned().unwrap_or(Value::Null);
    let ws = s(&info, "workspace_id").unwrap_or("").to_string();
    let tab = s(&info, "tab_id").unwrap_or("").to_string();
    let target = std::env::var("KEYS_HELP_TARGET")
        .ok()
        .filter(|t| !t.is_empty() && t != &self_id)
        .unwrap_or_default();
    let manifest_dirs = paths::manifest_dirs();
    let engine = Engine::load(&manifest_dirs);
    for e in &engine.errors {
        paths::log(e);
    }
    channel::write_env_vars(&engine.env_names());
    let _term = term::RawTerm::enter();
    let mut v = Viewer {
        client,
        sub: None,
        msub: None,
        self_id,
        ws,
        tab,
        target: String::new(),
        ino: Inotify::new().map_err(|e| e.to_string())?,
        sig: term::signalfd(),
        engine,
        manifest_dirs,
        view_path: paths::view_path(),
        view_cfg: ViewConfig::default(),
        view_err: None,
        records: Records::default(),
        pidfds: HashMap::new(),
        job: None,
        job_n: 0,
        resolution: None,
        ctx: String::new(),
        table: Vec::new(),
        message: None,
        ui: UiState::default(),
        undo: Vec::new(),
        input_dirs: Vec::new(),
        counted: HashSet::new(),
        forgotten: HashSet::new(),
        shown_key: String::new(),
        input: Input::default(),
        completion: Vec::new(),
        opt_job: None,
    };
    v.load_view();
    for d in v.view_dirs() {
        let _ = std::fs::create_dir_all(&d);
        v.ino.watch(&d);
    }
    for d in v.manifest_dirs.clone() {
        v.ino.watch(&d);
    }
    // Каталог panes/ наблюдается ради IN_CREATE каталога цели (см.
    // watch_target_dir).
    let panes_dir = paths::panes_dir();
    let _ = std::fs::create_dir_all(&panes_dir);
    v.ino.watch(&panes_dir);
    v.subscribe();
    v.sweep_pane_dirs();
    v.size_initial();
    v.ensure_min_rows();
    let target = if target.is_empty() {
        // Цель не передана: панель в фокусе tab, кроме самой панели просмотрщика.
        v.client
            .call("pane.layout", json!({"pane_id": v.self_id}))
            .ok()
            .and_then(|r| r.get("layout").and_then(|l| s(l, "focused_pane_id")).map(str::to_string))
            .filter(|p| p != &v.self_id)
            .unwrap_or_default()
    } else {
        target
    };
    v.set_target(&target);

    let res = event_loop(&mut v);
    v.cleanup();
    res
}

fn event_loop(v: &mut Viewer) -> Result<(), String> {
    loop {
        let mut fds: Vec<libc::pollfd> = Vec::new();
        let mut tags: Vec<Tag> = Vec::new();
        let mut add = |fd: RawFd, tag: Tag, fds: &mut Vec<libc::pollfd>| {
            fds.push(libc::pollfd { fd, events: libc::POLLIN, revents: 0 });
            tags.push(tag);
        };
        add(0, Tag::Stdin, &mut fds);
        if let Some(sub) = &v.sub {
            add(sub.fd(), Tag::Sub, &mut fds);
        }
        if let Some(m) = &v.msub {
            add(m.fd(), Tag::MSub, &mut fds);
        }
        add(v.ino.fd.as_raw_fd(), Tag::Ino, &mut fds);
        if let Some(sfd) = &v.sig {
            add(sfd.as_raw_fd(), Tag::Sig, &mut fds);
        }
        if let Some(j) = &v.job {
            add(j.pidfd.as_raw_fd(), Tag::Job, &mut fds);
        }
        if let Some((_, j)) = &v.opt_job {
            add(j.pidfd.as_raw_fd(), Tag::OptJob, &mut fds);
        }
        for (pid, fd) in &v.pidfds {
            add(fd.as_raw_fd(), Tag::Pid(*pid), &mut fds);
        }
        // Ожидание без срока: -1 — только события дескрипторов.
        // SAFETY: poll по локальному массиву pollfd его длины.
        let n = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, -1) };
        if n < 0 {
            let e = std::io::Error::last_os_error();
            if e.kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            return Err(e.to_string());
        }
        let ready: Vec<(usize, i16)> = fds
            .iter()
            .enumerate()
            .filter(|(_, f)| f.revents != 0)
            .map(|(i, f)| (i, f.revents))
            .collect();
        for (i, rev) in ready {
            match tags[i] {
                Tag::Stdin => {
                    if rev & (libc::POLLHUP | libc::POLLERR | libc::POLLNVAL) != 0 && rev & libc::POLLIN == 0 {
                        return Ok(());
                    }
                    let mut buf = [0u8; 1024];
                    // SAFETY: чтение в локальный буфер его размера.
                    let r = unsafe { libc::read(0, buf.as_mut_ptr().cast(), buf.len()) };
                    if r <= 0 {
                        return Ok(());
                    }
                    let sections = v.sections();
                    let entries_owned: Vec<view::Shown> = ui::flatten(&sections).into_iter().cloned().collect();
                    let entries: Vec<&view::Shown> = entries_owned.iter().collect();
                    let (w, _) = term::size();
                    let lay = ui::layout(&sections, w);
                    for k in ui::parse_input(&buf[..r as usize]) {
                        let a = v.ui.handle(k, &lay, &entries);
                        v.handle_action(a);
                    }
                }
                Tag::Sub => {
                    let incoming = v.sub.as_mut().map(Subscription::read).unwrap_or_default();
                    for inc in incoming {
                        match inc {
                            Incoming::Event(ev) => {
                                if !v.handle_event(&ev) {
                                    return Ok(());
                                }
                            }
                            Incoming::Lost => {
                                v.subscribe();
                                v.recompute();
                            }
                            Incoming::Closed => {
                                // Сервер herdr остановлен или подписка закрыта: новая
                                // подписка; если сервера нет — выход.
                                v.subscribe();
                                if v.sub.is_none() {
                                    return Ok(());
                                }
                                v.recompute();
                            }
                        }
                    }
                }
                Tag::MSub => {
                    let incoming = v.msub.as_mut().map(Subscription::read).unwrap_or_default();
                    let mut again = false;
                    let mut hit = false;
                    for inc in incoming {
                        match inc {
                            Incoming::Event(_) => hit = true,
                            Incoming::Lost | Incoming::Closed => again = true,
                        }
                    }
                    if again {
                        v.subscribe_screen();
                    }
                    if hit || again {
                        v.recompute();
                    }
                }
                Tag::Ino => v.handle_fs(),
                Tag::Sig => {
                    let sigs = v.sig.as_ref().map(term::read_signals).unwrap_or_default();
                    for s in sigs {
                        if s == libc::SIGWINCH {
                            v.ensure_min_rows();
                            v.render();
                        } else {
                            return Ok(());
                        }
                    }
                }
                Tag::Job => v.job_done(),
                Tag::OptJob => v.opt_job_done(),
                Tag::Pid(pid) => {
                    v.drop_pid(pid);
                    v.recompute();
                }
            }
        }
    }
}

/// Печать таблицы контекста (`table <контекст> --pane <id>`): то же, что
/// показывает просмотрщик, с учётом конфигурации представления.
pub fn print_table(ctx: &str, pane: Option<&str>, as_json: bool) -> Result<(), String> {
    let dirs = paths::manifest_dirs();
    let mut engine = Engine::load(&dirs);
    for e in &engine.errors {
        eprintln!("{e}");
    }
    let mut res = context::from_ctx(&engine.manifests, ctx)
        .ok_or_else(|| format!("нет манифеста для контекста {ctx}"))?;
    if let Some(p) = pane {
        let recs = Records::scan(&paths::pane_dir(p));
        let m = &engine.manifests[res.manifest];
        let provider = m.detect.provider.clone().unwrap_or_else(|| m.program.clone());
        if let Some(r) = recs.latest_of(&provider) {
            res.record = Some(r.clone());
            res.pid = Some(r.pid);
        }
    }
    let built = engine.build_blocking(&res);
    let cfg = std::fs::read_to_string(view::real_path(&paths::view_path()))
        .ok()
        .map(|t| view::parse(&t))
        .transpose()?
        .unwrap_or_default();
    let m = &engine.manifests[res.manifest];
    let extra = view::Extra {
        origin_order: m.origin_order.clone(),
        ..Default::default()
    };
    let sections = view::apply_ext(&built.entries, &view::effective_with(&cfg, &res.ctx, Some(&m.view)), &extra);
    use std::io::Write;
    let mut out = std::io::stdout().lock();
    // Закрытый канал вывода (`| head`) — не ошибка.
    if as_json {
        let list: Vec<Value> = sections
            .iter()
            .flat_map(|s| {
                let pinned = s.title.is_none();
                s.entries.iter().map(move |e| {
                    let mut v = serde_json::to_value(&e.entry).unwrap_or(Value::Null);
                    v["pinned"] = json!(pinned);
                    v["show_origin"] = json!(e.show_origin);
                    v
                })
            })
            .collect();
        let _ = writeln!(out, "{}", json!({"context": res.ctx, "entries": list}));
        return Ok(());
    }
    let _ = writeln!(out, "# {}", res.ctx);
    for s in &sections {
        let title = s.title.clone().unwrap_or_else(|| ui::PINNED_TITLE.to_string());
        for e in &s.entries {
            let _ = writeln!(
                out,
                "{}\t{}\t{}\t{}\t{}",
                title,
                e.entry.key,
                e.entry.shown_desc(),
                e.entry.origin,
                e.entry.action
            );
        }
    }
    Ok(())
}

/// `unknown list`.
pub fn print_unknown() {
    for u in unknown::list(&unknown::default_path()) {
        println!("{}\t{}\t{}", u.command, u.count, u.last);
    }
}
