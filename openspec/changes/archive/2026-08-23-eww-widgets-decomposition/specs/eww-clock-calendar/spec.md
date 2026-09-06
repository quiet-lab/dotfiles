## MODIFIED Requirements

### Requirement: Календарь
Встроенный виджет `calendar` MUST показывать текущий день (`cal-day` = `date '+%-d'`), месяц (`cal-month` через `widgets/clock/scripts/calendar`, переводящий номер месяца в 0-based — требование eww) и год (`cal-year`). Все три переменные опрашиваются раз в 10 часов.

#### Scenario: Месяц корректен
- **WHEN** календарь отрисовывается в августе (номер 8)
- **THEN** переменная cal-month равна 7 (0-based)
