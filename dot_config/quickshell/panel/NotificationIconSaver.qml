// Сохранение картинки уведомления в файл (спецификация qs-notifications,
// требование «Значок, картинка и разметка тела»). Картинку из подсказки
// `image-data` модуль Quickshell отдаёт ссылкой своего поставщика изображений
// (`image://…`), а сами байты из подсказок убирает: такая ссылка живёт ровно
// столько, сколько живёт объект уведомления, и в файл состояния её записать
// нельзя. Поэтому картинка перерисовывается в файл каталога состояния панели,
// и запись истории хранит путь к нему.
//
// Единственный доступный способ получить пиксели в QML — `grabToImage`,
// а он требует, чтобы элемент лежал в окне и отрисовывался. Поэтому элемент
// помещается в окно панели и остаётся почти прозрачным: при нулевой
// непрозрачности сцена его не рисует и снимок не удаётся.
import QtQuick

Item {
    id: saver
    width: 64
    height: 64
    opacity: 0.004
    z: -1

    // Очередь заданий { url, path, done }: снимок делается по одному.
    property var queue: []
    property var current: null

    function save(url, path, done) {
        saver.queue.push({ url: url, path: path, done: done });
        saver.step();
    }

    function step() {
        if (saver.current || saver.queue.length === 0) return;
        saver.current = saver.queue.shift();
        image.source = saver.current.url;
    }

    function finish(ok) {
        const job = saver.current;
        saver.current = null;
        image.source = "";
        if (job && job.done) job.done(ok);
        Qt.callLater(saver.step);
    }

    Image {
        id: image
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(64, 64)
        asynchronous: false
        cache: false
        onStatusChanged: {
            if (!saver.current) return;
            if (status === Image.Error) { saver.finish(false); return; }
            if (status !== Image.Ready) return;
            const path = saver.current.path;
            const ok = saver.grabToImage(result => {
                saver.finish(result.saveToFile(path));
            }, Qt.size(64, 64));
            if (!ok) saver.finish(false);
        }
    }
}
