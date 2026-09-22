<!-- Черновик обращения в https://issues.chromium.org, не отправлен; отправка — решение пользователя. -->

# Chromium on Wayland never calls xdg_toplevel.set_parent for secondary windows

## Summary

Under the Ozone/Wayland backend, Chromium never calls
`xdg_toplevel.set_parent` for any of its secondary windows (task manager,
detached DevTools, a new window opened with Ctrl+N), and
`XdgToplevel::SetSystemModal` is implemented as an empty stub
(tracked as [crbug.com/378465003](https://issues.chromium.org/issues/378465003)).
As a result, no compositor, compositor plugin, or third-party tool can tell
a Chromium dialog apart from a regular top-level window.

## Current behavior

Searching `ui/ozone/platform/wayland` in the Chromium tree finds no call to
`xdg_toplevel_set_parent`. Every additional window a Chromium-based browser
opens — the task manager, a detached DevTools window, a window opened by
Ctrl+N — arrives at the compositor as an independent top-level window: no
parent, no modal flag, no relationship to the window it logically belongs
to. `XdgToplevel::SetSystemModal()` is present in the code but does nothing
(empty body), matching the existing tracking bug
[crbug.com/378465003](https://issues.chromium.org/issues/378465003). The
print preview is drawn inside the tab itself, and the file picker is handed
off to the XDG desktop portal, so those two specific cases are not affected
— but every other secondary window is.

This is not compositor-specific: we observe it on Hyprland, but the same gap
exists on GNOME (Mutter) and KDE (KWin), since it is Chromium that never
issues the call, not a compositor limitation.

## Expected behavior

Chromium should call `xdg_toplevel.set_parent` when creating a window that
is logically a child of another Chromium window (task manager, detached
DevTools, dialogs), and should implement `XdgToplevel::SetSystemModal` to
call the `xdg-dialog-v1` protocol (`xdg_wm_dialog_v1.get_xdg_dialog` plus
`xdg_dialog_v1.set_modal`) where the window is actually modal.

## Why

External tools that manage window placement (tiling window managers,
window-manager-adjacent daemons, accessibility tools) rely on
`xdg_toplevel.set_parent` and `xdg-dialog-v1` to tell an application's
dialogs apart from its regular windows, so they do not force dialog geometry
into a tiling layout meant for top-level windows. GTK4 and Qt6 (6.8+) both
call these protocol methods correctly for their own dialogs; Chromium is the
outlier among the toolkits we tested. Because Chromium does not call them,
neither the compositor nor a compositor plugin nor a third-party client can
recover this relationship — the information simply never reaches Wayland.

## Environment

- Google Chrome and Yandex Browser (Chromium-based), current stable channel
  as of September 2026, running under Wayland (`--ozone-platform=wayland`)
  on Hyprland 0.56.2
- Also observed under GNOME/Mutter and KDE/KWin — this is not
  compositor-specific

## References

- `ui/ozone/platform/wayland` — the Ozone/Wayland backend where
  `xdg_toplevel.set_parent` and `xdg-dialog-v1` would need to be wired up
- [crbug.com/378465003](https://issues.chromium.org/issues/378465003) —
  existing tracking bug for the empty `XdgToplevel::SetSystemModal` stub
- For comparison, GTK4 and Qt6 (6.8+) both call `xdg_toplevel.set_parent`
  and the `xdg-dialog-v1` modal state correctly
