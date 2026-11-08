//! Задача 6.5: извлечение таблиц по манифестам — фикстуры `ble-bind -P`, `keymap.toml` yazi,
//! `[keybindings]` tv, `--bind` fzf, раздел `KEY BINDINGS` man, нормализация клавиш.

mod common;

use std::collections::BTreeMap;

use common::*;
use keys_help::entry::Entry;
use keys_help::extract::{Outputs, Subst};
use keys_help::keys;

fn fx(rel: &str) -> String {
    std::fs::read_to_string(fixtures().join(rel)).unwrap_or_else(|e| panic!("{rel}: {e}"))
}

fn home_with(name: &str, files: &[(&str, &str)]) -> std::path::PathBuf {
    let h = tmpdir(name);
    for (rel, fixture) in files {
        let p = h.join(rel);
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::copy(fixtures().join(fixture), &p).unwrap();
    }
    h
}

// ---- нормализация ----

#[test]
fn normalization_spec_scenario() {
    assert_eq!(keys::normalize("<C-x>"), "C-x");
    assert_eq!(keys::normalize("ctrl-alt-t"), "C-M-t");
    assert_eq!(keys::normalize("<Esc>"), "ESC");
}

#[test]
fn normalization_forms() {
    for (raw, want) in [
        ("<C-x><C-k>", "C-x C-k"),
        ("<A-x>", "M-x"),
        ("alt-shift-up", "M-S-up"),
        ("shift-alt-ctrl-a", "C-M-S-a"),
        ("enter", "RET"),
        ("<Tab>", "TAB"),
        ("<Space>", "SP"),
        (" ", "SP"),
        ("<Up>", "up"),
        ("Ctrl+X", "C-x"),
        ("^X", "C-x"),
        ("C-x C-k", "C-x C-k"),
        ("ctrl+alt+shift+slash", "C-M-S-/"),
    ] {
        assert_eq!(keys::normalize(raw), want, "{raw}");
    }
}

// ---- ble.sh: дамп ble-bind -P ----

fn ble_table(keymap: &str) -> Vec<Entry> {
    let m = manifest_named("ble");
    let mut sub = subst(keymap, keymap, &tmpdir("ble-home"));
    sub.record.insert(
        "table".into(),
        fixtures()
            .join(format!("ble/{keymap}.bind"))
            .display()
            .to_string(),
    );
    table(&m, &sub, &Outputs::new())
}

#[test]
fn ble_vi_imap_user_bindings_and_origins() {
    let t = ble_table("vi_imap");
    for (key, origin) in [
        ("M-f", "fzf"),
        ("M-h", "fzf"),
        ("M-d", "fzf"),
        ("M-r", "atuin"),
        ("M-up", "atuin"),
        ("M-t", "tv"),
        ("C-M-t", "tv"),
    ] {
        let e = find(&t, key).unwrap_or_else(|| panic!("нет {key}"));
        assert_eq!(e.origin, origin, "{key}");
    }
    // Служебных __…__ нет.
    assert!(t
        .iter()
        .all(|e| !e.action.contains("__default__") && !e.action.contains("__attach__")));
    assert!(t.iter().all(|e| !e.key.starts_with("__")));
}

#[test]
fn ble_entry_fields() {
    let t = ble_table("vi_imap");
    let f = find(&t, "M-f").unwrap();
    assert_eq!(f.action, "fzf-file-widget");
    assert_eq!(f.source, "manifest:ble.toml");
    assert_eq!(f.raw, "ble-bind -m 'vi_imap' -x M-f fzf-file-widget");
    // Короткое описание из манифеста, а не имя виджета.
    let r = find(&t, "C-r").unwrap();
    assert_eq!(r.action, "history-isearch-backward");
    assert!(!r.desc.is_empty() && r.desc != r.action, "{r:?}");
    assert_eq!(r.origin, "ble");
    // Последовательности клавиш через пробел.
    assert!(find(&t, "C-x C-r").is_some());
}

