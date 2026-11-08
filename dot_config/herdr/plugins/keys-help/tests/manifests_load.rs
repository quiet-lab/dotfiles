//! Задача 6.4: разбор манифестов `manifests/`, пропуск ошибочного, `kh-fake` без правки ядра;
//! разрешение контекста по манифестам (порядок «манифест → извлекатель → неизвестная»).

mod common;

use common::*;
use keys_help::channel::{parse_record, Record};
use keys_help::context::{self, Facts, Proc, Resolved};
use keys_help::engine::Engine;
use keys_help::manifest;

const FIRST_QUEUE: [&str; 6] = ["ble", "fzf", "atuin", "tv", "yazi", "nvim"];

#[test]
fn all_shipped_manifests_parse_without_messages() {
    let (ms, errors) = manifest::load_dirs(&[root().join("manifests")]);
    assert!(errors.is_empty(), "сообщения: {errors:?}");
    let stems: Vec<&str> = ms.iter().map(|m| m.stem.as_str()).collect();
    for want in FIRST_QUEUE.iter().chain(["generic"].iter()) {
        assert!(stems.contains(want), "нет манифеста {want}: {stems:?}");
    }
    // Каждый файл каталога разобран отдельно (а не пропущен).
    let files = std::fs::read_dir(root().join("manifests"))
        .unwrap()
        .flatten()
        .filter(|e| e.path().extension().is_some_and(|x| x == "toml"))
        .count();
    assert_eq!(files, ms.len());
}

#[test]
fn shipped_manifests_have_unique_programs_and_labels() {
    let (ms, _) = manifest::load_dirs(&[root().join("manifests")]);
    let mut programs: Vec<&str> = ms.iter().map(|m| m.program.as_str()).collect();
    programs.sort();
    let n = programs.len();
    programs.dedup();
    assert_eq!(programs.len(), n, "повтор program");
    for m in &ms {
        let want = if m.detect.fallback { m.stem.clone() } else { format!("manifest:{}.toml", m.stem) };
        assert_eq!(m.source_label(), want);
    }
    // Универсальный — единственный с fallback и самым низким приоритетом.
    let fb: Vec<_> = ms.iter().filter(|m| m.detect.fallback).collect();
    assert_eq!(fb.len(), 1);
    assert_eq!(fb[0].stem, "generic");
    assert!(ms.iter().filter(|m| !m.detect.fallback).all(|m| m.priority > fb[0].priority));
}

#[test]
fn broken_manifest_is_skipped_with_message_others_work() {
    let d = tmpdir("mf-broken");
    std::fs::copy(root().join("manifests/tv.toml"), d.join("tv.toml")).unwrap();
    std::fs::write(d.join("bad.toml"), "program = \"bad\"\n[[source]\nkind = ").unwrap();
    std::fs::write(d.join("noprog.toml"), "priority = 1\n").unwrap();
    std::fs::write(d.join("badkind.toml"), "program = \"x\"\n[[source]]\nkind = \"nope\"\n").unwrap();
    std::fs::write(d.join("badre.toml"), "program = \"y\"\n[[source]]\nkind = \"regex\"\nregex = \"(\"\n").unwrap();
    std::fs::write(d.join("readme.txt"), "не манифест").unwrap();
    let (ms, errors) = manifest::load_dirs(std::slice::from_ref(&d));
    assert_eq!(ms.len(), 1);
    assert_eq!(ms[0].program, "tv");
    assert_eq!(errors.len(), 4, "{errors:#?}");
    for name in ["bad.toml", "noprog.toml", "badkind.toml", "badre.toml"] {
        assert!(errors.iter().any(|e| e.contains(name)), "нет сообщения о {name}: {errors:?}");
    }
    // Через Engine: те же сообщения доступны вызывающему, остальные манифесты действуют.
    let e = Engine::load(&[d]);
    assert_eq!(e.manifests.len(), 1);
    assert_eq!(e.errors.len(), 4);
}

