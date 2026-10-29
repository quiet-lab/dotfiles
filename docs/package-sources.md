# Источники пакетов

Документ сводит в одну таблицу, откуда установлена каждая программа
машины, какие версии доступны в каждом источнике и куда её переводить.
Цель — единый источник для каждой программы, чтобы обновление шло
одной командой `paru -Syu`, а не набором `mise upgrade`, `cargo install`
и ручных скачиваний.

Версии сняты 2026-10-29. Правило выбора источника предложено и ещё
не оформлено записью решения; когда оно будет принято, ляжет в
`docs/decisions/` (номер следующий после 0008), а здесь останется ссылка.

## Правило выбора источника

1. Предпочитается пакет официальных репозиториев (pacman: core, extra
   и зеркала CachyOS).
2. Пакет AUR берётся, только если в репозиториях пакета нет либо
   репозиторий отстаёт от AUR (или от последней версии upstream, если
   AUR-пакет `-bin` ей равен) не меньше чем на минорную версию (средняя
   цифра в X.Y.Z; для версий-дат, как у wezterm и yazi, — на месяц
   и больше). Пакеты `-git` и `nightly` кандидатами не считаются, кроме
   случая, когда другого пакета программы нет.
3. mise, cargo, flatpak, AppImage и ручная сборка из git допустимы,
   только если программы нет ни в репозиториях, ни в AUR.

Условные обозначения таблицы: «—» — источника нет или команда ответа не
дала; колонка «mise» — последняя версия по `mise latest`; «cargo» —
последняя версия на crates.io; «git» — последний тег upstream
(запрашивался только для программ, у которых он нужен для решения);
«AUR» — пакет с выпускаемой версией, пакеты `-git` не показаны.

## Таблица

