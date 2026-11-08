//! Запуск команд источников (D6): без оболочки и терминала (`setsid`),
//! stdin `/dev/null`, вывод — во временный файл, ожидание — по pidfd
//! в цикле просмотрщика или `waitpid` для печати таблицы. Сроков нет:
//! процесс завершается сменой контекста или выходом просмотрщика.

use std::os::fd::OwnedFd;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};

/// Запущенная команда.
pub struct Job {
    pub argv: Vec<String>,
    /// Номер задания: по нему цикл просмотрщика отличает готовность
    /// текущего задания от устаревшей (задание заменено в той же итерации).
    pub n: u64,
    pub pid: i32,
    pub pidfd: OwnedFd,
    out: PathBuf,
    child: std::process::Child,
}

fn out_path(n: u64) -> PathBuf {
    crate::paths::runtime_dir()
        .join("tmp")
        .join(format!("{}-{n}.out", std::process::id()))
}

/// Переменные окружения, по которым программа находит графическую сессию,
/// композитор и шину сессии: проба `--help` запускается без них, чтобы
/// программа, не знающая `--help`, не открыла окно и не выполнила действие
/// в сессии.
pub const PROBE_ENV_REMOVE: &[&str] = &[
    "DISPLAY",
    "WAYLAND_DISPLAY",
    "WAYLAND_SOCKET",
    "HYPRLAND_INSTANCE_SIGNATURE",
    "DBUS_SESSION_BUS_ADDRESS",
    "SUDO_ASKPASS",
    "SWAYSOCK",
    "XAUTHORITY",
];

/// Проба справки: аргумент `--help` у команды (параметры первого слова
/// строки ввода, источник `{command} --help` универсального извлекателя).
pub fn is_help_probe(argv: &[String]) -> bool {
    argv.iter().skip(1).any(|a| a == "--help")
}

/// Путь исполняемого файла: как есть с `/`, иначе первый файл по `PATH`.
pub fn resolve(cmd: &str) -> Option<PathBuf> {
    if cmd.contains('/') {
        return Some(PathBuf::from(cmd));
    }
    let path = std::env::var("PATH").unwrap_or_default();
    path.split(':')
        .filter(|d| !d.is_empty())
        .map(|d| std::path::Path::new(d).join(cmd))
        .find(|p| p.is_file())
}

/// Исполняемый файл ELF (заголовок `\x7fELF`, по ссылкам): сценарии
/// с `#!` пробу справки не проходят — сценарий, не разбирающий `--help`,
/// выполнил бы своё действие.
pub fn is_elf(path: &std::path::Path) -> bool {
    use std::io::Read;
    let mut head = [0u8; 4];
    std::fs::File::open(path)
        .and_then(|mut f| f.read_exact(&mut head))
        .is_ok()
        && head == *b"\x7fELF"
}

/// Запускает команду; `None` — не запустилась или проба справки отклонена
/// (вывод считается пустым).
pub fn spawn(argv: &[String], n: u64) -> Option<Job> {
    let probe = is_help_probe(argv);
    if probe && !resolve(argv.first()?).is_some_and(|p| is_elf(&p)) {
        crate::paths::debug(&format!("проба справки пропущена, не ELF: {}", argv[0]));
        return None;
    }
    let out = out_path(n);
    std::fs::create_dir_all(out.parent()?).ok()?;
    let file = std::fs::File::create(&out).ok()?;
    let mut cmd = Command::new(&argv[0]);
    cmd.args(&argv[1..])
        .stdin(Stdio::null())
        .stdout(Stdio::from(file))
        .stderr(Stdio::null())
        .env("TERM", "dumb")
        .env("MANPAGER", "cat")
        .env("PAGER", "cat")
        .env("MANWIDTH", "200")
        .env("NO_COLOR", "1")
        .env_remove("HERDR_PANE_ID");
    if probe {
        for k in PROBE_ENV_REMOVE {
            cmd.env_remove(k);
        }
    }
    // SAFETY: setsid в дочернем процессе до exec — безопасный системный вызов.
    unsafe {
        cmd.pre_exec(|| {
            libc::setsid();
            // Маска сигналов просмотрщика (signalfd) не наследуется командой.
            let mut set: libc::sigset_t = std::mem::zeroed();
            libc::sigemptyset(&mut set);
            libc::sigprocmask(libc::SIG_SETMASK, &set, std::ptr::null_mut());
            Ok(())
        });
    }
    let child = match cmd.spawn() {
        Ok(c) => c,
        Err(_) => {
            let _ = std::fs::remove_file(&out);
            return None;
        }
    };
    let pid = child.id() as i32;
    let Some(pidfd) = crate::channel::pidfd_open(pid) else {
        let _ = std::fs::remove_file(&out);
        return None;
    };
    Some(Job {
        argv: argv.to_vec(),
        n,
        pid,
        pidfd,
        out,
        child,
    })
}

impl Job {
    /// Забирает завершившийся процесс и его вывод.
    pub fn finish(mut self) -> String {
        let _ = self.child.wait();
        let text = std::fs::read(&self.out)
            .map(|b| String::from_utf8_lossy(&b).to_string())
            .unwrap_or_default();
        let _ = std::fs::remove_file(&self.out);
        text
    }

    /// Завершает процесс и его группу (смена контекста, выход).
    pub fn kill(mut self) {
        // SAFETY: сигнал своей дочерней группе процессов (setsid сделал pid лидером).
        unsafe {
            libc::kill(-self.pid, libc::SIGKILL);
        }
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_file(&self.out);
    }
}

/// Синхронный запуск с ожиданием завершения (`table`).
pub fn run_blocking(argv: &[String]) -> Option<String> {
    spawn(argv, 0).map(Job::finish)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(a: &[&str]) -> Vec<String> {
        a.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn help_probe_only_elf() {
        assert!(is_help_probe(&v(&["ls", "--help"])));
        assert!(!is_help_probe(&v(&["man", "-P", "cat", "ls"])));
        assert!(!is_help_probe(&v(&["--help"])));
        let sh = resolve("sh").expect("sh");
        assert!(is_elf(&sh) || std::fs::read_link(&sh).is_ok());
        let d = std::env::temp_dir().join(format!("kh-cmdrun-{}", std::process::id()));
        std::fs::create_dir_all(&d).expect("tmp");
        let script = d.join("act");
        let mark = d.join("ran");
        std::fs::write(&script, format!("#!/bin/sh\ntouch {}\n", mark.display())).expect("script");
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).expect("chmod");
        }
        assert!(!is_elf(&script));
        let argv = vec![script.display().to_string(), "--help".to_string()];
        assert!(spawn(&argv, 9_000_001).is_none(), "сценарий с --help не запускается");
        assert!(!mark.exists());
        // Без --help сценарий — обычная команда источника.
        let out = run_blocking(&[script.display().to_string()]);
        assert!(out.is_some() && mark.exists());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn help_probe_env_without_session() {
        // sh — ELF; `--help` здесь только $0 сценария, а печатается окружение пробы.
        std::env::set_var("WAYLAND_DISPLAY", "wayland-test");
        let out = run_blocking(&v(&["sh", "-c", "env", "--help"])).unwrap_or_default();
        std::env::remove_var("WAYLAND_DISPLAY");
        assert!(out.contains("TERM=dumb"), "{out}");
        assert!(!out.contains("WAYLAND_DISPLAY="), "{out}");
    }
}
