//! Клиент сокета herdr (D3): запросы и подписка `events.subscribe`.
//! Протокол — JSON по строкам через Unix-сокет.

use std::io::{BufRead, BufReader, Read, Write};
use std::os::fd::{AsRawFd, RawFd};
use std::os::unix::net::UnixStream;

use serde_json::{json, Value};

#[derive(Debug)]
pub enum Error {
    Io(std::io::Error),
    /// Ответ с ошибкой: код и сообщение.
    Api(String, String),
    Protocol(String),
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::Io(e) => write!(f, "сокет herdr: {e}"),
            Error::Api(c, m) => write!(f, "herdr: {c}: {m}"),
            Error::Protocol(m) => write!(f, "herdr: {m}"),
        }
    }
}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error::Io(e)
    }
}

pub type Result<T> = std::result::Result<T, Error>;

/// Путь сокета: `HERDR_SOCKET_PATH` или сокет сессии по умолчанию.
pub fn socket_path() -> String {
    match std::env::var("HERDR_SOCKET_PATH") {
        Ok(v) if !v.is_empty() => v,
        _ => format!("{}/.config/herdr/herdr.sock", crate::paths::home()),
    }
}

/// Запросы к серверу. Сервер отвечает на один запрос в соединении и
/// закрывает его, поэтому каждый запрос идёт новым соединением.
pub struct Client {
    next: u64,
}

impl Client {
    /// Проверяет, что сокет доступен.
    pub fn connect() -> Result<Client> {
        UnixStream::connect(socket_path())?;
        Ok(Client { next: 0 })
    }

    /// Запрос и ответ; возвращает `result`.
    pub fn call(&mut self, method: &str, params: Value) -> Result<Value> {
        self.next += 1;
        let id = format!("keys-help:{}:{}", std::process::id(), self.next);
        let mut writer = UnixStream::connect(socket_path())?;
        let mut reader = BufReader::new(writer.try_clone()?);
        let line = json!({"id": id, "method": method, "params": params}).to_string();
        writer.write_all(line.as_bytes())?;
        writer.write_all(b"\n")?;
        loop {
            let mut buf = String::new();
            if reader.read_line(&mut buf)? == 0 {
                return Err(Error::Protocol("соединение закрыто".to_string()));
            }
            let v: Value = serde_json::from_str(buf.trim())
                .map_err(|e| Error::Protocol(format!("ответ не JSON: {e}")))?;
            if v.get("id").and_then(Value::as_str) != Some(id.as_str()) {
                continue;
            }
            if let Some(err) = v.get("error") {
                return Err(Error::Api(
                    err.get("code").and_then(Value::as_str).unwrap_or("").to_string(),
                    err.get("message").and_then(Value::as_str).unwrap_or("").to_string(),
                ));
            }
            return Ok(v.get("result").cloned().unwrap_or(Value::Null));
        }
    }
}

/// Событие подписки или потеря событий.
#[derive(Debug)]
pub enum Incoming {
    Event(Value),
    /// `events_lost`: подписка закрыта сервером, нужна новая.
    Lost,
    /// Соединение закрыто.
    Closed,
}

/// Долгое соединение подписки; читается без блокировки по готовности дескриптора.
pub struct Subscription {
    stream: UnixStream,
    buf: Vec<u8>,
    id: String,
}

impl Subscription {
    /// Подписка на события; ждёт подтверждения и переводит сокет в неблокирующий режим.
    pub fn open(subscriptions: Value) -> Result<Subscription> {
        let mut stream = UnixStream::connect(socket_path())?;
        let id = format!("keys-help:sub:{}", std::process::id());
        let line = json!({"id": id, "method": "events.subscribe",
                          "params": {"subscriptions": subscriptions}})
        .to_string();
        stream.write_all(line.as_bytes())?;
        stream.write_all(b"\n")?;
        // Первая строка — подтверждение или ошибка.
        let mut first = Vec::new();
        let mut byte = [0u8; 1];
        loop {
            let n = stream.read(&mut byte)?;
            if n == 0 {
                return Err(Error::Protocol("подписка закрыта".to_string()));
            }
            if byte[0] == b'\n' {
                break;
            }
            first.push(byte[0]);
        }
        let v: Value = serde_json::from_slice(&first)
            .map_err(|e| Error::Protocol(format!("ответ подписки не JSON: {e}")))?;
        if let Some(err) = v.get("error") {
            return Err(Error::Api(
                err.get("code").and_then(Value::as_str).unwrap_or("").to_string(),
                err.get("message").and_then(Value::as_str).unwrap_or("").to_string(),
            ));
        }
        stream.set_nonblocking(true)?;
        Ok(Subscription {
            stream,
            buf: Vec::new(),
            id,
        })
    }

    pub fn fd(&self) -> RawFd {
        self.stream.as_raw_fd()
    }

    /// Читает всё доступное и возвращает полные строки.
    pub fn read(&mut self) -> Vec<Incoming> {
        let mut out = Vec::new();
        let mut chunk = [0u8; 65536];
        let mut closed = false;
        loop {
            match self.stream.read(&mut chunk) {
                Ok(0) => {
                    closed = true;
                    break;
                }
                Ok(n) => self.buf.extend_from_slice(&chunk[..n]),
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(_) => {
                    closed = true;
                    break;
                }
            }
        }
        while let Some(p) = self.buf.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = self.buf.drain(..=p).collect();
            let Ok(v) = serde_json::from_slice::<Value>(&line) else {
                continue;
            };
            if let Some(err) = v.get("error") {
                if err.get("code").and_then(Value::as_str) == Some("events_lost") {
                    out.push(Incoming::Lost);
                } else {
                    out.push(Incoming::Closed);
                }
                continue;
            }
            if v.get("id").and_then(Value::as_str) == Some(self.id.as_str()) {
                continue;
            }
            out.push(Incoming::Event(v));
        }
        if closed {
            out.push(Incoming::Closed);
        }
        out
    }
}

/// Имя события без различия точки и подчёркивания: `pane_focused`.
pub fn event_name(ev: &Value) -> String {
    ev.get("event")
        .and_then(Value::as_str)
        .or_else(|| ev.get("data").and_then(|d| d.get("type")).and_then(Value::as_str))
        .unwrap_or("")
        .replace('.', "_")
}

/// Данные события.
pub fn event_data(ev: &Value) -> &Value {
    ev.get("data").unwrap_or(ev)
}

/// Строковое поле JSON.
pub fn s<'a>(v: &'a Value, key: &str) -> Option<&'a str> {
    v.get(key).and_then(Value::as_str)
}
