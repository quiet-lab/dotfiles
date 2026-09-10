## ADDED Requirements

### Requirement: Запуск сессии из lightdm
Сессия Hyprland MUST запускаться из lightdm записью `hyprland.desktop` из пакета (`/usr/bin/start-hyprland`), выбранной в greeter. Конфигурация lightdm (`user-session=openbox`) и сессия Openbox MUST NOT изменяться: обе сессии остаются доступными в меню greeter, а выбранная сессия запоминается lightdm для следующего входа. Две графические сессии одного пользователя MUST NOT работать одновременно: выход из Hyprland останавливает `graphical-session.target`. uwsm MUST NOT использоваться для запуска; запись `hyprland-uwsm.desktop` остаётся в меню как неиспользуемая.

#### Scenario: Вход в Hyprland через greeter
- **WHEN** в greeter lightdm выбрана сессия «Hyprland» и введён пароль
- **THEN** запускается Hyprland с конфигом из `~/.config/hypr/hyprland.lua`, `loginctl show-session` показывает `Type=wayland`, а `echo $XDG_SESSION_DESKTOP` в терминале сессии даёт `Hyprland`

#### Scenario: Выход в greeter
- **WHEN** пользователь завершает сессию Hyprland
- **THEN** lightdm показывает greeter, и вход в сессию Openbox выполняется как прежде, с дашбордом eww

#### Scenario: Возврат в Openbox
- **WHEN** в greeter выбрана сессия Openbox после работы в Hyprland
- **THEN** сессия Openbox запускается с автозапуском без изменений, `chezmoi status` не показывает расхождений

## MODIFIED Requirements

### Requirement: Окружение клиентов для NVIDIA
Сессия MUST передавать всем запускаемым из неё клиентам переменные окружения `LIBVA_DRIVER_NAME=nvidia`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `NVD_BACKEND=direct` и `ELECTRON_OZONE_PLATFORM_HINT=auto`; они задаются в управляемом chezmoi конфиге `dot_config/hypr/hyprland.lua`. Аппаратное декодирование видео через VA-API MUST работать в браузере, запущенном из сессии. Для Firefox это условие выполняется только при настройках профиля `media.hardware-video-decoding.force-enabled`, `media.rdd-ffmpeg.enabled`, `gfx.x11-egl.force-enabled`, `widget.dmabuf.force-enabled`, `media.av1.enabled=false` (Turing не декодирует AV1) и переменной окружения `MOZ_DISABLE_RDD_SANDBOX=1`; без них Firefox на NVIDIA VA-API не включает.

#### Scenario: Клиент видит переменные
- **WHEN** из сессии Hyprland запущен терминал
- **THEN** в его окружении присутствуют все четыре переменные с указанными значениями

#### Scenario: Видео декодируется аппаратно
- **WHEN** в браузере, запущенном из сессии, воспроизводится видео в H.264 или AV1
- **THEN** `nvidia-smi` показывает ненулевую загрузку декодера

## REMOVED Requirements

### Requirement: Изоляция пробной сессии
**Reason**: Пробный период закончен: сессия становится постоянной и запускается из lightdm, а не из текстовой консоли.
**Migration**: Требования к сохранности сессии Openbox и управляемых файлов перенесены в требование «Запуск сессии из lightdm»; переключение консолей между двумя одновременными сессиями больше не поддерживается.
