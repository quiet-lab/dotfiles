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

/// Запускает команду; `None` — не запустилась (вывод считается пустым).
pub fn spawn(argv: &[String], n: u64) -> Option<Job> {
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
