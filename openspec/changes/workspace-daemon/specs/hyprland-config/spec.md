## MODIFIED Requirements

### Requirement: Поведение окон в переходный период
Новые окна MUST открываться плавающими, как в Openbox, с сохранением возможности перевести окно в мозаичный режим привязкой; расположение окон workspace по ячейкам задаёт демон workspaced (спецификация ws-daemon), собственная раскладка зон в конфиге Hyprland MUST NOT создаваться. Помимо `special:hidden` для окон, скрытых пользователем, сессия MUST допускать специальный стол `special:pool` для окон, припаркованных демоном; переключение на него привязкой MUST NOT предусматриваться. Приложения Xwayland MUST поддерживаться: Xwayland включён, окна GTK-программ, запущенных с `GDK_BACKEND=x11`, и приложений AppImage отображаются без чёрных областей.

#### Scenario: Новое окно плавающее
- **WHEN** из сессии запущен терминал
- **THEN** `hyprctl activewindow` показывает `floating: 1`

#### Scenario: Окно Xwayland
- **WHEN** из сессии запущена GTK-программа с `GDK_BACKEND=x11`
- **THEN** `hyprctl clients` показывает для неё `xwayland: 1`, окно отрисовано полностью

#### Scenario: Припаркованное окно
- **WHEN** демон перенёс окно на `special:pool`
- **THEN** `hyprctl clients -j` показывает у окна стол `special:pool`, окно не видно ни на одном столе, `hyprctl binds` не содержит привязки для показа `special:pool`
