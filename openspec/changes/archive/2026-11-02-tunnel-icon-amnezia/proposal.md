## Why

Знак анархии с Wikimedia Commons не связан с AmneziaVPN, а зелёный
`Theme.green` (#73DACA) на значках туннелей близок к бирюзовому и плохо
отличим от других плиток. Значок `amn0` должен быть символом самой
Amnezia, а «поднят» — ярко-зелёным, как молнии обоев.

## What Changes

- Значок `amn0` — одноцветный силуэт символа Amnezia из логотипа клиента
  (`amneziaLogo.svg`, GPL-3.0), без надписи, Shape с цветом состояния.
- Новый токен `Theme.brightGreen` (#98D048); значки туннелей в состоянии
  «поднят» — им, остальные плитки не меняются.

## Capabilities

### New Capabilities

### Modified Capabilities

- `qs-tray-lang`: требование «Значки туннелей».

## Impact

`dot_config/quickshell/panel/tiles/Tray.qml`, `panel/icons/`
(`amnezia.js`, `README.md`; `anarchy.svg` удалён из источника и
из `$HOME`),
`dot_config/quickshell/common/Theme.qml`.
