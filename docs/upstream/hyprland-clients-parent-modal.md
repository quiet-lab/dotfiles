<!-- Черновик обращения в https://github.com/hyprwm/Hyprland, не отправлен; отправка — решение пользователя. -->

# Expose window parent and modal state in `hyprctl clients -j` and `HL.Window`

## Summary

Add two read-only fields to the client object returned by `hyprctl clients -j`
(and to the Lua window object `HL.Window`): `parent` (the address of the
parent toplevel, or empty/null) and `modal` (whether the window or any of its
children is a modal dialog). Also send the already-declared `parent` event in
the `wlr-foreign-toplevel-management` implementation.

## Current behavior

Hyprland already tracks this information internally:

- `CWindow::parent()` reads it from `xdg_toplevel.set_parent`.
- `CXDGToplevelResource::anyChildModal()` reads it from `xdg-dialog-v1`
  (`xdg_wm_dialog_v1.get_xdg_dialog` plus `xdg_dialog_v1.set_modal`).

None of this reaches the outside. `hyprctl clients -j` includes `address`,
`class`, `title`, `initialClass`, `initialTitle`, `floating`, `pinned`,
`xdgTag`, `xdgDescription`, `swallowing`, `grouped` and more, but no parent
and no modal flag. The Lua stub `HL.Window`
(`/usr/share/hypr/stubs/hl.meta.lua`) mirrors the same set. The existing
window rule `modal:1` only checks `CWindow::isModal()`, which in turn only
reads `_NET_WM_STATE_MODAL` on XWayland windows — it does nothing for native
Wayland clients.

Separately, `zwlr_foreign_toplevel_manager_v1` is advertised at version 3,
which declares a `parent` event, but Hyprland never calls
`wlr_foreign_toplevel_handle_v1_set_parent`, so the event is never sent even
though the advertised version promises it. (labwc and Wayfire call it; sway
and niri advertise v3 but do not call it either.)

## Expected behavior

- `hyprctl clients -j` includes `parent` (address string or empty/null) and
  `modal` (boolean) per window.
- `HL.Window` exposes the same two fields.
- The `wlr-foreign-toplevel-management` implementation sends the `parent`
  event whenever a toplevel's parent changes, matching what version 3 of the
  protocol already declares.

## Why

We run a tiling daemon outside the compositor (`workspaced`) that manages
window placement per virtual desktop. It needs to tell an application dialog
(task manager, detached DevTools, a "Save As" prompt) apart from a regular
top-level window of the same application, so it does not force dialog
geometry into a tiling cell. Right now there is no way to do this from
outside the compositor: the data exists inside Hyprland but is not
serialized anywhere. We currently work around this with a title regex and a
window-class denylist in our own config, which is fragile and
application-specific.

This is additive only: two new optional fields on an existing IPC/Lua
structure, and one event send that the protocol version already promises.
Nothing existing changes shape or meaning.

Two earlier, broader requests were closed as not planned and are not what
this asks for:

- [#6879](https://github.com/hyprwm/Hyprland/issues/6879) asked for a whole
  new window-manager protocol with relationships between windows.
- [#9549](https://github.com/hyprwm/Hyprland/issues/9549) asked for window
  rules targeting modal dialogs.

This request is neither: it does not ask for a new protocol or a new rule,
only for two fields Hyprland already computes to be exposed through the
existing IPC and Lua surfaces.

## Environment

- Hyprland 0.56.2
- wayland 1.26.0, wayland-protocols 1.49
- Arch-based (CachyOS)

## Notes

This does not help with Chromium-based windows (Google Chrome, the Yandex
Browser, Electron apps): they call neither `xdg_toplevel.set_parent` nor
`xdg-dialog-v1` at all, so no amount of exposing existing compositor state
helps there — that is a separate, Chromium-side gap.
