// Общий поток событий NetworkManager панели (спецификация qs-network,
// требование «Состояние из NetworkManager по событиям»): один процесс
// `nmcli monitor` на всю панель. Плитка сети и значок туннеля axata в трее
// подписываются на сигнал event() и по нему перечитывают своё состояние;
// второй поток не запускается.
pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Строка потока: в NetworkManager что-то изменилось.
    signal event()

    // Когда монитор запущен и сколько раз подряд он вышел сразу после запуска.
    property double started: 0
    property int failures: 0

    Process {
        id: monitor
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser {
            onRead: root.event()
        }
        onRunningChanged: if (running) root.started = Date.now()
        onExited: {
            // Монитор заканчивается, когда перезапускается NetworkManager: тем же
            // событием он и поднимается заново. Счёт подряд идущих мгновенных
            // выходов нужен на случай, когда nmcli не запускается вовсе (нет
            // NetworkManager, нет прав): иначе выход и запуск пошли бы по кругу.
            if (Date.now() - root.started >= 1000) root.failures = 0;
            else root.failures++;
            if (root.failures < 5) {
                monitor.running = true;
                // Пока монитор не работал, события могли пройти мимо: подписчики
                // перечитывают состояние сразу после его возврата.
                root.event();
            } else {
                console.warn("network: nmcli monitor не запускается, состояние сети больше не обновляется");
            }
        }
    }
}
