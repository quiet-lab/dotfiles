//! Общие помощники интеграционных тестов.
#![allow(dead_code)]

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use keys_help::entry::Entry;
use keys_help::extract::{self, Build, Outputs, Subst};
use keys_help::manifest::{self, Manifest};

pub fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

pub fn fixtures() -> PathBuf {
    root().join("tests/fixtures")
}

/// Свой временный каталог теста (изоляция данными).
pub fn tmpdir(name: &str) -> PathBuf {
    static N: AtomicU64 = AtomicU64::new(0);
    let d = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join(format!(
        "{name}-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::SeqCst)
    ));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).expect("tmpdir");
    d
}

/// Манифест плагина по имени файла без расширения.
pub fn manifest_named(stem: &str) -> Manifest {
    let p = root().join("manifests").join(format!("{stem}.toml"));
    let text = std::fs::read_to_string(&p).expect("read manifest");
    manifest::parse(&text, &p).unwrap_or_else(|e| panic!("{stem}: {e}"))
}

pub fn subst(mode_native: &str, mode: &str, home: &Path) -> Subst {
    Subst {
        mode_native: mode_native.to_string(),
        mode: mode.to_string(),
        home: home.display().to_string(),
        ..Default::default()
    }
}

/// Таблица манифеста без запуска команд: нужные выводы заданы в `outputs`.
pub fn table(m: &Manifest, sub: &Subst, outputs: &Outputs) -> Vec<Entry> {
    match extract::build(m, sub, outputs) {
        Build::Done(b) => b.entries,
        Build::Need(argv) => panic!("нужен вывод команды {argv:?}"),
    }
}

pub fn find<'a>(t: &'a [Entry], key: &str) -> Option<&'a Entry> {
    t.iter().find(|e| e.key == key)
}

pub fn keys(t: &[Entry]) -> Vec<&str> {
    t.iter().map(|e| e.key.as_str()).collect()
}

pub fn outputs(items: &[(&[&str], &str)]) -> Outputs {
    let mut o: Outputs = BTreeMap::new().into_iter().collect();
    for (argv, out) in items {
        o.insert(
            argv.iter().map(|s| s.to_string()).collect(),
            Some(out.to_string()),
        );
    }
    o
}
