/// Цветовая схема Brand — единая палитра для всех компонентов UI.
///
/// Все цвета точно совпадают с Android-версией приложения (MainActivity.kt).
/// Приложение использует только тёмную тему; светлая не предусмотрена.
///
/// Маппинг на Android: `BrandBlue`, `BrandBlueDark`, `BrandBg`, `BrandSurface`,
/// `BrandCard`, `BrandBorder`, `BrandText`, `BrandSubtext`, `BrandYellow`,
/// `BrandGreen`, `BrandRed`, `BrandOrange`.
import SwiftUI

// Exact match to Android brand colors

/// Перечисление-namespace с константами цветов бренда UREMONT.
///
/// Используется во всех View как единый источник цветов.
/// Все значения — статические свойства типа `Color`.
enum Brand {
    /// Основной акцентный синий (#227DF5) — кнопки, ссылки, бейджи, прогресс-бары
    static let blue = Color(red: 34/255, green: 125/255, blue: 245/255)      // #227DF5
    /// Тёмный вариант синего (#0063E4) — для состояния нажатия и градиентов
    static let blueDark = Color(red: 0/255, green: 99/255, blue: 228/255)    // #0063E4
    /// Основной фон приложения (#0D0D0F) — почти чёрный
    static let bg = Color(red: 13/255, green: 13/255, blue: 15/255)          // #0D0D0F
    /// Поверхность для sheet-презентаций и вложенных контейнеров (#18181B)
    static let surface = Color(red: 24/255, green: 24/255, blue: 27/255)     // #18181B
    /// Фон карточек (SensorCard, VehicleInfoCard и т.д.) (#242428)
    static let card = Color(red: 36/255, green: 36/255, blue: 40/255)        // #242428
    /// Цвет бордюров и разделителей (#36363C)
    static let border = Color(red: 54/255, green: 54/255, blue: 60/255)      // #36363C
    /// Основной цвет текста (#F0F0F5) — почти белый
    static let text = Color(red: 240/255, green: 240/255, blue: 245/255)     // #F0F0F5
    /// Вторичный текст, подсказки, подписи (#8E8E93) — серый
    static let subtext = Color(red: 142/255, green: 142/255, blue: 147/255)  // #8E8E93
    /// Жёлтый (#FCC900) — предупреждения, ожидающие ошибки, мониторы «Не готов»
    static let yellow = Color(red: 252/255, green: 201/255, blue: 0/255)     // #FCC900
    /// Зелёный (#34C759) — успех, подключено, «Ошибок нет», мониторы «Готов»
    static let green = Color(red: 52/255, green: 199/255, blue: 89/255)      // #34C759
    /// Красный (#FF3B30) — ошибки, постоянные DTC, «Нет соединения»
    static let red = Color(red: 255/255, green: 59/255, blue: 48/255)        // #FF3B30
    /// Оранжевый (#FF9500) — наличие ошибок в блоке ECU, границы карточек с ошибками
    static let orange = Color(red: 255/255, green: 149/255, blue: 0/255)     // #FF9500
}
