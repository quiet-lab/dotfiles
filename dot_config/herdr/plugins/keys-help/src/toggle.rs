//! Действие `toggle` (D4): закрыть просмотрщик tab, если он есть, иначе открыть.

use serde_json::{json, Value};

use crate::herdr::{s, Client};

pub const PLUGIN_ID: &str = "quiet-lab.keys-help";
pub const TOKEN: &str = "keys_help";
pub const SOURCE: &str = "plugin:quiet-lab.keys-help";

/// Панели tab с токеном просмотрщика.
pub fn viewers_in_tab(panes: &[Value], tab: &str) -> Vec<String> {
    panes
        .iter()
        .filter(|p| s(p, "tab_id") == Some(tab))
        .filter(|p| p.get("tokens").and_then(|t| t.get(TOKEN)).is_some())
        .filter_map(|p| s(p, "pane_id").map(str::to_string))
        .collect()
}

/// Ставит панели токен просмотрщика (без срока: снимается вместе с панелью).
pub fn mark(client: &mut Client, pane_id: &str) -> crate::herdr::Result<()> {
    client.call(
        "pane.report_metadata",
        json!({"pane_id": pane_id, "source": SOURCE, "tokens": {TOKEN: "viewer"}}),
    )?;
    Ok(())
}

fn find_pane_id(v: &Value) -> Option<String> {
    if let Some(p) = s(v, "pane_id") {
        return Some(p.to_string());
    }
    if let Value::Object(o) = v {
        for (_, x) in o {
            if let Some(p) = find_pane_id(x) {
                return Some(p);
            }
        }
    }
    None
}

pub fn run() -> Result<(), String> {
    let pane = std::env::var("HERDR_PANE_ID").map_err(|_| "нет HERDR_PANE_ID".to_string())?;
    let mut client = Client::connect().map_err(|e| e.to_string())?;
    let cur = client
        .call("pane.current", json!({"caller_pane_id": pane}))
        .map_err(|e| e.to_string())?;
    let info = cur.get("pane").cloned().unwrap_or(Value::Null);
    let ws = s(&info, "workspace_id").unwrap_or("").to_string();
    let tab = std::env::var("HERDR_TAB_ID")
        .ok()
        .filter(|t| !t.is_empty())
        .or_else(|| s(&info, "tab_id").map(str::to_string))
        .unwrap_or_default();
    let list = client
        .call("pane.list", json!({"workspace_id": ws}))
        .map_err(|e| e.to_string())?;
    let panes = list
        .get("panes")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let viewers = viewers_in_tab(&panes, &tab);
    if !viewers.is_empty() {
        for v in viewers {
            client
                .call("plugin.pane.close", json!({"pane_id": v}))
                .map_err(|e| e.to_string())?;
        }
        return Ok(());
    }
    let opened = client
        .call(
            "plugin.pane.open",
            json!({
                "plugin_id": PLUGIN_ID,
                "entrypoint": "viewer",
                "placement": "split",
                "target_pane_id": pane,
                "direction": "down",
                "focus": false,
                "env": {"KEYS_HELP_TARGET": pane},
            }),
        )
        .map_err(|e| e.to_string())?;
    // Токен сразу, чтобы повторное нажатие закрыло панель ещё до старта просмотрщика.
    if let Some(id) = find_pane_id(&opened) {
        if id != pane {
            let _ = mark(&mut client, &id);
        }
    }
    Ok(())
}