#[test]
fn ble_origin_readline_for_vi_rlfunc() {
    // vi-rlfunc/… — readline.
    let t = ble_table("vi_nmap");
    let rl: Vec<&Entry> = t
        .iter()
        .filter(|e| e.action.starts_with("vi-rlfunc/"))
        .collect();
    if rl.is_empty() {
        // В снятом дампе нет таких привязок — проверим на однострочном дампе.
        let d = tmpdir("ble-rl");
        let p = d.join("x.bind");
        std::fs::write(&p, "ble-bind -m 'vi_nmap' -f C-t vi-rlfunc/transpose-chars\nble-bind -m 'vi_nmap' -c M-z 'echo hi'\nble-bind -m 'vi_nmap' -f C-a beginning-of-line\n").unwrap();
        let m = manifest_named("ble");
        let mut sub = subst("vi_nmap", "vi_nmap", &d);
        sub.record.insert("table".into(), p.display().to_string());
        let t = table(&m, &sub, &Outputs::new());
        assert_eq!(find(&t, "C-t").unwrap().origin, "readline");
        assert_eq!(find(&t, "M-z").unwrap().origin, "user");
        assert_eq!(find(&t, "C-a").unwrap().origin, "ble");
    } else {
        assert!(rl.iter().all(|e| e.origin == "readline"));
    }
}

/// `ac_enter` — служебный код автодополнения ble.sh, а не клавиша: в таблицах его нет,
/// и ни одна клавиша не распадается на отдельные символы с подчёркиванием.
#[test]
fn ble_ac_enter_not_shown() {
    for km in ["vi_imap", "vi_nmap", "vi_cmap", "emacs", "auto_complete"] {
        let t = ble_table(km);
        assert!(t.iter().all(|e| e.key != "ac_enter"), "{km}");
        assert!(t.iter().all(|e| !e.key.contains(" _ ")), "{km}");
    }
}

#[test]
fn ble_all_keymaps_parse_nonempty() {
    for km in [
        "vi_imap",
        "vi_nmap",
        "vi_xmap",
        "vi_smap",
        "vi_omap",
        "vi_cmap",
        "isearch",
        "nsearch",
        "menu_complete",
        "auto_complete",
        "emacs",
    ] {
        let t = ble_table(km);
        assert!(!t.is_empty(), "{km}: пустая таблица");
        assert!(t.iter().all(|e| !e.key.is_empty()), "{km}");
        // Ввод цифр и символов не показывается.
        assert!(t.iter().all(|e| e.action != "self-insert"), "{km}");
    }
}

#[test]
fn ble_dump_with_quoted_key_and_macros() {
    let d = tmpdir("ble-q");
    let p = d.join("q.bind");
    std::fs::write(
        &p,
        "ble-bind -m 'vi_imap' -f 'C-x C-r' dabbrev-expand\n\
         ble-bind -m 'vi_imap' -f __default__ vi_imap/__default__\n\
         ble-bind -m 'vi_imap' -s '?' '\\C-x\\C-_A1\\a'\n\
         ble-bind -m 'vi_imap' -f C-j accept-line\n",
    )
    .unwrap();
    let m = manifest_named("ble");
    let mut sub = subst("vi_imap", "vi_imap", &d);
    sub.record.insert("table".into(), p.display().to_string());
    let t = table(&m, &sub, &Outputs::new());
    assert_eq!(keys(&t), vec!["C-x C-r", "C-j"]);
}

// ---- yazi ----

fn yazi_table(home: &std::path::Path, native: &str, name: &str) -> Vec<Entry> {
    table(
        &manifest_named("yazi"),
        &subst(native, name, home),
        &Outputs::new(),
    )
}

#[test]
fn yazi_defaults_without_user_keymap() {
    let h = tmpdir("yazi-none");
    let t = yazi_table(&h, "mgr", "manager");
    let q = find(&t, "q").expect("q");
    assert_eq!(q.origin, "yazi");
    assert_eq!(q.action, "quit");
    assert!(!q.desc_full.is_empty(), "полный desc исходников");
    assert!(find(&t, "j").is_some() && find(&t, "k").is_some());
}

#[test]
fn yazi_prepend_and_append_keymap_override_defaults() {
    let h = home_with(
        "yazi-user",
        &[(".config/yazi/keymap.toml", "yazi/keymap.toml")],
    );
    let t = yazi_table(&h, "mgr", "manager");
    // prepend_keymap побеждает умолчание.
    let q = find(&t, "q").unwrap();
    assert_eq!(q.action, "close");
    assert_eq!(q.origin, "user");
    assert_eq!(q.desc_full, "My own quit that closes tab");
    // Последовательность из двух клавиш.
    let gz = find(&t, "g z").expect("g z");
    assert_eq!(gz.action, "cd ~/work");
    assert_eq!(gz.origin, "user");
    assert_eq!(find(&t, "C-e").unwrap().action, "shell --block");
    // append_keymap добавляет.
    assert_eq!(find(&t, "f9").map(|e| e.origin.as_str()), Some("user"));
    // Умолчания остаются там, где не переопределены.
    assert_eq!(find(&t, "j").unwrap().origin, "yazi");
    // Нет повторов клавиш.
    let mut ks = keys(&t);
    ks.sort();
    let n = ks.len();
    ks.dedup();
    assert_eq!(ks.len(), n, "повторы клавиш");
}

