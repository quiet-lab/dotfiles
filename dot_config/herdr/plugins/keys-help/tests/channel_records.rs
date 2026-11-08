//! Задача 6.6: канал записей поставщиков — порядок записей, стек bash → yazi → nvim,
//! удаление записи умершего процесса по pidfd (тестовые процессы с `HERDR_PANE_ID`
//! из временного каталога).

mod common;

use std::os::fd::AsRawFd;
use std::path::Path;
use std::process::{Child, Command, Stdio};

use keys_help::channel::{self, parse_record, Records};

fn write(dir: &Path, program: &str, pid: i32, mode: &str, state: &str) {
    std::fs::create_dir_all(dir).unwrap();
    let json =
        format!(r#"{{"v":1,"program":"{program}","mode":"{mode}","pid":{pid},"state":"{state}"}}"#);
    // Целиком одним write: временный файл и rename, как делает поставщик.
    let tmp = dir.join(format!(".{program}-{pid}.tmp"));
    std::fs::write(&tmp, json).unwrap();
    std::fs::rename(&tmp, dir.join(format!("{program}-{pid}.json"))).unwrap();
}

/// Тестовый процесс, живущий до закрытия stdin.
fn sleeper(pane_dir: &Path, pane_id: &str) -> Child {
    Command::new("cat")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .env("HERDR_PANE_ID", pane_id)
        .env("XDG_RUNTIME_DIR", pane_dir)
        .spawn()
        .expect("cat")
}

/// Ожидание события выхода процесса через pidfd (poll без срока).
fn wait_pidfd(fd: &std::os::fd::OwnedFd) {
    let mut p = libc::pollfd {
        fd: fd.as_raw_fd(),
        events: libc::POLLIN,
        revents: 0,
    };
    loop {
        // SAFETY: poll по одному корректному pollfd, срок -1 — ожидание события.
        let r = unsafe { libc::poll(&mut p, 1, -1) };
        if r > 0 {
            assert!(p.revents & libc::POLLIN != 0);
            return;
        }
    }
}

#[test]
fn parse_record_fields_and_garbage() {
    let r = parse_record(
        r#"{"v":1,"program":"nvim","mode":"insert","pid":12,"state":"active","server":"/s","env":{"A":"1"},"command":null,"table":"/t"}"#,
    )
    .expect("record");
    assert_eq!(
        (
            r.program.as_str(),
            r.mode.as_deref(),
            r.pid,
            r.state.as_str()
        ),
        ("nvim", Some("insert"), 12, "active")
    );
    assert_eq!(r.server.as_deref(), Some("/s"));
    assert_eq!(r.table.as_deref(), Some("/t"));
    assert_eq!(r.env["A"], "1");
    let f = r.fields();
    assert_eq!(f.get("server").map(String::as_str), Some("/s"));
    // Mode может быть null.
    let n =
        parse_record(r#"{"v":1,"program":"fzf","mode":null,"pid":1,"state":"active"}"#).unwrap();
    assert_eq!(n.mode, None);
    // Неразобранный JSON пропускается.
    assert!(parse_record("{\"v\":1,\"prog").is_none());
    assert!(parse_record("").is_none());
    assert!(parse_record("[]").is_none());
}

#[test]
fn active_is_last_changed_record_of_live_process() {
    let d = common::tmpdir("ch-order");
    let me = std::process::id() as i32;
    write(&d, "ble", me, "vi_imap", "active");
    let mut rs = Records::scan(&d);
    assert_eq!(rs.active(|_| true).map(|r| r.program.as_str()), Some("ble"));
    // Порядок по событиям: новая запись последняя.
    write(&d, "yazi", me + 1, "mgr", "active");
    let r = parse_record(
        &std::fs::read_to_string(d.join("yazi-".to_string() + &(me + 1).to_string() + ".json"))
            .unwrap(),
    )
    .unwrap();
    rs.put(format!("yazi-{}.json", me + 1), r);
    assert_eq!(
        rs.active(|_| true).map(|r| r.program.as_str()),
        Some("yazi")
    );
    // Изменение прежней записи делает её последней.
    let ble =
        parse_record(&std::fs::read_to_string(d.join(format!("ble-{me}.json"))).unwrap()).unwrap();
    rs.put(format!("ble-{me}.json"), ble);
    assert_eq!(rs.active(|_| true).map(|r| r.program.as_str()), Some("ble"));
    assert_eq!(
        rs.slots.len(),
        2,
        "повторная запись заменяет, а не дублирует"
    );
    // Запись мёртвого процесса не активна.
    assert_eq!(
        rs.active(|p| p == me + 1).map(|r| r.program.as_str()),
        Some("yazi")
    );
    assert!(rs.active(|_| false).is_none());
    assert_eq!(rs.latest_of("yazi").map(|r| r.pid), Some(me + 1));
}

#[test]
fn scan_orders_by_mtime() {
    let d = common::tmpdir("ch-scan");
    write(&d, "ble", 1, "vi_imap", "active");
    // Записи разной давности: mtime первой отодвигается назад.
    let old = std::fs::File::options()
        .write(true)
        .open(d.join("ble-1.json"))
        .unwrap();
    old.set_modified(std::time::SystemTime::now() - std::time::Duration::from_secs(100))
        .unwrap();
    write(&d, "yazi", 2, "mgr", "active");
    write(&d, "nvim", 3, "normal", "active");
    let f = std::fs::File::options()
        .write(true)
        .open(d.join("nvim-3.json"))
        .unwrap();
    f.set_modified(std::time::SystemTime::now() + std::time::Duration::from_secs(100))
        .unwrap();
    // Побочные файлы не записи.
    std::fs::write(d.join("note.txt"), "x").unwrap();
    std::fs::write(d.join("broken-9.json"), "{").unwrap();
    let rs = Records::scan(&d);
    let order: Vec<&str> = rs.slots.iter().map(|s| s.record.program.as_str()).collect();
    assert_eq!(order, vec!["ble", "yazi", "nvim"]);
}

/// Стек bash → yazi → nvim: активной становится последняя запись, при выходе nvim
/// (удаление записи) — снова yazi, после выхода yazi оболочка пишет PRECMD-запись.
#[test]
fn stack_bash_yazi_nvim() {
    let d = common::tmpdir("ch-stack");
    let pane = d.join("panes/%1-1");
    let (bash, yazi, nvim) = (100, 200, 300);
    let mut rs = Records::default();
    let name = |p: &str, pid: i32| format!("{p}-{pid}.json");
    let put = |rs: &mut Records, p: &str, pid: i32, mode: &str, state: &str| {
        write(&pane, p, pid, mode, state);
        let r = parse_record(&std::fs::read_to_string(pane.join(name(p, pid))).unwrap()).unwrap();
        rs.put(name(p, pid), r);
    };
    let prog = |rs: &Records| {
        rs.active(|_| true)
            .map(|r| (r.program.clone(), r.mode.clone(), r.state.clone()))
    };

    put(&mut rs, "ble", bash, "vi_imap", "active");
    assert_eq!(prog(&rs).unwrap().0, "ble");
    put(&mut rs, "ble", bash, "vi_imap", "exec"); // оболочка запустила yazi
    put(&mut rs, "yazi", yazi, "mgr", "active");
    assert_eq!(prog(&rs).unwrap().0, "yazi");
    put(&mut rs, "nvim", nvim, "normal", "active");
    assert_eq!(prog(&rs).unwrap().0, "nvim");
    put(&mut rs, "nvim", nvim, "insert", "active");
    assert_eq!(
        prog(&rs),
        Some(("nvim".into(), Some("insert".into()), "active".into()))
    );
    // nvim вышел и удалил запись — снова yazi.
    std::fs::remove_file(pane.join(name("nvim", nvim))).unwrap();
    rs.remove(&name("nvim", nvim));
    assert_eq!(prog(&rs).unwrap().0, "yazi");
    // yazi вышел — запись удалена; оболочка пишет PRECMD-запись и она активна.
    rs.remove(&name("yazi", yazi));
    assert_eq!(prog(&rs).unwrap().2, "exec");
    put(&mut rs, "ble", bash, "vi_imap", "active");
    assert_eq!(
        prog(&rs),
        Some(("ble".into(), Some("vi_imap".into()), "active".into()))
    );
    assert_eq!(rs.slots.len(), 1);
}

#[test]
fn killed_process_record_removed_by_pidfd() {
    let d = common::tmpdir("ch-kill");
    let pane = d.join("panes/%2-1");
    let mut shell = sleeper(&d, "%2-1");
    let mut nvim = sleeper(&d, "%2-1");
    let (sp, np) = (shell.id() as i32, nvim.id() as i32);
    write(&pane, "ble", sp, "vi_imap", "active");
    write(&pane, "nvim", np, "normal", "active");
    let mut rs = Records::scan(&pane);
    assert_eq!(
        rs.active(channel::alive).map(|r| r.program.as_str()),
        Some("nvim")
    );

    // pidfd процесса записи; завершение сигналом SIGKILL приходит событием pidfd.
    let fd = channel::pidfd_open(np).expect("pidfd_open");
    // SAFETY: сигнал собственному дочернему процессу по известному pid.
    unsafe { libc::kill(np, libc::SIGKILL) };
    wait_pidfd(&fd);
    let removed = rs.remove_pid(np);
    assert_eq!(removed, vec![format!("nvim-{np}.json")]);
    let _ = nvim.wait();
    // Запись упавшего процесса осталась в каталоге (процесс не удалил её): её снимает
    // просмотрщик — здесь проверяем состояние набора и повторное сканирование с проверкой жизни.
    assert_eq!(
        rs.active(channel::alive).map(|r| r.program.as_str()),
        Some("ble")
    );
    let rescanned = Records::scan(&pane);
    assert_eq!(
        rescanned.active(channel::alive).map(|r| r.program.as_str()),
        Some("ble")
    );
    // Неизвестный pid ничего не удаляет.
    assert!(rs.remove_pid(1).is_empty());

    drop(shell.stdin.take());
    let _ = shell.wait();
}

#[test]
fn pidfd_of_dead_process_is_none_and_alive_false() {
    let d = common::tmpdir("ch-dead");
    let mut c = sleeper(&d, "%3-1");
    let pid = c.id() as i32;
    assert!(channel::alive(pid));
    drop(c.stdin.take());
    c.wait().unwrap();
    assert!(!channel::alive(pid));
    assert!(channel::pidfd_open(pid).is_none());
    assert!(!channel::alive(0));
    assert!(!channel::alive(-5));
}

#[test]
fn pidfd_fires_on_normal_exit() {
    let d = common::tmpdir("ch-exit");
    let mut c = sleeper(&d, "%4-1");
    let pid = c.id() as i32;
    let fd = channel::pidfd_open(pid).unwrap();
    drop(c.stdin.take()); // cat завершается
    wait_pidfd(&fd);
    c.wait().unwrap();
}
