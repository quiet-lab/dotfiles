// Сервер уведомлений панели (спецификация qs-notifications): панель занимает
// имя D-Bus org.freedesktop.Notifications вместо dunst, ведёт стопку показанных
// уведомлений, историю и режим «не беспокоить». Карточка — NotificationCard.qml,
// стопка — NotificationStack.qml, окно истории — NotificationHistoryPopup.qml,
// плитка колонки — tiles/Notifications.qml.
pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

QtObject {
    id: svc

    // Предел истории: столько записей хватает, чтобы разобрать пропущенное
    // за день, а список остаётся обозримым в одном окне (design D4).
    readonly property int historyLimit: 50
    // Подсказки, задающие метку стопки: уведомление с уже занятой меткой
    // занимает место прежнего (design D12). Первая — та, которой пользуются
    // скрипты громкости, яркости и снимков экрана.
    readonly property var stackTagHints: [
        "synchronous", "private-synchronous",
        "x-dunst-stack-tag", "x-canonical-private-synchronous"
    ]

    // Показанные уведомления — модель самого сервера: он держит принятые
    // уведомления в порядке появления, новые в конце. Столбик рисует модель
    // сверху вниз, поэтому новая карточка встаёт снизу, а прежние поднимаются
    // выше. Модель нужна именно как модель, а не как список: она добавляет
    // и убирает по одному уведомлению, и карточки остальных не пересоздаются
    // (иначе закрытие одного уведомления обрывало бы растворение соседних).
    readonly property var model: svc.server.trackedNotifications
    readonly property var shown: svc.model ? svc.model.values : []
    // История: записи { time, appName, summary, body, icon, urgency }.
    property var history: []
    property bool dnd: false

    // Просьба открыть или закрыть окно истории: само окно живёт в плитке.
    signal historyToggleRequested()
    // Просьба закрыть уведомление: карточка растворяется и закрывает его,
    // когда анимация кончилась. action — действие, которое нужно выполнить
    // вместо простого закрытия, или null; expire — закрыть по истечении
    // (уйдёт в историю), а не как закрытое пользователем.
    signal closeRequested(var notification, var action, var expire)

    // --- Разбор уведомления ---

    // Метка стопки уведомления или пустая строка.
    function stackTag(n) {
        const hints = n.hints;
        if (!hints) return "";
        for (const key of svc.stackTagHints) {
            const v = hints[key];
            if (v !== undefined && v !== null && String(v) !== "") return String(v);
        }
        return "";
    }

    // Источник значка: картинка из подсказок уведомления, иначе значок
    // приложения (имя из темы значков, путь к файлу или готовый URL).
    function iconSource(n) {
        if (n.image) return n.image;
        const icon = n.appIcon;
        if (!icon) return "";
        if (icon.startsWith("/")) return "file://" + icon;
        if (icon.indexOf("://") > 0) return icon;
        return Quickshell.hasThemeIcon(icon) ? Quickshell.iconPath(icon) : "";
    }

    // Процент для полосы заполнения или −1, если подсказки value нет.
    function progress(n) {
        const hints = n.hints;
        if (!hints || hints["value"] === undefined || hints["value"] === null) return -1;
        const v = Number(hints["value"]);
        if (isNaN(v)) return -1;
        return Math.max(0, Math.min(100, Math.round(v)));
    }

    // Тело уведомления для Text.StyledText: перевод строки приходит и
    // настоящим символом, и последовательностью из обратной косой черты
    // и буквы n — так его шлют скрипты сессии, и так же его понимал dunst.
    function markup(text) {
        if (!text) return "";
        return text.replace(/\\n/g, "<br/>").replace(/\n/g, "<br/>");
    }

    // Действие по умолчанию: с идентификатором default, иначе первое из списка.
    function defaultAction(n) {
        const actions = n.actions;
        if (!actions || actions.length === 0) return null;
        for (const a of actions) if (a.identifier === "default") return a;
        return actions[0];
    }

    // Кнопки карточки: все действия, кроме действия по умолчанию — оно
    // выполняется кликом по самой карточке, а не отдельной кнопкой.
    function buttons(n) {
        const out = [];
        const actions = n.actions;
        if (!actions) return out;
        for (const a of actions) if (a.identifier !== "default") out.push(a);
        return out;
    }

    // --- Приём и закрытие ---

    function handle(n) {
        // Режим «не беспокоить»: обычное уведомление на экран не выходит
        // и сразу становится записью истории, critical показывается (design D7).
        // Уведомление, у которого tracked остался выключенным, сервер закрывает
        // сам и сообщает об этом клиенту.
        if (svc.dnd && n.urgency !== NotificationUrgency.Critical) {
            svc.remember(n);
            return;
        }

        // Замена по метке стопки: прежнее уведомление с той же меткой
        // закрывается как закрытое пользователем и в историю не идёт.
        const tag = svc.stackTag(n);
        if (tag !== "") {
            for (const other of svc.shown) {
                if (other !== n && svc.stackTag(other) === tag) { other.dismiss(); break; }
            }
        }

        n.tracked = true;
        n.closed.connect(reason => svc.finished(n, reason));
    }

    function finished(n, reason) {
        // Закрытое пользователем в историю не попадает (design D3): он его
        // уже видел и убрал сам.
        if (reason === NotificationCloseReason.Dismissed) return;
        svc.remember(n);
    }

    function remember(n) {
        // Клиент прямо просит не сохранять уведомление.
        if (n.transient) return;
        const list = svc.history.slice();
        list.unshift({
            time: new Date(),
            appName: n.appName || "",
            summary: n.summary || "",
            body: n.body || "",
            icon: svc.iconSource(n),
            urgency: n.urgency
        });
        if (list.length > svc.historyLimit) list.length = svc.historyLimit;
        svc.history = list;
    }

    // --- Команды ---

    function requestClose(n, action) { svc.closeRequested(n, action || null, false); }
    // Уведомление вытеснено с экрана: растворяется так же, но уходит в историю.
    function requestExpire(n) { svc.closeRequested(n, null, true); }
    // Закрыть последнее пришедшее уведомление — самое нижнее в столбике.
    function closeNewest() {
        if (svc.shown.length > 0) svc.requestClose(svc.shown[svc.shown.length - 1], null);
    }
    function closeAll() { for (const n of svc.shown.slice()) svc.requestClose(n, null); }
    // Самое старое видимое уведомление — верхнее в столбике — закрывается
    // вместе с выполнением своего действия по умолчанию, то есть ровно так же,
    // как по клику мышью по нему.
    function dismissOldest() {
        if (svc.shown.length === 0) return;
        const n = svc.shown[0];
        svc.requestClose(n, svc.defaultAction(n));
    }
    function clearHistory() { svc.history = []; }
    function forget(index) {
        const list = svc.history.slice();
        list.splice(index, 1);
        svc.history = list;
    }
    function toggleDnd() {
        svc.dnd = !svc.dnd;
        svc.dndFile.setText(svc.dnd ? "1\n" : "0\n");
    }

    // --- Состояние режима «не беспокоить» на диске (design D6) ---

    readonly property string dndPath: Quickshell.statePath("notifications-dnd")

    // Каталог состояния панели создаёт сама панель: запись в несуществующий
    // каталог не удалась бы. Режим переключают уже после старта, так что
    // каталог к этому моменту готов.
    property Process stateDir: Process {
        command: ["mkdir", "-p", svc.dndPath.substring(0, svc.dndPath.lastIndexOf("/"))]
        running: true
    }

    property FileView dndFile: FileView {
        path: svc.dndPath
        preload: true
        atomicWrites: true
        // Файла нет, пока режим ни разу не включали, — это не ошибка.
        printErrors: false
        onLoaded: svc.dnd = text().trim() === "1"
    }

    // --- Сервер ---

    property NotificationServer server: NotificationServer {
        // Перечитывание конфигурации панели не закрывает показанные уведомления:
        // сервер переносит их в новое поколение и присылает заново.
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        // Ссылки и картинки в теле не поддерживаются намеренно: тело рисует
        // Text.StyledText, который в сеть не ходит (design D10).
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: false
        onNotification: (n) => svc.handle(n)
    }

    // --- Управление с клавиатуры (design D13) ---
    // Вызов: qs -c panel ipc call notifications <функция>.
    property IpcHandler ipc: IpcHandler {
        target: "notifications"
        function close(): void { svc.closeNewest(); }
        function closeAll(): void { svc.closeAll(); }
        function dismissOldest(): void { svc.dismissOldest(); }
        function dnd(): void { svc.toggleDnd(); }
        function history(): void { svc.historyToggleRequested(); }
    }
}