#[test]
fn yazi_user_keymap_applies_only_to_its_layer() {
    let h = home_with(
        "yazi-layer",
        &[(".config/yazi/keymap.toml", "yazi/keymap.toml")],
    );
    let t = yazi_table(&h, "input", "input");
    assert!(find(&t, "g z").is_none());
    assert!(!t.is_empty());
}

#[test]
fn yazi_keymap_replaces_defaults() {
    let h = tmpdir("yazi-replace");
    let p = h.join(".config/yazi/keymap.toml");
    std::fs::create_dir_all(p.parent().unwrap()).unwrap();
    std::fs::write(
        &p,
        "[mgr]\nkeymap = [\n { on = \"x\", run = \"quit\", desc = \"Only key\" },\n]\n",
    )
    .unwrap();
    let t = yazi_table(&h, "mgr", "manager");
    assert_eq!(keys(&t), vec!["x"]);
}

// ---- television ----

#[test]
fn tv_table_matches_keybindings_section() {
    let h = home_with(
        "tv-home",
        &[(".config/television/config.toml", "tv/config.toml")],
    );
    let t = table(
        &manifest_named("tv"),
        &subst("tv", "tv", &h),
        &Outputs::new(),
    );
    let got: BTreeMap<&str, &str> = t
        .iter()
        .map(|e| (e.key.as_str(), e.action.as_str()))
        .collect();
    let want: BTreeMap<&str, &str> = [
        ("ESC", "quit"),
        ("C-c", "quit"),
        ("down", "select_next_entry"),
        ("C-n", "select_next_entry"),
        ("C-o", "toggle_preview"),
        ("RET", "confirm_selection"),
    ]
    .into_iter()
    .collect();
    assert_eq!(got, want);
    assert!(t.iter().all(|e| e.origin == "tv"));
    // [ui] в таблицу не попадает.
    assert!(find(&t, "theme").is_none());
}

#[test]
fn tv_without_config_is_empty_not_error() {
    let t = table(
        &manifest_named("tv"),
        &subst("tv", "tv", &tmpdir("tv-none")),
        &Outputs::new(),
    );
    assert!(t.is_empty());
}

// ---- fzf ----

fn fzf_sub(home: &std::path::Path, opts: Option<&str>) -> Subst {
    let mut s = subst("fzf", "fzf", home);
    if let Some(o) = opts {
        s.env.insert("FZF_DEFAULT_OPTS".into(), o.to_string());
    }
    s
}

fn fzf_outputs() -> Outputs {
    outputs(&[(&["man", "-P", "cat", "fzf"], &fx("man/fzf-actions.txt"))])
}

#[test]
fn fzf_defaults_with_bind_override() {
    let h = tmpdir("fzf-h");
    let t = table(
        &manifest_named("fzf"),
        &fzf_sub(&h, Some("--bind ctrl-y:accept")),
        &fzf_outputs(),
    );
    let y = find(&t, "C-y").expect("C-y");
    assert_eq!(y.action, "accept");
    assert_eq!(y.origin, "user");
    // Умолчания из man на месте.
    let c = find(&t, "C-c").unwrap();
    assert_eq!(c.action, "abort");
    assert_eq!(c.origin, "fzf");
    assert_eq!(find(&t, "RET").unwrap().action, "accept");
}

#[test]
fn fzf_bind_overrides_default_key() {
    let h = tmpdir("fzf-ov");
    let t = table(
        &manifest_named("fzf"),
        &fzf_sub(&h, Some("--bind='ctrl-c:accept,ctrl-x:abort' --color=dark")),
        &fzf_outputs(),
    );
    assert_eq!(find(&t, "C-c").unwrap().action, "accept");
    assert_eq!(find(&t, "C-c").unwrap().origin, "user");
    assert_eq!(find(&t, "C-x").unwrap().action, "abort");
    // Остальные клавиши abort остались.
    assert_eq!(find(&t, "C-g").unwrap().action, "abort");
}

#[test]
fn fzf_without_env_has_only_defaults() {
    let h = tmpdir("fzf-noenv");
    let t = table(&manifest_named("fzf"), &fzf_sub(&h, None), &fzf_outputs());
    assert!(t.iter().all(|e| e.origin == "fzf"));
}

