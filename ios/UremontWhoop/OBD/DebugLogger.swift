/// Синглтон-логгер: кольцевой буфер 800 записей, уровни d/i/w/e, вывод в os_log.
///
/// Файл содержит:
/// - `LogLevel` — уровни логирования (debug, info, warn, error)
/// - `LogEntry` — одна запись лога (время, уровень, тег, сообщение)
/// - `DebugLogger` — синглтон для записи и чтения логов
///
/// ## Принцип работы
/// Каждое сообщение дублируется в два канала:
/// 1. **Кольцевой буфер** в памяти (максимум 800 записей) — для отображения
///    в дебаг-консоли внутри `SettingsSheet`
/// 2. **os_log** — для просмотра в Console.app / Xcode
///
/// ## Потокобезопасность
/// Все операции с буфером защищены `NSLock`.
///
/// ## Использование
/// ```swift
/// DebugLogger.shared.d("OBD", "Отправлен AT Z")
/// DebugLogger.shared.e("BLE", "Потеряно соединение", error)
/// ```
import Foundation
import os.log

// MARK: - LogLevel

/// Уровень важности лог-сообщения.
///
/// Определяет:
/// - Однобуквенный префикс для текстового вывода (`letter`)
/// - Тип `OSLogType` для системного логирования (`osLogType`)
///
/// Реализует `Comparable` для фильтрации по минимальному уровню.
enum LogLevel: Int, Comparable, CaseIterable {
    /// Отладочное сообщение (самый низкий приоритет)
    case debug = 0
    /// Информационное сообщение
    case info  = 1
    /// Предупреждение (нештатная, но обрабатываемая ситуация)
    case warn  = 2
    /// Ошибка (критическая проблема)
    case error = 3

    /// Однобуквенное обозначение уровня: D, I, W, E.
    ///
    /// Используется в текстовом форматировании лога: `«HH:mm:ss.SSS D/Tag: сообщение»`.
    var letter: String {
        switch self {
        case .debug: return "D"
        case .info:  return "I"
        case .warn:  return "W"
        case .error: return "E"
        }
    }

    /// Маппинг на системный `OSLogType` для вывода через `os_log`.
    ///
    /// - debug → `.debug` (не сохраняется по умолчанию)
    /// - info → `.info`
    /// - warn → `.default` (всегда сохраняется)
    /// - error → `.error` (всегда сохраняется, подсвечивается в Console.app)
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info:  return .info
        case .warn:  return .default
        case .error: return .error
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - LogEntry

/// Одна запись в кольцевом буфере логов.
///
/// Хранит метаданные (время, уровень, тег) и текст сообщения.
/// Используется для отображения в дебаг-консоли `SettingsSheet`.
struct LogEntry {
    /// Unix-время записи (секунды с 1970-01-01, с миллисекундами)
    let timeMs: TimeInterval
    /// Уровень важности сообщения
    let level: LogLevel
    /// Тег-источник (например, «OBD», «BLE», «SessionRepo»)
    let tag: String
    /// Текст сообщения
    let message: String
}

// MARK: - DebugLogger

/// Основной логгер приложения — синглтон с кольцевым буфером.
///
/// ## Паттерн
/// Синглтон (`shared`). Приватный инициализатор резервирует память под буфер.
///
/// ## Кольцевой буфер
/// Максимум 800 записей. При переполнении удаляются самые старые элементы
/// из начала массива (`removeFirst`).
///
/// ## Дублирование в os_log
/// Каждое сообщение параллельно отправляется в `os_log` с категорией «OBD»
/// и подсистемой из `Bundle.main.bundleIdentifier`. Это позволяет просматривать
/// логи в Xcode Console и Console.app.
///
/// ## Удобные методы
/// - `d(_:_:)` — debug
/// - `i(_:_:)` — info
/// - `w(_:_:)` — warn
/// - `e(_:_:)` — error
/// - `e(_:_:_:)` — error с объектом `Error`
final class DebugLogger {

    /// Единственный экземпляр логгера (синглтон)
    static let shared = DebugLogger()

    /// Максимальный размер кольцевого буфера
    private static let maxEntries = 800

