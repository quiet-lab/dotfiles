//! Задача 6.7: файл неизвестных программ (счётчик, дата, без повторов, удаление при появлении
//! таблицы) и кеш универсального извлекателя (повторного запуска `man`/`--help` нет).
//!
//! Кеш читает каталоги по переменным окружения процесса, поэтому тесты с окружением идут
//! под одним замком (только тестовый процесс, ресурс — окружение процесса).

mod common;

use std::sync::Mutex;

use common::*;
use keys_help::context;
use keys_help::engine::{disk_key, Engine};
use keys_help::extract::Build;
use keys_help::unknown;

static ENV: Mutex<()> = Mutex::new(());

// ---- файл неизвестных программ ----

#[test]
fn counter_date_one_table_per_command() {
    let d = tmpdir("unk-file");
    let p = d.join("state/unknown-programs.toml");
    let date = unknown::today();
    assert_eq!(date.len(), 10);
    assert_eq!(date.matches('-').count(), 2);
    unknown::record(&p, "kh-unknown", &date).unwrap();
    unknown::record(&p, "kh-unknown", &date).unwrap();
    let text = std::fs::read_to_string(&p).unwrap();
    assert_eq!(text.matches("[program.kh-unknown]").count(), 1, "{text}");
    let l = unknown::list(&p);
    assert_eq!(l.len(), 1);
    assert_eq!((l[0].command.as_str(), l[0].count, l[0].last.as_str()), ("kh-unknown", 2, date.as_str()));
    // Строка в файле — `count = 2` и сегодняшняя дата `last`.
    let t: toml::Table = text.parse().unwrap();
    let prog = &t["program"]["kh-unknown"];
    assert_eq!(prog["count"].as_integer(), Some(2));
    assert_eq!(prog["last"].as_str(), Some(date.as_str()));
}

#[test]
fn list_sorted_by_count_desc_then_name() {
    let t = {
        let mut s = String::new();
        for (c, n) in [("b", 1), ("a", 1), ("z", 3), ("m", 2)] {
            for _ in 0..n {
                s = unknown::bump_text(&s, c, "2026-11-08").unwrap();
            }
        }
        s
    };
    let order: Vec<String> = unknown::list_text(&t).into_iter().map(|u| u.command).collect();
    assert_eq!(order, vec!["z", "m", "a", "b"]);
}

#[test]
fn forget_removes_command_when_table_appears() {
    let d = tmpdir("unk-forget");
    let p = d.join("unknown-programs.toml");
    unknown::record(&p, "kh-a", "2026-11-08").unwrap();
    unknown::record(&p, "kh-b", "2026-11-08").unwrap();
    unknown::forget(&p, "kh-a").unwrap();
    let l = unknown::list(&p);
    assert_eq!(l.len(), 1);
    assert_eq!(l[0].command, "kh-b");
    // Нет файла или команды — не ошибка и файл не создаётся.
    let none = d.join("none.toml");
    unknown::forget(&none, "x").unwrap();
    assert!(!none.exists());
    unknown::forget(&p, "zzz").unwrap();
    assert_eq!(unknown::list(&p).len(), 1);
    // Новое появление после удаления начинает счёт заново.
    unknown::record(&p, "kh-a", "2026-11-09").unwrap();
    assert_eq!(unknown::list(&p).iter().find(|u| u.command == "kh-a").unwrap().count, 1);
}

#[test]
fn broken_and_missing_file_lists_nothing() {
    assert!(unknown::list_text("[[[").is_empty());
    assert!(unknown::list_text("").is_empty());
    assert!(unknown::list(&tmpdir("unk-none").join("нет.toml")).is_empty());
}

#[test]
fn bump_keeps_comments_and_other_tables() {
    let src = "# моя заметка\n[program.old]\ncount = 5\nlast = \"2026-01-01\"\n";
    let out = unknown::bump_text(src, "new", "2026-11-08").unwrap();
    assert!(out.contains("# моя заметка"));
    let l = unknown::list_text(&out);
    assert_eq!(l.len(), 2);
    assert_eq!(l[0].command, "old");
    assert_eq!(l[0].count, 5);
}

