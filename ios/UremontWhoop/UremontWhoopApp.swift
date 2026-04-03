/// Точка входа iOS-приложения: создаёт ObdConnectionManager и внедряет через environmentObject.
///
/// Файл содержит `@main` структуру `UremontWhoopApp` — единственную точку входа
/// iOS-приложения OBD2-диагностики UREMONT Whoop.
///
/// Обязанности:
/// - Создание и хранение экземпляра `ObdConnectionManager` как `@StateObject`
///   (живёт всё время жизни приложения)
/// - Внедрение менеджера в иерархию View через `.environmentObject`
///   для доступа из любого экрана
/// - Принудительная установка тёмной темы (`.preferredColorScheme(.dark)`)
/// - Заливка фона `Brand.bg` под safe area
///
/// `AppRoot` — корневой View с TabView/PageView для навигации между экранами
/// Connect, Ошибки и Датчики.
import SwiftUI

/// Главная структура приложения UREMONT Whoop (iOS).
///
/// Использует `@StateObject` для `ObdConnectionManager`, чтобы экземпляр
/// создавался единожды при запуске и не пересоздавался при перерисовке View.
/// Менеджер отвечает за TCP-соединение с Wi-Fi OBD2-адаптером,
/// отправку ELM327/OBD2 команд и парсинг ответов.
@main
struct UremontWhoopApp: App {
    /// Единственный экземпляр менеджера OBD2-подключения.
    /// Создаётся при запуске приложения и живёт до его завершения.
    /// Внедряется в иерархию View как `environmentObject` для доступа
    /// из `AppRoot`, `ConnectPage`, `ErrorsPage`, `SensorsPage` и других экранов.
    @StateObject private var obdManager = ObdConnectionManager()

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environmentObject(obdManager)
                .preferredColorScheme(.dark)
                .background(Brand.bg.ignoresSafeArea())
        }
    }
}