#[test]
fn unknown_fields_are_reported_not_fatal() {
    let d = tmpdir("mf-unknown-field");
    std::fs::write(d.join("a.toml"), "program = \"a\"\ntypo_field = 1\n[detect]\nprocess = [\"a\"]\n").unwrap();
    let (ms, errors) = manifest::load_dirs(&[d]);
    assert_eq!(ms.len(), 1, "манифест с опечаткой действует");
    assert!(errors.iter().any(|e| e.contains("typo_field")), "{errors:?}");
}

#[test]
fn missing_dir_is_ignored() {
    let (ms, errors) = manifest::load_dirs(&[tmpdir("mf-x").join("нет")]);
    assert!(ms.is_empty() && errors.is_empty());
}

fn facts<'a>(procs: &'a [Proc], active: Option<&'a Record>, screen: &'a dyn Fn(&str, Option<u32>) -> Option<String>) -> Facts<'a> {
    Facts { active, procs, shell_pid: None, title: "", screen }
}

fn proc(pid: i32, name: &str) -> Proc {
    Proc { pid, name: name.into(), argv0: name.into() }
}

#[test]
fn kh_fake_is_recognised_without_core_changes() {
    let mut e = Engine::load(&[root().join("manifests"), fixtures().join("manifests")]);
    assert!(e.errors.is_empty(), "{:?}", e.errors);
    let procs = [proc(4242, "kh-fake")];
    let no_screen = |_: &str, _: Option<u32>| None;
    let res = match context::resolve(&e.manifests, &facts(&procs, None, &no_screen), "/nonexistent") {
        Resolved::Manifest(r) => *r,
        other => panic!("{other:?}"),
    };
    assert_eq!(res.ctx, "kh-fake.main");
    assert_eq!(res.command, "kh-fake");
    let t = e.build_blocking(&res).entries;
    assert_eq!(keys(&t), vec!["q", "C-r", "C-x C-s"]);
    assert_eq!(find(&t, "q").unwrap().desc, "выйти");
    assert_eq!(find(&t, "q").unwrap().group, "general");
    let save = find(&t, "C-x C-s").unwrap();
    assert_eq!(save.desc_full, "Save the current document to disk.");
    assert!(!save.desc.is_empty() && save.desc.chars().count() <= 32, "{}", save.desc);
    assert!(t.iter().all(|x| x.source == "manifest:kh-fake.toml"));
    // Та же программа по строке контекста (`table kh-fake`).
    let by_ctx = context::from_ctx(&e.manifests, "kh-fake").expect("from_ctx");
    assert_eq!(by_ctx.ctx, "kh-fake.main");
}

#[test]
fn manifest_beats_generic_extractor() {
    let e = Engine::load(&[root().join("manifests")]);
    let no_screen = |_: &str, _: Option<u32>| None;
    let procs = [proc(10, "fzf")];
    match context::resolve(&e.manifests, &facts(&procs, None, &no_screen), "/nonexistent") {
        Resolved::Manifest(r) => assert_eq!(r.ctx, "fzf"),
        other => panic!("{other:?}"),
    }
}

#[test]
fn program_without_manifest_goes_to_generic_then_nothing() {
    let e = Engine::load(&[root().join("manifests")]);
    let no_screen = |_: &str, _: Option<u32>| None;
    let procs = [proc(10, "htop")];
    match context::resolve(&e.manifests, &facts(&procs, None, &no_screen), "/nonexistent") {
        Resolved::Manifest(r) => {
            assert_eq!(r.ctx, "htop.generic");
            assert_eq!(r.command, "htop");
        }
        other => panic!("{other:?}"),
    }
    // Без извлекателя (только манифесты программ) — «ничего» с именем команды.
    let only_programs: Vec<_> = e.manifests.iter().filter(|m| !m.detect.fallback).cloned().collect();
    match context::resolve(&only_programs, &facts(&procs, None, &no_screen), "/nonexistent") {
        Resolved::Nothing(Some(c)) => assert_eq!(c, "htop"),
        other => panic!("{other:?}"),
    }
    match context::resolve(&only_programs, &facts(&[], None, &no_screen), "/nonexistent") {
        Resolved::Nothing(None) => {}
        other => panic!("{other:?}"),
    }
}