#[test]
fn parallel_writers_do_not_lose_counts() {
    // Файл один на пользователя, писать могут несколько просмотрщиков: замок на файл.
    let d = tmpdir("unk-par");
    let p = d.join("unknown-programs.toml");
    let hs: Vec<_> = (0..8)
        .map(|_| {
            let p = p.clone();
            std::thread::spawn(move || {
                for _ in 0..10 {
                    unknown::record(&p, "kh-par", "2026-11-08").unwrap();
                }
            })
        })
        .collect();
    for h in hs {
        h.join().unwrap();
    }
    assert_eq!(unknown::list(&p)[0].count, 80);
}

// ---- кеш универсального извлекателя ----

const MAN: &str = "KEY BINDINGS\n       q          Quit now\n       j          Down one line\n";

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

fn resolution(e: &Engine, cmd: &str) -> context::Resolution {
    let mut r = context::from_ctx(&e.manifests, &format!("{cmd}.generic")).expect("generic");
    r.command = cmd.to_string();
    r
}

#[test]
fn generic_cache_does_not_rerun_commands_on_same_inputs() {
    let d = tmpdir("cache");
    let bin = d.join("bin");
    let man = d.join("man/man1");
    std::fs::create_dir_all(&bin).unwrap();
    std::fs::create_dir_all(&man).unwrap();
    let exe = bin.join("kh-cache");
    std::fs::write(&exe, "#!/bin/sh\nexit 0\n").unwrap();
    std::fs::write(man.join("kh-cache.1"), ".TH X 1\n").unwrap();
    let path = format!("{}:{}", bin.display(), std::env::var("PATH").unwrap_or_default());
    let _env = Env::set(&[
        ("XDG_CACHE_HOME", d.join("cache").display().to_string()),
        ("PATH", path),
        ("MANPATH", d.join("man").display().to_string()),
        ("HOME", d.display().to_string()),
    ]);
    let dirs = [root().join("manifests")];

    // Первый запуск: нужен вывод man.
    let mut e1 = Engine::load(&dirs);
    let res = resolution(&e1, "kh-cache");
    let argv = match e1.step(&res) {
        Build::Need(a) => a,
        Build::Done(_) => panic!("кеша ещё нет"),
    };
    assert_eq!(argv, vec!["man", "-P", "cat", "kh-cache"]);
    e1.outputs.insert(argv, Some(MAN.to_string()));
    let first = match e1.step(&res) {
        Build::Done(b) => b.entries,
        Build::Need(a) => panic!("{a:?}"),
    };
    assert_eq!(keys(&first), vec!["q", "j"]);
    // Повторный шаг в том же процессе — из памяти, без новых команд.
    assert!(matches!(e1.step(&res), Build::Done(_)));

    // Новый просмотрщик (пустая память, пустые выводы): таблица берётся с диска без `man`.
    let mut e2 = Engine::load(&dirs);
    let res2 = resolution(&e2, "kh-cache");
    match e2.step(&res2) {
        Build::Done(b) => assert_eq!(b.entries, first),
        Build::Need(a) => panic!("команда запущена повторно: {a:?}"),
    }
    assert!(e2.outputs.is_empty());

    // Изменился исполняемый файл (размер) — входы другие, нужен новый вывод.
    std::fs::write(&exe, "#!/bin/sh\n# изменён\nexit 0\n").unwrap();
    let mut e3 = Engine::load(&dirs);
    let res3 = resolution(&e3, "kh-cache");
    assert!(matches!(e3.step(&res3), Build::Need(_)), "кеш не сброшен после изменения файла");
}

#[test]
fn generic_cache_invalidated_by_man_page_mtime() {
    let d = tmpdir("cache-man");
    let bin = d.join("bin");
    let man = d.join("man/man1");
    std::fs::create_dir_all(&bin).unwrap();
    std::fs::create_dir_all(&man).unwrap();
    std::fs::write(bin.join("kh-cm"), "#!/bin/sh\nexit 0\n").unwrap();
    let page = man.join("kh-cm.1");
    std::fs::write(&page, ".TH X 1\n").unwrap();
    let path = format!("{}:{}", bin.display(), std::env::var("PATH").unwrap_or_default());
    let _env = Env::set(&[
        ("XDG_CACHE_HOME", d.join("cache").display().to_string()),
        ("PATH", path),
        ("MANPATH", d.join("man").display().to_string()),
        ("HOME", d.display().to_string()),
    ]);
    let k1 = disk_key("kh-cm", None);
    assert_eq!(k1, disk_key("kh-cm", None), "ключ входов детерминирован");
    let f = std::fs::File::options().write(true).open(&page).unwrap();
    f.set_modified(std::time::SystemTime::now() + std::time::Duration::from_secs(3600)).unwrap();
    assert_ne!(k1, disk_key("kh-cm", None), "mtime man-страницы не учтён");
    // Другой путь исполняемого файла — другой ключ.
    assert!(k1.contains("kh-cm"));
}

