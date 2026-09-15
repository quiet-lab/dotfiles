// Запуск программ из панели. Панель работает юнитом systemd, и процессы, запущенные
// напрямую, попадают в её cgroup: остановка или перезапуск юнита убивала бы их.
// systemd-run --user --scope помещает каждую программу в собственную область вне юнита.
pragma Singleton
import Quickshell
import QtQuick

QtObject {
    function detached(args, cwd) {
        const cmd = ["systemd-run", "--user", "--scope", "--collect", "--quiet", "--"].concat(args);
        if (cwd) Quickshell.execDetached({ command: cmd, workingDirectory: cwd });
        else Quickshell.execDetached(cmd);
    }
}