| Программа | Сейчас | pacman | AUR | mise | cargo | flatpak | AppImage | git | По правилу | Что сделать |
|---|---|---|---|---|---|---|---|---|---|---|
| atuin | mise 18.20.1 | 18.23.0 | — | 18.24.2 | 18.24.3 | — | — | — | pacman | снять из mise, поставить extra/atuin |
| bat | mise 0.26.1, pacman | 0.26.1 | — | 0.26.1 | 0.26.1 | — | — | — | pacman | удалить дубль mise |
| btop | mise 1.4.7, pacman | 1.4.7 | — | 1.4.8 | — | — | — | — | pacman | удалить дубль mise |
| bun | mise 1.4.0 | 1.4.3 | bun-bin 1.4.4 | 1.4.4 | — | — | — | — | pacman | снять из mise, поставить extra/bun |
| cargo-binstall | mise 1.22.0 | 1.25.1 | — | 1.26.1 | 1.26.1 | — | — | — | pacman | снять из mise, поставить extra/cargo-binstall |
| chezmoi | mise 2.72.0 | 2.73.1 | — | 2.73.3 | — | — | — | — | pacman | снять из mise, поставить extra/chezmoi |
| claude (Claude Code) | вручную, `~/.local/share/claude` 2.1.312 | claude-code 2.1.301 (cachyos) | claude-code 2.1.312 | — | — | — | — | — | pacman | снять ручную установку, поставить cachyos/claude-code |
| deno | mise 2.9.6 | 2.9.7 | deno-stable-bin 2.9.7 | 2.9.8 | — | — | — | — | pacman | снять из mise, поставить extra/deno |
| eww-daemon | cargo install 0.1.0 | — | — | — | — | — | — | — | остаётся: cargo (свой проект) | свой проект |
| fd | mise 10.5.0, pacman | 10.5.0 | — | 10.5.0 | 10.5.0 | — | — | — | pacman | удалить дубль mise |
| ffmpeg | mise 9.0.1, pacman | 9.0.2 | — | 9.0.2 | — | — | — | — | pacman | удалить дубль mise |
| fzf | mise 0.74.3, pacman | 0.74.5 | — | 0.74.5 | — | — | — | — | pacman | удалить дубль mise |
| groovy | mise 4.0.33 | 6.0.0 | — | 6.0.0 | — | — | — | — | pacman | снять из mise, поставить extra/groovy (проверить, нужна ли ветка 4.x) |
| herdr | mise 0.8.2 (бинарник 0.9.0) | — | herdr-bin 0.9.5 | 0.9.5 | — | — | — | v0.9.5 | AUR (herdr-bin) | снять из mise, `paru -S herdr-bin` |
| hunk | mise 0.20.0 | — | hunk-bin 0.24.1 | 0.24.1 | — | — | — | v0.24.1 | AUR (hunk-bin) | снять из mise, `paru -S hunk-bin` |
| imagemagick | mise 7.1.2_30, pacman | 7.1.2.34 | — | 7.1.2_31 | — | — | — | — | pacman | удалить дубль mise |
| java | mise temurin-21.0.13 | jdk21-openjdk 21.0.12.1 | jdk21-temurin 21.0.13 | 27.0.1.0.3 | — | — | — | — | pacman | снять из mise, поставить extra/jdk21-openjdk (отставание в патч-версии) |
| jq | mise 1.8.2, pacman | 1.8.2 | — | 1.8.2 | — | — | — | — | pacman | удалить дубль mise |
| just | mise 1.58.0 | 1.59.0 | — | 1.59.0 | 1.59.0 | — | — | — | pacman | снять из mise, поставить extra/just |
| lazygit | mise 0.64.1 | 0.66.1 | — | 0.66.2 | — | — | — | — | pacman | снять из mise, поставить extra/lazygit |
| lsd | mise 1.2.0 | 1.2.0 | — | 1.2.0 | 1.2.0 | — | — | — | pacman | снять из mise, поставить extra/lsd |
| neovide | cargo install из git 0.16.2 | 0.16.2 | neovide-bin 0.16.2 | — | 0.16.2 | 0.16.2 | 0.16.2 | v0.16.2 | pacman | снять `~/.cargo/bin/neovide`, поставить extra/neovide |
| neovim | mise stable (0.12.6) | 0.12.6 | — | 0.12.6 | — | — | — | — | pacman | снять из mise, поставить extra/neovim |
| node 26 | mise 26.8.1 | nodejs 26.11.1 | — | 26.13.0 | — | — | — | — | pacman | снять из mise, поставить extra/nodejs |
| node 20, 22, 24 | mise 20.20.2, 22.23.3, 24.20.0, 24.22.1 | nodejs-lts-iron 20.20.2, -jod 22.23.3, -krypton 24.21.0 | — | 20.20.2, 22.23.4, 24.22.2 | — | — | — | — | остаётся: mise (закреплённые версии) | оставить: пакеты nodejs-lts-* конфликтуют с nodejs и не ставятся рядом |
| oh-my-pi | mise github 18.0.10 | — | oh-my-pi-bin 18.13.3 | 18.13.2 | — | — | — | v18.13.3 | AUR (oh-my-pi-bin) | снять из mise, `paru -S oh-my-pi-bin` |
| oha | cargo install 1.16.0 | 1.16.0 | — | — | 1.16.0 | — | — | — | pacman | снять `~/.cargo/bin/oha`, поставить extra/oha |
| ollama | вручную, `/usr/local/bin` 0.32.14 | 0.40.4 | ollama-bin 0.40.12 | — | — | — | — | v0.40.13 | pacman | снять ручную установку, поставить extra/ollama (и ollama-cuda) |
| opencode | mise 1.18.25 | 2.0.29 | opencode-bin 1.19.5 | 2.2.0 | — | — | — | v1.19.5 | pacman | снять из mise, поставить extra/opencode |
| OpenSpec (@fission-ai) | bun global 1.10.0 | — | openspec 1.15.0 | — | — | — | — | — | AUR (openspec) | снять из bun global, `paru -S openspec` |
| oxker | mise 0.13.4 | — | oxker-bin 0.13.4 | 0.13.4 | 0.13.4 | — | — | v0.13.4 | AUR (oxker-bin) | снять из mise, `paru -S oxker-bin` |
| poetry 2.4.2 | mise 2.4.2 | python-poetry 2.5.1 | — | 2.5.1 | — | — | — | — | pacman | снять из mise, поставить extra/python-poetry |
| poetry 1.8.2, 1.8.3, pipx:poetry 1.8.3 | mise | — (только 2.5.1) | — | — | — | — | — | — | остаётся: mise (закреплённые старые версии) | оставить |
| python 3.14 | mise 3.14.7, pacman | 3.14.8 | — | 3.15.2 | — | — | — | — | pacman | удалить дубль mise |
| python 3.12 | mise 3.12.14, 3.12.15 | — | python312 3.12.16 | 3.12.16 | — | — | — | — | AUR (python312) | снять из mise, `paru -S python312` |
| python 3.11, 3.14, 3.14t | uv python | 3.14.8 (только 3.14) | — | — | — | — | — | — | остаётся: uv (кэш интерпретаторов uv) | оставить |
| py-spy | uv tool 0.4.2 | — | py-spy-bin 0.4.2 | — | 0.4.2 | — | — | v0.4.2 | AUR (py-spy-bin) | снять из uv tool, `paru -S py-spy-bin` |
| resvg | mise 0.48.1 | 0.48.1 | — | 0.49.0 | 0.49.0 | — | — | — | pacman | снять из mise, поставить extra/resvg |
| ruff | mise 0.16.9 | 0.17.1 | — | 0.17.3 | — | — | — | — | pacman | снять из mise, поставить extra/ruff |
| rust | mise (ссылка на `~/.cargo/bin`, rustup, nightly 1.100.0) | rustup 1.29.1 | — | 1.99.1 | — | — | — | — | pacman | поставить extra/rustup вместо `~/.cargo/bin/rustup`, снять запись rust из mise; наборы инструментов остаются в `~/.rustup` |
| starship | mise 1.26.0 | 1.26.0 | — | 1.27.0 | 1.27.0 | — | — | — | pacman | снять из mise, поставить extra/starship |
| television | mise 0.15.9 | 0.15.9 | — | 0.15.9 | 0.15.9 | — | — | — | pacman | снять из mise, поставить extra/television |
| tuicr | mise github 0.24.0 | 0.27.0 | — | 0.28.0 | 0.28.0 | — | — | v0.28.0 | pacman | снять из mise, поставить extra/tuicr |
| usage | mise 6.5.0 | 6.12.1 | — | 7.1.3 | — | — | — | — | pacman | снять из mise, поставить extra/usage |
| uv | mise 0.12.9, 0.12.7 | 0.13.1 | — | 0.13.6 | 0.13.6 | — | — | — | pacman | снять из mise, поставить extra/uv |
| vault | mise 2.2.1 | 2.1.1 | vault-bin 1.18.0 | 2.2.1 | — | — | — | — | pacman | снять из mise, поставить extra/vault (версия в репозитории ниже на минорную) |
| watchexec | mise 2.7.0 | 2.8.0 | — | 2.8.0 | 2.8.0 | — | — | — | pacman | снять из mise, поставить extra/watchexec |
| wezterm | сборка `~/builds/wezterm` 20260805 | 20240203 | wezterm-nightly-bin (nightly), wezterm-git | — | — | 20240203 | 20240203 | 20240203 | AUR (wezterm-nightly-bin) | `paru -S wezterm-nightly-bin`, сборку убрать; репозиторий отстаёт на два года |
| xh | mise 0.26.2 | 0.26.2 | — | 0.26.3 | 0.26.3 | — | — | — | pacman | снять из mise, поставить extra/xh |
| yarn 1.22.22 | mise 1.22.22 | 1.22.22 | — | 1.22.22 | — | — | — | — | pacman | снять из mise, поставить extra/yarn |
| yarn 4 | mise 4.11.0 | — | yarn-berry 4.18.0 | 4.18.1 | — | — | — | — | AUR (yarn-berry) | `paru -S yarn-berry`; пакет конфликтует с extra/yarn, из двух ставится один |
| yazi | mise 26.8.15 | 26.9.1 | — | 26.9.1 | 26.5.6 | — | — | — | pacman | снять из mise, поставить extra/yazi |
| zoxide | mise 0.10.0 | 0.10.0 | — | 0.10.0 | 0.10.0 | — | — | — | pacman | снять из mise, поставить extra/zoxide |
| mise | вручную, `~/.local/bin/mise` 2026.8.14 | 2026.10.11 | mise-bin 2026.10.22 | — | — | — | — | v2026.10.23 | pacman | снять ручную установку, поставить extra/mise |
| workspaced | вручную 0.1.0 | — | — | — | — | — | — | — | остаётся: ручная сборка (свой проект) | свой проект |
| AmneziaVPN | установщик в `/opt` | — | amneziavpn-bin 5.0.3.0 | — | — | — | — | 5.0.3.0 | AUR (amneziavpn-bin) | запустить деинсталлятор в `/opt`, `paru -S amneziavpn-bin` |
| Handy | AppImage | — | handy-bin 0.9.8 | — | — | — | 0.9.8 | v0.9.8 | AUR (handy-bin) | убрать AppImage, `paru -S handy-bin` |
| LM Studio | AppImage 0.4.23 | — | lmstudio-bin 0.4.26 | — | — | 0.4.23 | AppImage с сайта 0.4.23 | — | AUR (lmstudio-bin) | убрать AppImage, `paru -S lmstudio-bin` |
| Vial | AppImage 0.7.5 | — | vial-appimage 0.7.5 | — | — | — | 0.7.5 | v0.7.5 | AUR (vial-appimage) | убрать AppImage, `paru -S vial-appimage` |
| docker-rootless-extras | AUR 29.9.2 | — | 29.9.2 | — | — | — | — | — | AUR (docker-rootless-extras) | оставить |
| voxtype | AUR 0.7.5 | — | 1.1.1 | — | — | — | — | — | AUR (voxtype) | обновить AUR |
| xdg-desktop-portal-termfilechooser | AUR 1.4.3 | — | 1.5.0 | — | — | — | — | — | AUR (xdg-desktop-portal-termfilechooser) | обновить AUR |
| yuckls-git | AUR (`-git`) | — | — (только `-git`) | — | — | — | — | — | AUR (yuckls-git) | оставить |

