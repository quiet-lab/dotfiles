## Why

У соединения `axata` остаётся один маршрут — 10.0.0.0/8 через 10.200.5.254:
маршрут 10.200.0.0/16 входит в него и лишний. Окно сведений `axata`
показывает маршрут, которого в профиле больше нет.

## What Changes

- Из профиля `axata` убирается маршрут 10.200.0.0/16.
- Окно сведений `axata` показывает маршрут 10.0.0.0/8 вместо 10.200.0.0/16.

## Capabilities

### New Capabilities

### Modified Capabilities

- `qs-tray-lang`: требование «Окно сведений туннеля».

## Impact

`dot_config/quickshell/panel/scripts/tunnelinfo`,
`docs/amnezia-split-tunnel.md`, профиль NetworkManager `axata`.