fn rec(json: &str) -> Record {
    parse_record(json).unwrap_or_else(|| panic!("запись не разобрана: {json}"))
}

#[test]
fn provider_records_choose_context() {
    let e = Engine::load(&[root().join("manifests")]);
    let no_screen = |_: &str, _: Option<u32>| None;
    let ble = rec(r#"{"v":1,"program":"ble","mode":"vi_nmap","pid":77,"state":"active"}"#);
    let procs = [proc(77, "bash")];
    match context::resolve(&e.manifests, &facts(&procs, Some(&ble), &no_screen), "/x") {
        Resolved::Manifest(r) => assert_eq!(r.ctx, "ble.vi_nmap"),
        other => panic!("{other:?}"),
    }
    // exec: оболочка запустила fzf — контекст fzf.
    let exec = rec(r#"{"v":1,"program":"ble","mode":"vi_imap","pid":77,"state":"exec","command":"fzf --height 40%"}"#);
    match context::resolve(&e.manifests, &facts(&[], Some(&exec), &no_screen), "/x") {
        Resolved::Manifest(r) => assert_eq!(r.ctx, "fzf"),
        other => panic!("{other:?}"),
    }
    // widget: привязка запускает __fzf_* — тоже fzf.
    let widget = rec(r#"{"v":1,"program":"ble","mode":"vi_imap","pid":77,"state":"widget","command":"fzf-file-widget"}"#);
    match context::resolve(&e.manifests, &facts(&[], Some(&widget), &no_screen), "/x") {
        Resolved::Manifest(r) => assert_eq!(r.ctx, "fzf"),
        other => panic!("{other:?}"),
    }
    // Команда tv из строки.
    let tv = rec(r#"{"v":1,"program":"ble","mode":"vi_imap","pid":77,"state":"exec","command":"tv"}"#);
    match context::resolve(&e.manifests, &facts(&[], Some(&tv), &no_screen), "/x") {
        Resolved::Manifest(r) => assert_eq!(r.ctx, "tv"),
        other => panic!("{other:?}"),
    }
    // Запись nvim с режимом.
    let nvim = rec(r#"{"v":1,"program":"nvim","mode":"insert","pid":78,"state":"active","server":"/tmp/s"}"#);
    let procs = [proc(78, "nvim")];
    match context::resolve(&e.manifests, &facts(&procs, Some(&nvim), &no_screen), "/x") {
        Resolved::Manifest(r) => {
            assert_eq!(r.ctx, "nvim.insert");
            assert_eq!(r.record.as_ref().and_then(|x| x.server.as_deref()), Some("/tmp/s"));
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn yazi_layer_renamed_manager_and_atuin_mode_from_config() {
    let e = Engine::load(&[root().join("manifests")]);
    let no_screen = |_: &str, _: Option<u32>| None;
    let yazi = rec(r#"{"v":1,"program":"yazi","mode":"mgr","pid":5,"state":"active"}"#);
    match context::resolve(&e.manifests, &facts(&[proc(5, "yazi")], Some(&yazi), &no_screen), "/x") {
        Resolved::Manifest(r) => {
            assert_eq!(r.ctx, "yazi.manager");
            assert_eq!(r.mode_native, "mgr");
        }
        other => panic!("{other:?}"),
    }
    // atuin: keymap_mode не задан — search; vim-normal — normal.
    let home = tmpdir("atuin-home");
    let procs = [proc(9, "atuin")];
    match context::resolve(&e.manifests, &facts(&procs, None, &no_screen), home.to_str().unwrap()) {
        Resolved::Manifest(r) => assert_eq!(r.ctx, "atuin.search"),
        other => panic!("{other:?}"),
    }
    let cfg = home.join(".config/atuin");
    std::fs::create_dir_all(&cfg).unwrap();
    std::fs::write(cfg.join("config.toml"), "keymap_mode = \"vim-normal\"\n").unwrap();
    match context::resolve(&e.manifests, &facts(&procs, None, &no_screen), home.to_str().unwrap()) {
        Resolved::Manifest(r) => assert_eq!(r.ctx, "atuin.normal"),
        other => panic!("{other:?}"),
    }
}