## Переводится на pacman

Тридцать три программы ставятся из репозиториев, ещё восемь уже стоят
через pacman и дублируются в mise.

Снять из mise (или другого места) и поставить пакет:

- atuin — extra 18.23.0, AUR только `-git`.
- bun — extra 1.4.3, AUR `bun-bin` 1.4.4 впереди на патч-версию.
- cargo-binstall — extra 1.25.1, AUR только `-git`.
- chezmoi — extra 2.73.1, AUR только устаревший `-git`.
- claude-code — cachyos 2.1.301, AUR 2.1.312, отставание на патч-версию; ручная установка новее пакета.
- deno — extra 2.9.7, равен AUR `deno-stable-bin`.
- groovy — extra 6.0.0, равен `mise latest`; установленная 4.0.33 — другая ветка, нужность проверить.
- java — extra `jdk21-openjdk` 21.0.12.1, AUR `jdk21-temurin` 21.0.13 впереди на патч-версию.
- just — extra 1.59.0, равен mise.
- lazygit — extra 0.66.1, AUR только `-git`.
- lsd — extra 1.2.0, равен mise.
- mise — extra 2026.10.11 новее ручной 2026.8.14; AUR `mise-bin` 2026.10.22 впереди в пределах того же месяца.
- neovide — extra 0.16.2 равен установленной из git.
- neovim — extra 0.12.6 равен stable.
- node 26 — extra `nodejs` 26.11.1, AUR нет.
- ollama — extra 0.40.4 новее установленной 0.32.14; AUR `ollama-bin` впереди на патч-версию.
- oha — extra 1.16.0 равен cargo.
- opencode — extra 2.0.29; AUR `opencode-bin` 1.19.5 старше.
- poetry 2.4.2 — extra `python-poetry` 2.5.1.
- resvg — extra 0.48.1, AUR только `-git`.
- ruff — extra 0.17.1 новее установленной 0.16.9.
- rustup — extra 1.29.1; наборы инструментов остаются в `~/.rustup`.
- starship — extra 1.26.0, AUR только `-git`.
- television — extra 0.15.9, равен mise.
- tuicr — extra 0.27.0, AUR только `-git`.
- usage — extra 6.12.1, AUR нет (в mise 7.1.3, отставание на мажорную версию, но по правилу AUR-пакета нет).
- uv — extra 0.13.1, AUR нет; отставание на патч-версии.
- vault — extra 2.1.1; AUR `vault-bin` 1.18.0 старше, установленная 2.2.1 новее пакета.
- watchexec — extra 2.8.0 равен mise.
- xh — extra 0.26.2, AUR нет.
- yarn 1.22.22 — extra 1.22.22 равен установленной.
- yazi — extra 26.9.1 равен mise, AUR только `-git` и `nightly`.
- zoxide — extra 0.10.0 равен mise.

