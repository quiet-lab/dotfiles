//! Запись таблицы клавиш (D6, таблица «Запись таблицы»).

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Entry {
    /// Нормализованная клавиша (вид ble.sh).
    pub key: String,
    /// Короткое описание: что делает, в нескольких словах.
    pub desc: String,
    /// Полный текст описания из источника.
    #[serde(default)]
    pub desc_full: String,
    #[serde(default)]
    pub group: String,
    #[serde(default)]
    pub origin: String,
    /// Имя виджета, функции или действия.
    #[serde(default)]
    pub action: String,
    /// Откуда запись: `manifest:<файл>`, имя манифеста-извлекателя, `user`.
    #[serde(default)]
    pub source: String,
    /// Исходный фрагмент источника.
    #[serde(default)]
    pub raw: String,
}

impl Entry {
    /// Текст ячейки: короткое описание, иначе полное, иначе действие.
    pub fn shown_desc(&self) -> &str {
        if !self.desc.is_empty() {
            &self.desc
        } else if !self.desc_full.is_empty() {
            &self.desc_full
        } else {
            &self.action
        }
    }
}
