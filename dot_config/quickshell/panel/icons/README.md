# Значки панели

| Файл | Источник | Лицензия |
|---|---|---|
| `amnezia.js` | символ логотипа `client/images/amneziaLogo.svg` репозитория [amnezia-vpn/amnezia-client](https://github.com/amnezia-vpn/amnezia-client), ветвь `dev`: 27 путей символа без надписи «AMNEZIA» и «YOUR OWN VPN», объединены в один путь одного цвета | GPL-3.0, как у клиента AmneziaVPN |

Значок `amn0` в трее (`tiles/Tray.qml`) рисует путь из `amnezia.js`
элементом Shape с цветом состояния из `Theme`. Штрих цвета заливки в 2 единицы логотипа
(около 0,5 px при 20 px) закрывает стыки между исходными путями и доводит
вес до глифа `axata`.