    /// Блокировка для потокобезопасного доступа к буферу
    private let lock = NSLock()
    /// Кольцевой буфер лог-записей (новые элементы добавляются в конец)
    private var buffer: [LogEntry] = []
    /// Экземпляр `OSLog` для вывода через системный логгер (подсистема: bundleId, категория: «OBD»)
    private let osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.uremont.whoop", category: "OBD")

    /// Форматтер времени для текстового вывода (формат «HH:mm:ss.SSS», POSIX-локаль)
    private lazy var timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    private init() {
        buffer.reserveCapacity(Self.maxEntries)
    }

    // MARK: - Public convenience methods

    /// Логирует сообщение уровня **debug**.
    ///
    /// - Parameters:
    ///   - tag: Тег-источник (например, «OBD», «BLE»)
    ///   - message: Текст сообщения
    func d(_ tag: String, _ message: String) {
        log(level: .debug, tag: tag, message: message)
    }

    /// Логирует сообщение уровня **info**.
    ///
    /// - Parameters:
    ///   - tag: Тег-источник
    ///   - message: Текст сообщения
    func i(_ tag: String, _ message: String) {
        log(level: .info, tag: tag, message: message)
    }

    /// Логирует сообщение уровня **warn** (предупреждение).
    ///
    /// - Parameters:
    ///   - tag: Тег-источник
    ///   - message: Текст сообщения
    func w(_ tag: String, _ message: String) {
        log(level: .warn, tag: tag, message: message)
    }

    /// Логирует сообщение уровня **error**.
    ///
    /// - Parameters:
    ///   - tag: Тег-источник
    ///   - message: Текст сообщения
    func e(_ tag: String, _ message: String) {
        log(level: .error, tag: tag, message: message)
    }

    /// Логирует ошибку с приложенным объектом `Error`.
    ///
    /// Если `error` не nil, к сообщению дописывается `: localizedDescription`.
    ///
    /// - Parameters:
    ///   - tag: Тег-источник
    ///   - message: Текст сообщения
    ///   - error: Объект ошибки (опционально)
    func e(_ tag: String, _ message: String, _ error: Error?) {
        let full = error.map { "\(message): \($0.localizedDescription)" } ?? message
        log(level: .error, tag: tag, message: full)
    }

    // MARK: - Buffer access

    /// Потокобезопасная копия всех записей буфера.
    ///
    /// Возвращает снимок буфера на момент вызова (от старых к новым).
    /// Используется в `SettingsSheet` для отображения дебаг-консоли.
    var entries: [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return Array(buffer)
    }

    /// Текущее количество записей в буфере.
    var size: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    /// Очищает буфер, сохраняя зарезервированную память.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
    }

    // MARK: - Formatting

    /// Форматирует все записи буфера в единую строку для экспорта / отображения.
    ///
    /// Формат каждой строки: `HH:mm:ss.SSS L/Tag: сообщение\n`,
    /// где L — однобуквенный уровень (D/I/W/E).
    ///
    /// - Returns: Многострочная строка со всеми записями лога
    func formatAll() -> String {
        let snapshot = entries
        var result = ""
        result.reserveCapacity(snapshot.count * 60)

        for entry in snapshot {
            let date = Date(timeIntervalSince1970: entry.timeMs)
            let time = timeFormatter.string(from: date)
            result += "\(time) \(entry.level.letter)/\(entry.tag): \(entry.message)\n"
        }

        return result
    }

    // MARK: - Internal

    /// Основной метод записи лога.
    ///
    /// 1. Создаёт `LogEntry` с текущим временем
    /// 2. Дублирует сообщение в `os_log` с соответствующим `OSLogType`
    /// 3. Добавляет запись в кольцевой буфер; при переполнении удаляет
    ///    лишние элементы из начала массива
    ///
    /// - Parameters:
    ///   - level: Уровень важности
    ///   - tag: Тег-источник
    ///   - message: Текст сообщения
    private func log(level: LogLevel, tag: String, message: String) {
        let now = Date().timeIntervalSince1970

        let entry = LogEntry(timeMs: now, level: level, tag: tag, message: message)

        os_log("%{public}@/%{public}@: %{public}@",
               log: osLog, type: level.osLogType,
               level.letter, tag, message)

        lock.lock()
        buffer.append(entry)
        if buffer.count > Self.maxEntries {
            buffer.removeFirst(buffer.count - Self.maxEntries)
        }
        lock.unlock()
    }
}
