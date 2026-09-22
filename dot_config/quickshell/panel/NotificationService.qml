// Сервер уведомлений панели (спецификация qs-notifications): панель занимает
// имя D-Bus org.freedesktop.Notifications вместо dunst и ведёт историю
// уведомлений за последние сутки. У каждой записи есть состояние
// «просмотрено»/«не просмотрено»: на экране столбиком показываются только
// непросмотренные (NotificationStack.qml, карточка — NotificationCard.qml),
// вся история целиком — в окне от плитки (NotificationHistoryPopup.qml),
// плитка колонки — tiles/Notifications.qml.
//
// История и режим «не беспокоить» лежат в файле состояния панели и переживают
// её перезапуск. Живой объект уведомления в файл не попадает, поэтому
// у восстановленной записи действия по умолчанию нет.
pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

QtObject {
    id: svc

    // Запись живёт в истории сутки. Срок проверяется при обращении к истории,
    // а не по расписанию: таймеров в панели нет.
    readonly property int lifetimeMs: 24 * 60 * 60 * 1000
    // Предохранитель от лавины уведомлений: больше записей файл не хранит,
    // самые старые вытесняются даже внутри суток.
    readonly property int historyLimit: 200
    // Подсказки, задающие метку стопки: уведомление с уже занятой меткой
    // занимает место прежнего. Первая — та, которой пользуются скрипты
    // громкости, яркости и снимков экрана.
    readonly property var stackTagHints: [
        "synchronous", "private-synchronous",
        "x-dunst-stack-tag", "x-canonical-private-synchronous"
    ]

    // Все записи истории по времени, старые в начале.
    property var records: []
    property bool dnd: false
    property int nextKey: 1
    // Состояние прочитано с диска: до этого записывать файл нельзя.
    property bool ready: false

    // Что показывается на экране: непросмотренные записи, а в режиме
    // «не беспокоить» — только критические.
    readonly property var onScreen: (svc.records || []).filter(
        r => !r.seen && (!svc.dnd || r.urgency === NotificationUrgency.Critical))
    // Счётчик плитки: непросмотренные целиком, включая скрытые режимом.
    readonly property int unseen: (svc.records || []).filter(r => !r.seen).length
    // История для окна: новые записи сверху.
    readonly property var newestFirst: (svc.records || []).slice().reverse()

    // Просьба открыть или закрыть окно истории: само окно живёт в плитке.
    signal historyToggleRequested()
    // Просьба карточке на экране растворяться и сделать после этого своё:
    // kind — "seen" (пометить просмотренным) или "act" (действие по умолчанию
    // и удаление из истории).
    signal cardActionRequested(var record, string kind)

    // --- Разбор уведомления ---

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
    function progressOf(n) {
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
        if (!n) return null;
        const actions = n.actions;
        if (!actions || actions.length === 0) return null;
        for (const a of actions) if (a.identifier === "default") return a;
        return actions[0];
    }

    // Кнопки карточки: все действия, кроме действия по умолчанию — оно
    // выполняется правым кликом по самой карточке.
    function buttons(n) {
        const out = [];
        if (!n) return out;
        const actions = n.actions;
        if (!actions) return out;
        for (const a of actions) if (a.identifier !== "default") out.push(a);
        return out;
    }

    // --- Приём уведомлений ---

    function byNotification(n) {
        for (const r of svc.records) if (r.notification === n) return r;
        return null;
    }

    function handle(n) {
        svc.prune();

        // Перечитывание конфигурации панели: сервер присылает прежние объекты
        // заново, записи для них уже есть — их надо только снова удержать.
        const known = svc.byNotification(n);
        if (known) { n.tracked = true; return; }

        // Уведомление удерживается, пока запись жива: только так у неё
        // остаётся действие по умолчанию и кнопки действий.
        n.tracked = true;

        // Замена по метке стопки: прежняя запись с той же меткой уходит
        // из истории целиком, иначе одних уведомлений громкости в ней
        // накопились бы десятки.
        const tag = svc.stackTag(n);
        if (tag !== "") {
            for (const r of svc.records) {
                if (r.tag === tag) { svc.forget(r); break; }
            }
        }

        const rec = svc.recordComponent.createObject(svc, {
            key: svc.nextKey,
            time: Date.now(),
            tag: tag,
            appName: n.appName || "",
            summary: n.summary || "",
            body: n.body || "",
            icon: svc.iconSource(n),
            urgency: n.urgency,
            progress: svc.progressOf(n),
            seen: false,
            notification: n
        });
        svc.nextKey += 1;

        // Уведомление закрыто приложением или его действием: запись остаётся
        // в истории, но живого объекта у неё больше нет, а значит нет
        // и действия по умолчанию.
        n.closed.connect(() => { rec.notification = null; });
        // Замена по replaces_id: модуль обновляет прежний объект и сигнал
        // notification не повторяет, поэтому за содержимым следят сигналы
        // самих свойств. Обновлённое уведомление снова считается
        // непросмотренным и возвращается на экран.
        const refresh = () => svc.refresh(rec);
        n.summaryChanged.connect(refresh);
        n.bodyChanged.connect(refresh);
        n.hintsChanged.connect(refresh);
        n.appIconChanged.connect(refresh);

        svc.records = svc.records.concat([rec]);
        svc.save();
    }

    function refresh(rec) {
        const n = rec.notification;
        if (!n) return;
        rec.summary = n.summary || "";
        rec.body = n.body || "";
        rec.icon = svc.iconSource(n);
        rec.progress = svc.progressOf(n);
        rec.urgency = n.urgency;
        rec.seen = false;
        svc.save();
    }

    // --- Состояния записей ---

    function markSeen(rec) {
        if (!rec || rec.seen) return;
        rec.seen = true;
        svc.save();
    }
    function markUnseen(rec) {
        if (!rec || !rec.seen) return;
        rec.seen = false;
        svc.save();
    }
    function toggleSeen(rec) {
        if (!rec) return;
        if (rec.seen) svc.markUnseen(rec);
        else svc.requestSeen(rec);
    }
    function markAllSeen() {
        for (const r of svc.records) r.seen = true;
        svc.save();
    }
    // Вернуть на экран последнее просмотренное уведомление.
    function restoreLast() {
        for (let i = svc.records.length - 1; i >= 0; --i) {
            if (svc.records[i].seen) { svc.markUnseen(svc.records[i]); return; }
        }
    }

    // Действие по умолчанию и удаление записи из истории.
    function act(rec) {
        if (!rec) return;
        const action = svc.defaultAction(rec.notification);
        // invoke() сообщает клиенту о выборе действия и закрывает уведомление
        // само, если клиент не просил оставить его открытым.
        if (action) action.invoke();
        svc.forget(rec);
    }

    // Просьбы, приходящие от кликов и клавиш: если запись сейчас на экране,
    // сперва растворяется её карточка, и только потом меняется состояние —
    // так соседние карточки не двигаются во время растворения.
    function requestSeen(rec) {
        if (!rec) return;
        if (svc.onScreen.indexOf(rec) >= 0) svc.cardActionRequested(rec, "seen");
        else svc.markSeen(rec);
    }
    function requestAct(rec) {
        if (!rec) return;
        if (svc.onScreen.indexOf(rec) >= 0) svc.cardActionRequested(rec, "act");
        else svc.act(rec);
    }

    // --- История ---

    // Убрать запись из истории целиком и закрыть её живое уведомление.
    function forget(rec) {
        if (!rec) return;
        svc.records = svc.records.filter(r => r !== rec);
        svc.discard(rec);
        svc.save();
    }
    function clearHistory() {
        const old = svc.records;
        svc.records = [];
        for (const r of old) svc.discard(r);
        svc.save();
    }

    // Уничтожение записи: живому уведомлению сообщается, что оно закрыто.
    function discard(rec) {
        const n = rec.notification;
        rec.notification = null;
        if (n) n.dismiss();
        rec.destroy();
    }

    // Срок жизни записи. Проверяется при обращении к истории — приходе нового
    // уведомления, открытии окна истории, переключении режима и при старте
    // панели, — а не по расписанию: таймеров в панели нет.
    function prune() {
        if (!svc.ready) return;
        const edge = Date.now() - svc.lifetimeMs;
        let list = svc.records.filter(r => r.time >= edge);
        if (list.length > svc.historyLimit) list = list.slice(list.length - svc.historyLimit);
        if (list.length === svc.records.length) return;
        const gone = svc.records.filter(r => list.indexOf(r) < 0);
        svc.records = list;
        for (const r of gone) svc.discard(r);
        svc.save();
    }

    function toggleDnd() {
        svc.dnd = !svc.dnd;
        svc.prune();
        svc.save();
    }

    // --- Запись состояния (design D6) ---

    readonly property string statePath: Quickshell.statePath("notifications.json")

    // Каталог состояния панель создаёт сама: запись в несуществующий каталог
    // не удалась бы.
    property Process stateDir: Process {
        command: ["mkdir", "-p", svc.statePath.substring(0, svc.statePath.lastIndexOf("/"))]
        running: true
    }

    property FileView stateFile: FileView {
        path: svc.statePath
        preload: true
        atomicWrites: true
        // Файла нет, пока панель ни разу не сохраняла состояние, — не ошибка.
        printErrors: false
        onLoaded: svc.restore(text())
        onLoadFailed: { svc.ready = true; }
    }

    function restore(text) {
        try {
            const data = JSON.parse(text);
            svc.dnd = data.dnd === true;
            svc.nextKey = data.nextKey || 1;
            const list = [];
            for (const r of (data.records || [])) {
                list.push(svc.recordComponent.createObject(svc, {
                    key: r.key || 0,
                    time: r.time || 0,
                    tag: r.tag || "",
                    appName: r.appName || "",
                    summary: r.summary || "",
                    body: r.body || "",
                    icon: r.icon || "",
                    urgency: r.urgency === undefined ? 1 : r.urgency,
                    progress: r.progress === undefined ? -1 : r.progress,
                    seen: r.seen === true,
                    notification: null
                }));
            }
            svc.records = list;
        } catch (e) {
            console.warn("уведомления: состояние не прочитано:", e);
        }
        svc.ready = true;
        svc.prune();
    }

    function save() {
        if (!svc.ready) return;
        const data = {
            dnd: svc.dnd,
            nextKey: svc.nextKey,
            records: svc.records.map(r => ({
                key: r.key, time: r.time, tag: r.tag, appName: r.appName,
                summary: r.summary, body: r.body, icon: r.icon,
                urgency: r.urgency, progress: r.progress, seen: r.seen
            }))
        };
        svc.stateFile.setText(JSON.stringify(data));
    }

    // Запись истории. Собственный объект, а не поле в массиве: у него есть
    // сигналы об изменении свойств, поэтому карточка и строка истории сами
    // перерисовываются, когда запись меняется.
    property Component recordComponent: Component {
        QtObject {
            property int key: 0
            property real time: 0
            property string tag: ""
            property string appName: ""
            property string summary: ""
            property string body: ""
            property string icon: ""
            property int urgency: 1
            property int progress: -1
            property bool seen: false
            // Живой объект уведомления или null, если его уже нет.
            property var notification: null
        }
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
        // Пометить просмотренным последнее пришедшее уведомление столбика.
        function close(): void {
            const list = svc.onScreen;
            if (list.length > 0) svc.requestSeen(list[list.length - 1]);
        }
        // Пометить просмотренными все.
        function closeAll(): void { svc.markAllSeen(); }
        // Очистить историю целиком.
        function clear(): void { svc.clearHistory(); }
        // Верхнее (самое старое) уведомление столбика: пометить просмотренным.
        function dismissOldest(): void {
            const list = svc.onScreen;
            if (list.length > 0) svc.requestSeen(list[0]);
        }
        // Верхнее уведомление: действие по умолчанию и удаление из истории.
        function invokeOldest(): void {
            const list = svc.onScreen;
            if (list.length > 0) svc.requestAct(list[0]);
        }
        // Вернуть на экран последнее просмотренное уведомление.
        function restore(): void { svc.restoreLast(); }
        function dnd(): void { svc.toggleDnd(); }
        function history(): void { svc.historyToggleRequested(); }
    }
}