#[test]
fn fzf_keys_after_fourth_are_not_lost() {
    let h = tmpdir("fzf-many");
    let t = table(&manifest_named("fzf"), &fzf_sub(&h, None), &fzf_outputs());
    // abort: четыре клавиши.
    for k in ["C-c", "C-g", "C-q", "ESC"] {
        assert_eq!(find(&t, k).map(|e| e.action.as_str()), Some("abort"), "{k}");
    }
    // unix-line-discard: ctrl-u alt-u alt-i alt-o alt-p alt-q alt-r — семь клавиш.
    for k in ["C-u", "M-u", "M-i", "M-o", "M-p", "M-q", "M-r"] {
        assert_eq!(
            find(&t, k).map(|e| e.action.as_str()),
            Some("unix-line-discard"),
            "{k}"
        );
    }
    // Три клавиши и две.
    for k in ["C-h", "C-BS", "BS"] {
        assert_eq!(
            find(&t, k).map(|e| e.action.as_str()),
            Some("backward-delete-char"),
            "{k}"
        );
    }
    // Строки с описанием в скобках без клавиш и продолжения строк не дают записей.
    assert!(t.iter().all(|e| !e.action.is_empty()));
    assert!(find(&t, "toggle-preview").is_none());
    assert!(t
        .iter()
        .all(|e| e.action != "accept-non-empty" && e.action != "toggle-preview"));
}

// ---- универсальный извлекатель: man ----

fn generic_table(cmd: &str, man: &str, home: &std::path::Path) -> Vec<Entry> {
    let m = manifest_named("generic");
    let mut sub = subst("generic", "generic", home);
    sub.command = cmd.to_string();
    let out = outputs(&[(&["man", "-P", "cat", cmd], man)]);
    table(&m, &sub, &out)
}

#[test]
fn generic_man_key_bindings_section() {
    let t = generic_table("kh-man", &fx("man/kh-man.txt"), &tmpdir("gen-h"));
    assert!(t.iter().all(|e| e.origin == "generic"), "{t:?}");
    let ks = keys(&t);
    for k in ["j", "down", "k", "q", "C-l", "/"] {
        assert!(ks.contains(&k), "нет {k} среди {ks:?}");
    }
    // Спецификация: `q` — сокращение первого предложения, desc_full — исходный текст.
    let q = find(&t, "q").unwrap();
    assert_eq!(q.desc, "quit the program immediately");
    assert_eq!(
        q.desc_full,
        "This will quit the program immediately. Unsaved changes are lost."
    );
    // Группа — подзаголовок раздела.
    assert_eq!(q.group, "general");
    assert_eq!(find(&t, "k").unwrap().group, "navigation");
    // Источник — извлекатель.
    assert!(q.source.contains("generic"), "{}", q.source);
    // Длинное описание сокращено до 32 символов с многоточием.
    let slash = find(&t, "/").unwrap();
    assert!(
        slash.desc.chars().count() <= 32 && slash.desc.ends_with('…'),
        "{}",
        slash.desc
    );
    assert!(slash.desc_full.contains("current logical line"));
}

/// Последовательность клавиш из двух слов в справке man (`C-x C-k`) — одна клавиша,
/// регистр описания сохраняется.
#[test]
fn generic_man_key_sequence() {
    let man = "KEY BINDINGS\n       C-x C-k    Kill the buffer (asks first).\n\n       q          Quit now\n";
    let t = generic_table("kh-man", man, &tmpdir("gen-seq"));
    let e = find(&t, "C-x C-k").expect("C-x C-k");
    assert_eq!(e.desc, "Kill the buffer");
}

/// Многосимвольное имя без аккорда (`double-click` из man fzf) остаётся одной клавишей,
/// а не распадается на символы.
#[test]
fn fzf_double_click_name_kept() {
    let h = tmpdir("fzf-dc");
    let t = table(&manifest_named("fzf"), &fzf_sub(&h, None), &fzf_outputs());
    assert_eq!(
        find(&t, "double-click").map(|e| e.action.as_str()),
        Some("accept")
    );
}

#[test]
fn generic_help_when_man_has_no_section() {
    let m = manifest_named("generic");
    let mut sub = subst("generic", "generic", &tmpdir("gen-help"));
    sub.command = "kh-help".into();
    let mut out = outputs(&[(
        &["man", "-P", "cat", "kh-help"],
        "KH-HELP(1)\n\nNAME\n       kh-help - x\n",
    )]);
    out.insert(
        vec!["kh-help".into(), "--help".into()],
        Some("Usage: kh-help\n\nKeys:\n  q    Quit now\n  j    Down one line\n\nOptions:\n  -h   help\n".into()),
    );
    let t = table(&m, &sub, &out);
    assert!(find(&t, "q").is_some() && find(&t, "j").is_some(), "{t:?}");
    assert!(t.iter().all(|e| e.origin == "generic"));
}

