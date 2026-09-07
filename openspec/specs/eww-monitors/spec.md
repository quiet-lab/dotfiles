# eww-monitors Specification

## Purpose

Метрики системы: круговые шкалы загрузки CPU/RAM/GPU с температурной подсветкой и плитка дисков с полосами заполнения. Аппаратные допущения: CPU AMD (k10temp), GPU NVIDIA (nvidia-smi).

## Requirements

### Requirement: Загрузка CPU
Переменная `cpu` MUST вычисляться скриптом `widgets/gauges/scripts/cpu` как доля занятого времени по дельте `/proc/stat` за 1-секундный сэмпл, в процентах 0–100. Poll — каждые 3 секунды.

#### Scenario: Простой системы
- **WHEN** все ядра простаивают между сэмплами
- **THEN** значение близко к 0

### Requirement: Использование RAM
`ram` MUST считаться из `/proc/meminfo` как `(MemTotal − MemAvailable) / MemTotal × 100`. Рядом MUST отображаться общий объём `ramtotal` в ГиБ (`MemTotal / 1048576`, poll 1h).

#### Scenario: Точность
- **WHEN** MemAvailable = 0
- **THEN** шкала показывает 100%

### Requirement: Загрузка и температура GPU
`gpu` (poll 3s) — `nvidia-smi --query-gpu=utilization.gpu`; `gputemp` (poll 5s) — `--query-gpu=temperature.gpu`. Температура CPU — `sensors -u k10temp-pci-00c3`, Tctl, poll 5s.

#### Scenario: Отсутствие nvidia-smi
- **WHEN** утилита недоступна
- **THEN** переменная получает пустое/нулевое значение без падения eww

### Requirement: Температурные классы
Значения загрузки CPU/RAM/GPU и температур MUST маппиться в классы порогами: <50 → `t-low`, <75 → `t-mid`, <90 → `t-high`, иначе `t-crit`. Класс применяется к circular-progress (цвет дуги) и к подписи температуры. Цвета: t-low #39FF14, t-mid #EAFF00, t-high #FF9500, t-crit #FF073A. Имена на шкалах: CPU — красный #FF073A, RAM — синий #2E9FFF (+ белый total), GPU — зелёный #39FF14.

#### Scenario: Перегрев
- **WHEN** Tctl достигла 92
- **THEN** подпись температуры и дуга получают класс t-crit (#FF073A)

### Requirement: Круговые шкалы
Каждая шкала MUST быть circular-progress толщиной 10 внутри обёртки 70×70 по центру плитки 100×100, с подписью `${значение}%` в центре. Цвета дуг: CPU $green, RAM $cyan, GPU $magenta; фон дуги rgba(169,177,214,0.15).

#### Scenario: Центральная подпись
- **WHEN** cpu = 42
- **THEN** в центре круга виден текст «42%»

### Requirement: Плитка дисков
`widgets/disks/scripts/disks` (poll 30s) MUST строить строку на блок из `lsblk -J` (jq → TSV), исключая устройства loop*/zram*/ram* и записи со fstype swap. Метка — LABEL или имя устройства без префикса `/dev`.

Для смонтированных: имя, scale-полоса заполнения (use% из `df -Ph`, max 100), свободное место (колонка avail). Для несмонтированных: имя справа — тип файловой системы серым. При нечитаемом df: заполнение 0 и свободное место «?».

#### Scenario: Несмонтированный раздел ntfs
- **WHEN** lsblk вернул раздел с fstype=ntfs без mountpoint
- **THEN** строка показывает имя устройства и текст «ntfs» вместо полосы

#### Scenario: Скрытые служебные устройства
- **WHEN** в системе есть loop-устройства snap/zram
- **THEN** они не отображаются в списке
