//! Задача 6.13: у каждой показываемой записи манифестов первой очереди короткое описание
//! `desc` не пусто, не совпадает с `action` и не длиннее 32 символов.

mod common;

use common::*;
use keys_help::entry::Entry;
use keys_help::extract::{Outputs, Subst};

fn fx(rel: &str) -> String {
    std::fs::read_to_string(fixtures().join(rel)).unwrap_or_else(|e| panic!("{rel}: {e}"))
}

fn check(what: &str, t: &[Entry]) {
    assert!(!t.is_empty(), "{what}: пустая таблица");
    let mut bad = Vec::new();
    for e in t {
        let n = e.desc.chars().count();
        if e.desc.is_empty() || e.desc == e.action || n > 32 {
            bad.push(format!("{} (action={:?}, desc={:?}, {n})", e.key, e.action, e.desc));
        }
    }
    assert!(bad.is_empty(), "{what}: {} записей с плохим desc:\n{}", bad.len(), bad.join("\n"));
}

#[test]
fn ble_all_keymaps() {
    let m = manifest_named("ble");
    for km in [
        "vi_imap", "vi_nmap", "vi_xmap", "vi_smap", "vi_omap", "vi_cmap", "isearch", "nsearch",
        "menu_complete", "auto_complete", "emacs",
    ] {
        let mut sub = subst(km, km, &tmpdir("d-ble"));
        sub.record.insert("table".into(), fixtures().join(format!("ble/{km}.bind")).display().to_string());
        check(&format!("ble.{km}"), &table(&m, &sub, &Outputs::new()));
    }
}

#[test]
fn fzf_default_and_user_binds() {
    let m = manifest_named("fzf");
    let out = outputs(&[(&["man", "-P", "cat", "fzf"], &fx("man/fzf-full-actions.txt"))]);
    let mut sub: Subst = subst("fzf", "fzf", &tmpdir("d-fzf"));
    sub.env.insert(
        "FZF_DEFAULT_OPTS".into(),
        "--bind ctrl-y:accept,alt-j:down,ctrl-/:toggle-preview".into(),
    );
    check("fzf", &table(&m, &sub, &out));
}

#[test]
fn atuin_all_modes() {
    let m = manifest_named("atuin");
    for mode in ["search", "insert", "normal"] {
        check(&format!("atuin.{mode}"), &table(&m, &subst(mode, mode, &tmpdir("d-atuin")), &Outputs::new()));
    }
}

#[test]
fn tv_snapshot_of_real_keybindings() {
    let h = tmpdir("d-tv");
    let p = h.join(".config/television/config.toml");
    std::fs::create_dir_all(p.parent().unwrap()).unwrap();
    std::fs::copy(fixtures().join("tv/config-full.toml"), &p).unwrap();
    check("tv", &table(&manifest_named("tv"), &subst("", "", &h), &Outputs::new()));
}

#[test]
fn yazi_all_layers() {
    let m = manifest_named("yazi");
    for (native, name) in [
        ("mgr", "manager"),
        ("tasks", "tasks"),
        ("spot", "spot"),
        ("pick", "pick"),
        ("input", "input"),
        ("confirm", "confirm"),
        ("cmp", "cmp"),
        ("help", "help"),
    ] {
        check(&format!("yazi.{name}"), &table(&m, &subst(native, name, &tmpdir("d-yazi")), &Outputs::new()));
    }
}

#[test]
fn nvim_basic_keys_and_dump() {
    let m = manifest_named("nvim");
    let dump = r#"[
      {"lhs":" ff","rhs":"<cmd>Telescope find_files<cr>","desc":"Find Files","origin":"lazyvim","group":"lazyvim","source":"/x/keymaps.lua:10"},
      {"lhs":" fb","desc":"Switch buffer using the fuzzy finder for all open buffers in the session","origin":"user","group":"user"},
      {"lhs":"<Plug>(x)","rhs":"y","origin":"nvim"},
      {"lhs":"gcc","rhs":"<cmd>x<cr>","desc":"Comment line","origin":"nvim","group":"nvim"}
    ]"#;
    for mode in ["normal", "insert", "visual", "select", "cmdline", "replace", "terminal", "operator"] {
        let mut sub = subst(mode, mode, &tmpdir("d-nvim"));
        sub.record.insert("server".into(), "/tmp/kh.sock".into());
        let letter = match mode {
            "normal" => "n",
            "insert" | "replace" => "i",
            "visual" => "x",
            "select" => "s",
            "cmdline" => "c",
            "terminal" => "t",
            _ => "o",
        };
        let argv_tail = format!("luaeval('require(\"keys_help\").dump(\"{letter}\")')");
        let out = outputs(&[(&["nvim", "--server", "/tmp/kh.sock", "--remote-expr", &argv_tail], dump)]);
        let t = table(&m, &sub, &out);
        check(&format!("nvim.{mode}"), &t);
        assert!(find(&t, "<Plug>(x)").is_none(), "{mode}: <Plug> показан");
    }
}
