//! Бинарник keys-help: подкоманды `toggle`, `viewer`, `table`, `unknown list`.

use std::process::ExitCode;

const USAGE: &str = "использование: keys-help toggle | viewer | table <контекст> [--pane <id>] [--json] | unknown list";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("toggle") => keys_help::toggle::run(),
        Some("viewer") => keys_help::viewer::run(),
        Some("table") => {
            let mut ctx = None;
            let mut pane = None;
            let mut json = false;
            let mut it = args[1..].iter();
            while let Some(a) = it.next() {
                match a.as_str() {
                    "--pane" => pane = it.next().cloned(),
                    "--json" => json = true,
                    other if ctx.is_none() => ctx = Some(other.to_string()),
                    _ => {}
                }
            }
            match ctx {
                Some(c) => keys_help::viewer::print_table(&c, pane.as_deref(), json),
                None => Err(USAGE.to_string()),
            }
        }
        Some("unknown") if args.get(1).map(String::as_str) == Some("list") => {
            keys_help::viewer::print_unknown();
            Ok(())
        }
        _ => Err(USAGE.to_string()),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            keys_help::paths::log(&e);
            eprintln!("keys-help: {e}");
            ExitCode::FAILURE
        }
    }
}