#[test]
fn generic_first_nonempty_wins() {
    // man даёт таблицу: --help не запрашивается (Build::Need не возникает).
    let m = manifest_named("generic");
    let mut sub = subst("generic", "generic", &tmpdir("gen-first"));
    sub.command = "kh-man".into();
    let out = outputs(&[(&["man", "-P", "cat", "kh-man"], &fx("man/kh-man.txt"))]);
    assert!(matches!(
        keys_help::extract::build(&m, &sub, &out),
        keys_help::extract::Build::Done(_)
    ));
}

#[test]
fn generic_nothing_found_is_empty() {
    let m = manifest_named("generic");
    let mut sub = subst("generic", "generic", &tmpdir("gen-none"));
    sub.command = "kh-unknown".into();
    let mut out = outputs(&[(&["man", "-P", "cat", "kh-unknown"], "")]);
    out.insert(
        vec!["kh-unknown".into(), "--help".into()],
        Some(String::new()),
    );
    assert!(table(&m, &sub, &out).is_empty());
}

#[test]
fn substitution_rules() {
    let mut s = Subst {
        command: "x".into(),
        mode_native: "mgr".into(),
        mode: "manager".into(),
        ..Default::default()
    };
    s.env.insert("A".into(), "1".into());
    use keys_help::extract::substitute;
    assert_eq!(
        substitute("{command}-{mode}-{mode_name}-{env.A}", &s).as_deref(),
        Some("x-mgr-manager-1")
    );
    assert_eq!(substitute("{env.MISSING}", &s), None);
    assert_eq!(substitute("{record.table}", &s), None);
    assert_eq!(substitute("a{3,4}b", &s).as_deref(), Some("a{3,4}b"));
}

// ---- Neovim: лидер приходит пробелом ----

#[test]
fn nvim_leader_space_is_normalized_to_sp() {
    let m = manifest_named("nvim");
    let mut sub = subst("normal", "normal", &tmpdir("nv-home"));
    sub.record.insert("server".into(), "/tmp/kh.sock".into());
    let dump = r#"[
      {"lhs":" ff","rhs":"<cmd>Telescope find_files<cr>","desc":"Find Files","origin":"lazyvim","group":"lazyvim","source":"/x/keymaps.lua:10"},
      {"lhs":" fb","desc":"Switch buffer using the fuzzy finder for all open buffers","origin":"user","group":"user"},
      {"lhs":"<Plug>(x)","rhs":"y","origin":"nvim"},
      {"lhs":"<C-M-h>","rhs":"<C-w>h","desc":"Window left","origin":"user"},
      {"lhs":"<C-M-р>","rhs":"<C-w>h","desc":"Window left","origin":"user"},
      {"lhs":" аа","rhs":"<cmd>Telescope find_files<cr>","desc":"Find Files","origin":"lazyvim"}
    ]"#;
    let out = outputs(&[(
        &[
            "nvim",
            "--server",
            "/tmp/kh.sock",
            "--remote-expr",
            "luaeval('require(\"keys_help\").dump(\"n\")')",
        ],
        dump,
    )]);
    let t = table(&m, &sub, &out);
    let ff = find(&t, "SP f f").expect("SP f f");
    assert_eq!(ff.desc.to_lowercase(), "find files");
    assert_eq!(ff.origin, "lazyvim");
    assert!(
        ff.raw.contains("Telescope find_files") && ff.raw.contains("keymaps.lua:10"),
        "{}",
        ff.raw
    );
    let fb = find(&t, "SP f b").expect("SP f b");
    assert!(fb.desc.chars().count() <= 32 && fb.desc.ends_with('…'));
    assert!(fb.desc_full.starts_with("Switch buffer"));
    assert!(find(&t, "<Plug>(x)").is_none());
    // Дубли ru-layout с кириллицей в lhs не показываются, латинская привязка остаётся.
    assert!(find(&t, "C-M-h").is_some());
    assert!(
        t.iter().all(|e| !e
            .key
            .chars()
            .any(|c| ('а'..='я').contains(&c.to_lowercase().next().unwrap_or(c)))),
        "кириллица в таблице"
    );
}
