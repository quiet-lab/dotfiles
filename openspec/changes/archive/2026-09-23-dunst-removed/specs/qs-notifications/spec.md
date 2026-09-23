## MODIFIED Requirements

### Requirement: Сервер уведомлений сессии
Панель Quickshell MUST быть единственным сервером уведомлений сессии: она
MUST занимать имя D-Bus `org.freedesktop.Notifications` и обслуживать вызовы
спецификации Desktop Notifications. Отдельный демон уведомлений (dunst)
в системе не установлен и MUST NOT устанавливаться и запускаться.

Сервер MUST объявлять клиентам возможности `persistence`, `body`,
`body-markup`, `actions` и `icon-static` и MUST NOT объявлять
`body-hyperlinks`, `body-images`, `action-icons` и `inline-reply`. Показанные
уведомления MUST переживать перезапуск конфигурации панели
(`keepOnReload`): перечитывание QML не закрывает показанные уведомления.

Уведомление MUST оставаться открытым для приложения, пока его запись живёт
в истории: только так у записи сохраняются действие по умолчанию и кнопки
действий. Закрытым для приложения уведомление MUST становиться, когда запись
уходит из истории.

#### Scenario: Имя D-Bus у панели
- **WHEN** сессия запущена и панель работает
- **THEN** `busctl --user list` показывает владельцем `org.freedesktop.Notifications` процесс `qs`, а пакета dunst в системе нет (`pacman -Q dunst` не находит пакет, `systemctl --user status dunst.service` отвечает «could not be found»)

#### Scenario: Уведомление доходит до панели
- **WHEN** выполнено `notify-send "Заголовок" "Текст"`
- **THEN** на экране появляется карточка панели с этим заголовком и текстом

#### Scenario: Возможности сервера
- **WHEN** клиент запрашивает `GetCapabilities`
- **THEN** в ответе есть `persistence`, `body`, `body-markup`, `actions` и `icon-static` и нет `body-hyperlinks`, `body-images`, `action-icons` и `inline-reply`