Удалить дубль mise (пакет pacman уже стоит):

- bat, btop, fd, ffmpeg, fzf, imagemagick, jq — версии в mise и pacman совпадают или различаются на патч.
- python 3.14 — core 3.14.8 уже стоит.

## Переводится на AUR

- herdr (`herdr-bin`) — в репозиториях нет, `herdr-bin` 0.9.5 равен upstream.
- hunk (`hunk-bin`) — в репозиториях нет, 0.24.1 равен upstream.
- oh-my-pi (`oh-my-pi-bin`) — в репозиториях нет, 18.13.3 равен upstream.
- oxker (`oxker-bin`) — в репозиториях нет, 0.13.4 равен upstream.
- OpenSpec (`openspec`) — в репозиториях нет, AUR 1.15.0 новее установленной 1.10.0.
- python 3.12 (`python312`) — в репозиториях нет, 3.12.16 новее установленных 3.12.14 и 3.12.15.
- py-spy (`py-spy-bin`) — в репозиториях нет, 0.4.2 равен установленной.
- wezterm (`wezterm-nightly-bin`, запасной вариант `wezterm-git`) — репозиторий отстаёт на два года (20240203 против сборки 20260805); релизных пакетов AUR нет, поэтому допустим nightly.
- yarn 4 (`yarn-berry`) — в репозиториях нет; конфликтует с `yarn` из extra, из двух ставится один.
- AmneziaVPN (`amneziavpn-bin`) — в репозиториях нет, 5.0.3.0 равен upstream.
- Handy (`handy-bin`) — в репозиториях нет, 0.9.8 равен последнему AppImage.
- LM Studio (`lmstudio-bin`) — в репозиториях нет, AUR 0.4.26 новее AppImage 0.4.23.
- Vial (`vial-appimage`) — в репозиториях нет, 0.7.5 равен AppImage.

Уже стоят из AUR:

- docker-rootless-extras — версия равна AUR, оставить.
- voxtype — установлена 0.7.5, AUR 1.1.1, обновить.
- xdg-desktop-portal-termfilechooser — установлена 1.4.3, AUR 1.5.0, обновить.
- yuckls-git — пакета без `-git` нет, оставить.

## Остаётся вне пакетов

- eww-daemon — свой проект `~/work/pets/eww-daemon`, нигде нет.
- workspaced — свой проект `~/work/pets/workspaced`, нигде нет.
- node 20, 22, 24 — закреплённые версии для проектов; пакеты `nodejs-lts-*` конфликтуют с `nodejs`.
- poetry 1.8.2, 1.8.3 и pipx:poetry 1.8.3 — закреплённые старые версии, в репозиториях только 2.5.1.
- Интерпретаторы uv python 3.11, 3.14, 3.14t — кэш самого uv.

## Итог

Переводится на pacman: 33 программы и 8 дублей mise для удаления.
Переводится на AUR: 13 программ; ещё 4 уже стоят из AUR (2 обновить,
2 оставить). Остаётся вне пакетов: 5 позиций (2 своих проекта и 3 набора
закреплённых версий).