#[test]
fn manifest_program_tables_are_not_written_to_disk_cache() {
    // Кешируется на диске только результат универсального извлекателя.
    let d = tmpdir("cache-prog");
    let _env = Env::set(&[
        ("XDG_CACHE_HOME", d.join("cache").display().to_string()),
        ("HOME", d.display().to_string()),
    ]);
    let mut e = Engine::load(&[root().join("manifests"), fixtures().join("manifests")]);
    let res = context::from_ctx(&e.manifests, "kh-fake").unwrap();
    let t = e.build_blocking(&res);
    assert_eq!(t.entries.len(), 3);
    assert!(!d.join("cache").exists(), "кеш программы с манифестом записан на диск");
}

// ---- кеш таблиц с командными источниками по записи (D6) ----

const REV_MANIFEST: &str = r#"
program = "kh-rev"
origins = ["kh-rev"]

[detect]
provider = "kh-rev"

[modes]
default = "main"

[[source]]
kind = "regex"
command = ["kh-dump", "{record.server}"]
regex = '''^(?P<key>\S+) (?P<action>.+)$'''
"#;

fn rev_record(pid: i32, rev: u64) -> keys_help::channel::Record {
    let mut r = keys_help::channel::parse_record(&format!(
        r#"{{"v":1,"program":"kh-rev","mode":"main","pid":{pid},"state":"active","server":"/s{pid}"}}"#
    ))
    .unwrap();
    r.rev = rev;
    r
}

fn rev_res(e: &Engine, pid: i32, rev: u64) -> context::Resolution {
    let mut r = context::from_ctx(&e.manifests, "kh-rev.main").expect("kh-rev");
    r.record = Some(rev_record(pid, rev));
    r.pid = Some(pid);
    r
}

fn build_with(e: &mut Engine, (pid, rev): (i32, u64), out: &str) -> Vec<String> {
    let res = &rev_res(e, pid, rev);
    match e.step(res) {
        Build::Need(a) => {
            e.outputs.insert(a, Some(out.to_string()));
            match e.step(res) {
                Build::Done(b) => b.entries.into_iter().map(|x| x.key).collect(),
                Build::Need(a) => panic!("{a:?}"),
            }
        }
        Build::Done(b) => b.entries.into_iter().map(|x| x.key).collect(),
    }
}

#[test]
fn record_revision_rebuilds_command_table() {
    let d = tmpdir("rev");
    std::fs::write(d.join("kh-rev.toml"), REV_MANIFEST).unwrap();
    let mut e = Engine::load(&[d]);
    assert!(e.errors.is_empty(), "{:?}", e.errors);
    assert_eq!(build_with(&mut e, (10, 1), "a x\n"), vec!["a"]);
    // Та же ревизия — из кеша, без команды.
    assert!(matches!(e.step(&rev_res(&e, 10, 1)), Build::Done(_)));
    // Запись перезаписана (смена режима): команда запускается заново,
    // новые привязки (LSP) попадают в таблицу.
    assert_eq!(build_with(&mut e, (10, 2), "a x\nb y\n"), vec!["a", "b"]);
    // Таблица прежней ревизии того же процесса снята.
    assert_eq!(e.cache_len(), 1);
    // Процесс завершился — его таблицы сняты.
    build_with(&mut e, (11, 1), "c z\n");
    assert_eq!(e.cache_len(), 2);
    e.forget_pid(10);
    assert_eq!(e.cache_len(), 1);
    // Предел размера кеша.
    for pid in 100..(100 + keys_help::engine::CACHE_MAX as i32 + 5) {
        build_with(&mut e, (pid, 1), "q w\n");
    }
    assert_eq!(e.cache_len(), keys_help::engine::CACHE_MAX);
}
