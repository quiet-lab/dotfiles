//! Терминал просмотрщика: неканонический режим, размер, signalfd.

use std::os::fd::{FromRawFd, OwnedFd};

/// Неканонический режим и альтернативный экран; восстанавливаются при `drop`.
pub struct RawTerm {
    saved: Option<libc::termios>,
}

impl RawTerm {
    pub fn enter() -> RawTerm {
        // SAFETY: tcgetattr/tcsetattr на дескрипторе 0 с локальной структурой.
        let saved = unsafe {
            let mut t: libc::termios = std::mem::zeroed();
            if libc::tcgetattr(0, &mut t) != 0 {
                None
            } else {
                let orig = t;
                libc::cfmakeraw(&mut t);
                // Вывод с обычным переводом строки не нужен: кадр пишется с \r\n.
                libc::tcsetattr(0, libc::TCSANOW, &t);
                Some(orig)
            }
        };
        write_out("\x1b[?1049h\x1b[?25l");
        RawTerm { saved }
    }
}

impl Drop for RawTerm {
    fn drop(&mut self) {
        write_out("\x1b[?25h\x1b[?1049l");
        if let Some(t) = &self.saved {
            // SAFETY: восстановление сохранённых настроек терминала.
            unsafe {
                libc::tcsetattr(0, libc::TCSANOW, t);
            }
        }
    }
}

/// Пишет в терминал; ошибка записи (панель закрыта) игнорируется.
pub fn write_out(s: &str) -> bool {
    use std::io::Write;
    let mut o = std::io::stdout().lock();
    o.write_all(s.as_bytes()).is_ok() && o.flush().is_ok()
}

/// Размер терминала: (столбцы, строки).
pub fn size() -> (usize, usize) {
    // SAFETY: ioctl TIOCGWINSZ в локальную структуру.
    unsafe {
        let mut ws: libc::winsize = std::mem::zeroed();
        if libc::ioctl(1, libc::TIOCGWINSZ, &mut ws) == 0 && ws.ws_col > 0 {
            (ws.ws_col as usize, ws.ws_row as usize)
        } else {
            (80, 24)
        }
    }
}

/// signalfd для SIGWINCH, SIGTERM, SIGHUP, SIGINT (сигналы блокируются).
pub fn signalfd() -> Option<OwnedFd> {
    // SAFETY: работа с локальным набором сигналов и системный вызов signalfd.
    unsafe {
        let mut set: libc::sigset_t = std::mem::zeroed();
        libc::sigemptyset(&mut set);
        for s in [libc::SIGWINCH, libc::SIGTERM, libc::SIGHUP, libc::SIGINT] {
            libc::sigaddset(&mut set, s);
        }
        libc::sigprocmask(libc::SIG_BLOCK, &set, std::ptr::null_mut());
        let fd = libc::signalfd(-1, &set, libc::SFD_NONBLOCK | libc::SFD_CLOEXEC);
        if fd < 0 {
            return None;
        }
        Some(OwnedFd::from_raw_fd(fd))
    }
}

/// Читает номера пришедших сигналов.
pub fn read_signals(fd: &OwnedFd) -> Vec<i32> {
    use std::os::fd::AsRawFd;
    let mut out = Vec::new();
    loop {
        // SAFETY: чтение структуры signalfd_siginfo в локальный буфер её размера.
        let mut info: libc::signalfd_siginfo = unsafe { std::mem::zeroed() };
        let n = unsafe {
            libc::read(
                fd.as_raw_fd(),
                (&mut info as *mut libc::signalfd_siginfo).cast(),
                std::mem::size_of::<libc::signalfd_siginfo>(),
            )
        };
        if n <= 0 {
            break;
        }
        out.push(info.ssi_signo as i32);
    }
    out
}
