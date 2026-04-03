// ═══════════════════════════════════════════════════════════════════════════════
//  ObdConnectionManager.swift
//  UremontWhoop – iOS
// ═══════════════════════════════════════════════════════════════════════════════
//
/// Управляет Wi-Fi TCP-соединением с ELM327-адаптером и реализует клиентскую
/// часть протокола OBD2 (AT-команды, режимы 01–09) поверх NWConnection (Network.framework).
///
/// **Поддерживаемые режимы OBD2:**
///   - Mode 01 — текущие параметры (Live Data PIDs)
///   - Mode 02 — Freeze Frame — снимок параметров в момент появления ошибки
///   - Mode 03 — постоянные коды неисправностей (DTC)
///   - Mode 04 — сброс кодов и гашение Check Engine
///   - Mode 07 — ожидающие коды (Pending DTC)
///   - Mode 09 — VIN, CalID, CVN, маска PID, имя ЭБУ; на CAN — имя ЭБУ КПП (7E1)
///
/// **Совместимость:** любой автомобиль с OBD2 (1996+). Протокол (CAN / K-Line / ISO)
/// определяется автоматически командой ATSP0.
///
/// **Отличие от Android-версии (`ObdConnectionManager.kt`):**
///   - Android поддерживает и Bluetooth SPP (RFCOMM), и Wi-Fi TCP.
///   - iOS-версия — только Wi-Fi TCP, т.к. Apple запрещает классический Bluetooth (SPP)
///     на уровне ОС; BLE не подходит для ELM327 (нет стандартного профиля).
///   - Вместо `InputStream`/`OutputStream` используется `NWConnection` из Network.framework,
///     который не поддерживает синхронные блокирующие чтения — отсюда рекурсивный pump-паттерн
///     в `readUntilPrompt` и `drainInput`.
///   - Вместо Kotlin `Mutex` — кастомный `AsyncMutex` с `tryLock`/`withLock`.
///   - Вместо `InputStream.available()` + `skip()` для drainInput — таймер + pump.

@preconcurrency import Foundation
import Network
import Combine

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DebugLogger Helpers
// ═══════════════════════════════════════════════════════════════════════════════

/// Тег для фильтрации логов этого модуля в DebugLogger-консоли.
private let TAG = "ObdConnection"

/// Псевдонимы для краткости: все важные события идут в DebugLogger-консоль приложения.
/// Уровни совпадают с Android-версией (d/i/w/e) для единообразия логов.
private func dbg(_ msg: String)                    { DebugLogger.shared.d(TAG, msg) }
private func info(_ msg: String)                   { DebugLogger.shared.i(TAG, msg) }
private func warn(_ msg: String)                   { DebugLogger.shared.w(TAG, msg) }
private func err(_ msg: String, _ e: Error? = nil) { DebugLogger.shared.e(TAG, msg, e) }

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - String Extension
// ═══════════════════════════════════════════════════════════════════════════════

private extension String {
    /// Удаляет пробелы, переносы строк и CR, переводит в верхний регистр.
    /// Применяется повсеместно перед разбором hex-данных от ELM327.
    func cleanObd() -> String {
        replacingOccurrences(of: "[\\r\\n\\s]", with: "", options: .regularExpression).uppercased()
    }
}

/// Первое вхождение `marker` (например `4121`) + 4 hex-цифры данных Mode 01 → uint16 (ст. байт первый).
private func parseMode01TwoByteFromCleaned(_ clean: String, marker: String) -> Int? {
    let escaped = NSRegularExpression.escapedPattern(for: marker)
    guard let re = try? NSRegularExpression(pattern: escaped + "([0-9A-F]{4})") else { return nil }
    let full = NSRange(clean.startIndex..., in: clean)
    guard let m = re.firstMatch(in: clean, options: [], range: full),
          m.numberOfRanges >= 2,
          let hexRange = Range(m.range(at: 1), in: clean) else { return nil }
    let hex = String(clean[hexRange])
    guard hex.count == 4,
          let a = Int(String(hex.prefix(2)), radix: 16),
          let b = Int(String(hex.suffix(2)), radix: 16) else { return nil }
    return a * 256 + b
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - ContinuationGuard
// ═══════════════════════════════════════════════════════════════════════════════

/// Потокобезопасный одноразовый guard для безопасного resume `CheckedContinuation`.
///
/// **Проблема:**
/// `NWConnection.receive()` вызывает callback на произвольном потоке DispatchQueue.
/// Один и тот же continuation может быть resumed из нескольких мест:
///   1. Из data-callback'а, когда пришёл символ `>` (prompt ELM327).
///   2. Из timeout-таймера, сработавшего по `queue.asyncAfter`.
///   3. Из error/isComplete callback'а при обрыве соединения.
/// Повторный resume `CheckedContinuation` — это crash (Swift runtime trap).
///
/// **Решение:**
/// `claim()` возвращает `true` ровно один раз; все последующие вызовы — `false`.
/// Атомарность обеспечивается `NSLock`.
///
/// **Аналог в Android:** не нужен — `InputStream.read()` блокирующий и однопоточный.
/// В iOS `NWConnection` — событийная модель, поэтому guard обязателен.
///
/// Помечен `@unchecked Sendable`, т.к. защита данных гарантируется `NSLock`,
/// но компилятор не может это вывести автоматически.
private final class ContinuationGuard: @unchecked Sendable {
    private var _claimed = false
    private let _lock = NSLock()

    /// Проверяет, был ли guard уже «использован» (continuation resumed).
    var isDone: Bool {
        _lock.lock()
        defer { _lock.unlock() }
        return _claimed
    }

    /// Пытается «забрать» право на resume. Возвращает `true` ровно один раз;
    /// все последующие вызовы возвращают `false`.
    func claim() -> Bool {
        _lock.lock()
        defer { _lock.unlock() }
        if _claimed { return false }
        _claimed = true
        return true
    }

    /// Сбрасывает guard для повторного использования.
    /// Применяется в `connectWifi` при переходных состояниях NWConnection
    /// (`.preparing`, `.setup`), которые не являются финальными.
    func reset() {
        _lock.lock()
        _claimed = false
        _lock.unlock()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - ReadState
// ═══════════════════════════════════════════════════════════════════════════════

/// Разделяемое мутабельное состояние для `readUntilPrompt`.
///
/// Содержит:
///   - `buffer` — накопленные байты ответа до символа `>`.
///   - `guard_` — `ContinuationGuard` для однократного resume continuation.
///
/// Помечен `@unchecked Sendable`, чтобы его можно было захватить в `@Sendable`-замыканиях
/// `NWConnection.receive()` и `queue.asyncAfter()`. Потокобезопасность обеспечивается
/// тем, что все обращения происходят на одной `DispatchQueue` (serial) `self.queue`.
private final class ReadState: @unchecked Sendable {
    var buffer = Data()
    let guard_ = ContinuationGuard()
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - ObdError
// ═══════════════════════════════════════════════════════════════════════════════

/// Ошибки OBD-соединения, используемые при подключении и обмене данными.
///
/// Аналог: в Android ошибки передаются через `Result.failure(Exception(...))`.
/// В iOS используется типизированный enum для pattern matching в UI-слое.
enum ObdError: Error, LocalizedError {
    /// Попытка отправить команду при отсутствии активного NWConnection.
    case notConnected
    /// Превышено время ожидания ответа от адаптера.
    case timeout
    /// Соединение отменено пользователем или системой.
    case cancelled
    /// NWConnection перешёл в состояние `.failed` или `.cancelled` после установки.
    case connectionClosed
    /// Ошибка подключения с описанием причины (человекочитаемый текст на русском).
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:             return "Нет соединения"
        case .timeout:                  return "Таймаут соединения"
        case .cancelled:                return "Соединение отменено"
        case .connectionClosed:         return "Соединение закрыто"
        case .connectionFailed(let s):  return s
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - SensorStatus
// ═══════════════════════════════════════════════════════════════════════════════

/// Статус показания датчика для цветовой индикации в UI.
///
/// - `ok`           — значение в пределах нормы (зелёная карточка).
/// - `warning`      — значение вышло за `minWarning`/`maxWarning` (жёлтая карточка).
/// - `unsupported`  — ЭБУ ответил «NO DATA» / «?» — PID не поддерживается этой машиной;
///                     карточка скрывается из сетки.
/// - `error`        — ошибка связи или «SEARCHING» (серая карточка с N/A).
/// - `disconnected` — нет активного соединения с адаптером.
///
/// Аналог Android: `SensorStatus` enum с теми же значениями.
enum SensorStatus { case ok, warning, unsupported, error, disconnected }

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - ObdPid
// ═══════════════════════════════════════════════════════════════════════════════

/// Описание одного OBD2 Mode 01 PID (Parameter Identification).
///
/// - `command`    — AT-команда для отправки адаптеру (напр. `"010C"`). Первые два символа =
///                  режим (`01` = Mode 01), следующие два = hex-номер PID.
/// - `shortCode`  — 2–4 буквы для компактного бейджа на карточке (напр. `"RPM"`).
/// - `name`       — полное название параметра на русском языке.
/// - `unit`       — единица измерения (напр. `"°C"`, `"об/мин"`, `"%"`).
/// - `minWarning` — нижний предупредительный порог; `nil` = не проверяется.
/// - `maxWarning` — верхний предупредительный порог; `nil` = не проверяется.
/// - `decode`     — замыкание, декодирующее массив байт ответа в `Float`.
///                  Байты: `b[0]`=0x41 (positive response Mode 01), `b[1]`=PID, `b[2..]`=данные.
///
/// Аналог Android: `data class ObdPid` с аналогичными полями и лямбдой `decode`.
struct ObdPid: Identifiable {
    var id: String { command }
    let command: String
    let shortCode: String
    let name: String
    let unit: String
    let minWarning: Float?
    let maxWarning: Float?
    let decode: ([Int]) -> Float
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - SensorReading
// ═══════════════════════════════════════════════════════════════════════════════

/// Результат одного опроса датчика (Mode 01).
///
/// - `pid`    — какой PID был запрошен (содержит имя, единицу, декодер).
/// - `value`  — декодированное float-значение; `nil` = нет данных / PID не поддерживается.
/// - `status` — статус для цветовой индикации карточки в UI.
///
/// Аналог Android: `data class SensorReading` с теми же полями.
struct SensorReading {
    let pid: ObdPid
    let value: Float?
    let status: SensorStatus
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DtcResult
// ═══════════════════════════════════════════════════════════════════════════════

/// Результат запроса диагностических кодов неисправностей.
/// Используется для Mode 03 (постоянные) и Mode 07 (ожидающие).
///
/// Аналог Android: `sealed class DtcResult` с теми же вариантами.
enum DtcResult: CustomStringConvertible {
    /// ЭБУ ответил: ошибок нет (или список пуст после фильтрации `"0000"`).
    case noDtcs
    /// Список найденных кодов в стандартном формате (напр. `["P0420", "C0031"]`).
    case dtcList([String])
    /// Нераспознанный ответ (например, нестандартный формат ЭБУ) — показываем «как есть».
    case rawResponse(String)
    /// Ошибка связи, таймаут или адаптер в состоянии «SEARCHING».
    case error(String)

    var description: String {
        switch self {
        case .noDtcs:              return "NoDtcs"
        case .dtcList(let codes):  return "DtcList(\(codes))"
        case .rawResponse(let r):  return "RawResponse(\(r))"
        case .error(let msg):      return "Error(\(msg))"
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - VehicleInfo
// ═══════════════════════════════════════════════════════════════════════════════

/// Статическая информация об автомобиле, прочитанная через OBD2 Mode 09.
///
/// Заполняется при вызове `readVehicleInfo()`. Поля `nil` = ЭБУ не поддерживает
/// соответствующий PID или не вернул данные (некоторые машины не отвечают на 090A).
///
/// **VIN (17 символов, ISO 3779):**
///   - Символы 1–3 (WMI) → производитель/завод (`VinWmiTable` + `decodeVinMake`).
///   - Символ 10 → модельный год (`decodeVinYear`).
///   - Символ 1 в диапазоне '1'…'5' → Северная Америка → `usesImperialUnits = true`.
///
    /// **Имперские единицы:**
    /// Часть американских ЭБУ нарушает стандарт и передаёт PIDs 0x21/0x31 в милях.
    /// `distanceMilKm()` / `distanceClearedKm()` конвертируют автоматически.
    ///
    /// **Важно про 0x31:** это не показание щитка приборов, а счётчик «после clear DTC» (2 байта).
///
/// Аналог Android: `data class VehicleInfo` с теми же полями и методами.
struct VehicleInfo: Equatable {
    /// 17-символьный идентификационный номер, ISO 3779.
    var vin: String?               = nil
    /// Производитель/завод по WMI (первые 3 символа VIN), см. `VinWmiTable`.
    var detectedMake: String?      = nil
    /// Модельный год, декодированный из 10-го символа VIN.
    var detectedYear: String?      = nil
    /// Название ЭБУ двигателя (Mode 09, PID 0A).
    var ecuName: String?           = nil
    /// Calibration ID (Mode 09, PID 03).
    var calibrationId: String?    = nil
    /// CVN (Mode 09, PID 04).
    var cvnHex: String?            = nil
    /// Маска поддерживаемых PID Mode 09 (ответ PID 00), 8 hex-символов.
    var mode09SupportMaskHex: String? = nil
    /// Сырые фрагменты PID 01, 05–09 Mode 09.
    var mode09ExtrasSummary: String? = nil
    /// PID 0x1C — тип OBD.
    var obdStandardLabel: String? = nil
    /// PID 0x51 — тип топлива.
    var fuelTypeLabel: String?     = nil
    /// Имя ЭБУ КПП (090A на CAN 7E1).
    var transmissionEcuName: String? = nil
    /// Одометр комбинации приборов (UDS 0x22, марочные пробы на CAN) — экспериментально.
    var clusterOdometerKm: Int? = nil
    /// Откуда взято [clusterOdometerKm] (для отладки / PDF).
    var clusterOdometerNote: String? = nil
    /// Символы 4–9 VIN (ISO 3779 VDS) — задел для платформенных веток.
    var vinVehicleDescriptor: String? = nil
    /// Имя группы марки (`BrandEcuHints.VehicleBrandGroup.rawValue`).
    var diagnosticBrandGroup: String? = nil
    /// Пробег с горящим Check Engine (PID 0x21), моторный ЭБУ; не полный одометр.
    var distanceMil: Int?          = nil
    /// PID 0x31: пройдено с последнего **сброса DTC в сканере** — не одометр приборки; max 65535 км (SAE).
    var distanceCleared: Int?      = nil
    /// PID 0x03 — статус топливной системы (Open/Closed Loop).
    var fuelSystemStatus: String?  = nil
    /// PID 0x30 — количество прогревов двигателя с последнего сброса DTC.
    var warmUpsCleared: Int?       = nil
    /// PID 0x4E — минуты с последнего сброса DTC.
    var timeSinceClearedMin: Int?  = nil
    /// `true` = WMI 1–5 (Северная Америка); ЭБУ может передавать дистанцию в милях.
    var usesImperialUnits: Bool    = false

    private static let milesToKm = 1.60934

    /// Дистанция с MIL в километрах (конвертируется из миль, если `usesImperialUnits`).
    func distanceMilKm() -> Int?     { distanceMil.map     { usesImperialUnits ? Int(Double($0) * Self.milesToKm) : $0 } }
    /// Дистанция после сброса в километрах (конвертируется из миль, если `usesImperialUnits`).
    func distanceClearedKm() -> Int? { distanceCleared.map { usesImperialUnits ? Int(Double($0) * Self.milesToKm) : $0 } }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - FreezeFrameData
// ═══════════════════════════════════════════════════════════════════════════════

/// Снимок параметров двигателя в момент появления приоритетной ошибки (Mode 02).
///
/// ЭБУ хранит один freeze frame — состояние датчиков в момент, когда была
/// зафиксирована наиболее приоритетная неисправность (обычно первая).
/// Формат запроса: `"02[PID]\r"`, ответ: `"42[PID][данные]"`.
/// Декодирование байт идентично Mode 01 (те же формулы).
///
/// Поля `nil` = ЭБУ не поддерживает соответствующий PID в Mode 02 или не вернул данные.
///
/// Аналог Android: `data class FreezeFrameData` с теми же полями.
struct FreezeFrameData: Equatable {
    var dtcCode: String?     = nil   // DTC, вызвавший снимок (PID 02)
    var rpm: Int?            = nil   // об/мин — PID 0C: (A×256+B)/4
    var speed: Int?          = nil   // км/ч — PID 0D: A
    var coolantTemp: Int?    = nil   // °C — PID 05: A-40
    var engineLoad: Float?   = nil   // % — PID 04: A×100/255
    var throttle: Float?     = nil   // % — PID 11: A×100/255
    var shortFuelTrim: Float? = nil  // % — PID 06: (A-128)×100/128
    var longFuelTrim: Float? = nil   // % — PID 07: (A-128)×100/128
    var map: Int?            = nil   // кПа — PID 0B: A
    var iat: Int?            = nil   // °C — PID 0F: A-40
    var voltage: Float?      = nil   // В — PID 42: (A×256+B)/1000
    var fuelStatus: String?  = nil   // Open/Closed Loop — PID 03

    var isEmpty: Bool {
        dtcCode == nil && rpm == nil && speed == nil && coolantTemp == nil &&
        engineLoad == nil && throttle == nil && shortFuelTrim == nil && longFuelTrim == nil &&
        map == nil && iat == nil && voltage == nil && fuelStatus == nil
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - ReadinessMonitor
// ═══════════════════════════════════════════════════════════════════════════════

/// Одна запись о готовности системы мониторинга OBD2 (Mode 01, PID 0x01).
///
/// - `name`  — название монитора на русском языке (напр. «Каталитический нейтрализатор»).
/// - `ready` — `true` = монитор завершил тест (готов к проверке выбросов);
///             `false` = тест ещё не пройден (нужен driving cycle).
///
/// Аналог Android: `data class ReadinessMonitor` с теми же полями.
struct ReadinessMonitor: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let ready: Bool
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - EcuDtcResult
// ═══════════════════════════════════════════════════════════════════════════════

/// Результат попытки считать DTC с нестандартного блока через CAN-адресацию (ATSH).
///
/// - `name`    — человекочитаемое название блока (напр. «ABS / Тормоза»).
/// - `address` — 11-битный CAN-заголовок запроса (напр. «7B0»).
/// - `result`  — результат опроса: коды / ошибка / нет данных.
///
/// Аналог Android: `data class EcuDtcResult` с теми же полями.
struct EcuDtcResult: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let result: DtcResult
    var pendingResult: DtcResult = .noDtcs
    var permanentResult: DtcResult = .noDtcs
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - AsyncMutex
// ═══════════════════════════════════════════════════════════════════════════════

/// Асинхронный мьютекс с двумя стратегиями захвата: `withLock` (ожидающий) и `tryLock` (неблокирующий).
///
/// **Зачем нужен:**
/// Все операции с `NWConnection` (send/receive) должны быть сериализованы — при одновременном
/// запуске live-мониторинга и чтения DTC два Task'а могут отправлять команды и читать ответы
/// из одного TCP-потока параллельно. Для TCP это критично — corrupted stream сложно восстановить.
///
/// **Стратегия для `pollSensor` (live-мониторинг): `tryLock()` (неблокирующий).**
///   Если DTC-скан держит мьютекс — сенсор немедленно возвращает `.error` (N/A в UI).
///   Это приемлемо: мониторинг продолжается и восстанавливается автоматически.
///
/// **Стратегия для DTC/VehicleInfo-операций: `withLock` (ожидающий).**
///   Перед началом ждёт завершения текущего poll-цикла — не более одного PID (~800 мс Wi-Fi).
///
/// **Аналог Android:** `kotlinx.coroutines.sync.Mutex` с тем же паттерном `tryLock`/`withLock`.
/// В Swift нет встроенного async-aware мьютекса, поэтому реализован вручную через
/// `NSLock` + `CheckedContinuation` FIFO-очередь.
///
/// Помечен `@unchecked Sendable`: защита данных обеспечена `NSLock`, но компилятор
/// не может это вывести автоматически.
final class AsyncMutex: @unchecked Sendable {
    private var _isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let _lock = NSLock()

    private func _syncLock()   { _lock.lock() }
    private func _syncUnlock() { _lock.unlock() }

    /// Ожидающий захват: если мьютекс занят, приостанавливает текущий Task
    /// до момента освобождения. Гарантирует FIFO-порядок пробуждения.
    func withLock<T>(_ body: () async throws -> T) async rethrows -> T {
        await acquireLock()
        defer { releaseLock() }
        return try await body()
    }

    /// Неблокирующий захват: возвращает `true` при успехе, `false` если уже занят.
    /// Используется в `pollSensor` — при неудаче сразу возвращает N/A вместо ожидания.
    func tryLock() -> Bool {
        _syncLock()
        defer { _syncUnlock() }
        if _isLocked { return false }
        _isLocked = true
        return true
    }

    /// Освобождает мьютекс. Должен вызываться в паре с успешным `tryLock()`.
    func unlock() { releaseLock() }

    /// Внутренний метод захвата: если свободен — захватывает синхронно;
    /// если занят — добавляет continuation в FIFO-очередь и suspend'ит Task.
    private func acquireLock() async {
        _syncLock()
        if !_isLocked {
            _isLocked = true
            _syncUnlock()
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
            _syncUnlock()
        }
    }

    /// Внутренний метод освобождения: если есть ожидающие — resume первого из FIFO;
    /// если очередь пуста — снимает флаг `_isLocked`.
    private func releaseLock() {
        _syncLock()
        if let next = waiters.first {
            waiters.removeFirst()
            _syncUnlock()
            next.resume()
        } else {
            _isLocked = false
            _syncUnlock()
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - ObdConnectionManager
// ═══════════════════════════════════════════════════════════════════════════════

/// Главный класс для работы с ELM327 через Wi-Fi TCP на iOS.
///
/// Является `ObservableObject` для SwiftUI — публикует `connectedDeviceLabel`
/// через `@Published`, чтобы UI автоматически обновлял статус подключения.
///
/// Помечен `@unchecked Sendable`: доступ к мутабельному состоянию (`connection`,
/// `lastEcuCommandMs`) сериализуется через `ioMutex` и `queue`.
///
/// **Аналог Android:** `ObdConnectionManager` (класс, не singleton). В Android
/// экземпляр хранится в `AppState` (Compose), в iOS — в `AppViewModel` (SwiftUI).
final class ObdConnectionManager: ObservableObject, @unchecked Sendable {

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Constants
    // ─────────────────────────────────────────────────────────────────────────

    /// Таймаут ожидания ответа ЭБУ на DTC/VIN/clear команды (мс).
    /// 12 сек покрывает K-Line 5-baud re-init (~7 сек) + сам ответ (~0.5 сек) с запасом.
    /// На CAN-авто ответ приходит за <200 мс — запас не влияет на скорость.
    private static let READ_TIMEOUT_MS       = 12_000

    /// Таймаут live PID (Mode 01) для Wi-Fi TCP.
    /// RTT Wi-Fi ~5–20 мс, нет overhead Bluetooth-стека, но внутренний парсинг адаптера
    /// добавляет задержку. 400 мс давал N/A на многих WiFi-адаптерах — 800 мс компромисс.
    /// На Android есть ещё BT-таймаут 1500 мс; на iOS Bluetooth SPP недоступен.
    private static let SENSOR_TIMEOUT_WIFI_MS = 800

    /// Таймаут TCP-подключения к адаптеру (секунды).
    /// 10 сек: покрывает медленные Wi-Fi модули + DNS-резолв в локальной сети.
    private static let CONNECT_TIMEOUT_SEC    = 10

    /// Порог простоя (мс), после которого `warmupIfNeeded` отправляет `0100`.
    /// K-Line (ISO 9141-2 / KWP2000) имеет P3_Max = 5 секунд — максимальный интервал
    /// между командами. 3.5 с = запас ~1.5 с до таймаута сессии ЭБУ.
    /// CAN-шина не имеет P3_Max, но warmup безвреден (~200 мс).
    private static let WARMUP_IDLE_THRESHOLD_MS: Int64 = 3500

    /// Таймаут для warmup-команды `0100` (мс).
    /// 9 сек: покрывает K-Line с истёкшей сессией — 5-baud re-init занимает 5–7 сек.
    /// На CAN ответ за ~200 мс — запас не влияет на скорость.
    private static let WARMUP_TIMEOUT_MS      = 9000

    /// Задержка после Mode 04 (Clear DTC) перед восстановлением сессии (мс).
    /// ЭБУ выполняет внутренний сброс после стирания ошибок — на некоторых авто 2+ с.
    /// 2.5 с — эмпирический минимум (было 1.5 с, давал NO DATA на Honda).
    private static let POST_CLEAR_DELAY_MS    = 2500

    /// Время чтения при сбросе буфера в `drainInput` (мс).
    /// ELM327 может прислать финальный `>` с задержкой до ~200 мс после нашего
    /// readUntilPrompt-таймаута. 150 мс — компромисс между полнотой очистки и задержкой.
    private static let DRAIN_TIMEOUT_MS       = 150

    /// Длина VIN по стандарту ISO 3779.
    private static let VIN_LENGTH             = 17

    /// Максимальная длина имени ЭБУ (Mode 09 PID 0A), символов.
    /// Ограничение для защиты от мусорных данных при битых ответах.
    private static let MAX_ECU_NAME_LENGTH    = 32

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: State
    // ─────────────────────────────────────────────────────────────────────────

    /// Активное TCP-соединение с ELM327 через Network.framework.
    /// `nil` = не подключены. Создаётся в `connectWifi`, уничтожается в `disconnect`.
    private var connection: NWConnection?

    /// Serial DispatchQueue для всех операций NWConnection.
    /// NWConnection требует указать очередь при `start()` и использует её для всех callback'ов.
    /// `.userInitiated` QoS: OBD-обмен — интерактивная задача, задержки заметны пользователю.
    private let queue = DispatchQueue(label: "com.uremont.obd", qos: .userInitiated)

    /// Мьютекс, сериализующий все операции ввода-вывода с адаптером.
    /// См. документацию `AsyncMutex` для описания стратегий `tryLock`/`withLock`.
    private let ioMutex = AsyncMutex()

    /// Время (epoch ms) последней отправки OBD2-команды (не AT).
    /// K-Line P3_Max = 5 сек — если пауза > 3.5 с, `warmupIfNeeded` восстановит сессию.
    /// AT-команды не обновляют таймстамп: ELM327 обрабатывает их локально, не затрагивая шину.
    private var lastEcuCommandMs: Int64 = 0

    /// `true` = CAN (ISO 15765-4), `false` = K-Line / KWP / J1850.
    /// Влияет на парсинг DTC: на CAN первый байт после маркера — count; на остальных — сразу DTC-пары.
    private var isCanProtocol = true

    /// `true`, если TCP-соединение установлено и готово к обмену.
    var isConnected: Bool { connection?.state == .ready }

    /// Подпись подключения для отображения в UI (напр. `"192.168.0.10:35000"`).
    /// `nil` = не подключены.
    @Published private(set) var connectedDeviceLabel: String?

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Connect Wi-Fi
    // ═══════════════════════════════════════════════════════════════════════════

    /// Устанавливает TCP-соединение с Wi-Fi ELM327 адаптером.
    ///
    /// Типичные параметры:
    ///   - `host = "192.168.0.10"` — Kingbolen, большинство китайских Wi-Fi ELM327.
    ///   - `port = 35000` — стандартный OBD Wi-Fi порт.
    ///   - Некоторые адаптеры: `192.168.4.1:35000` или `192.168.1.1:23`.
    ///
    /// Телефон должен быть уже подключён к Wi-Fi точке адаптера (iOS не может
    /// подключиться к Wi-Fi программно без Hotspot Configuration Entitlement).
    ///
    /// **TCP_NODELAY** (`noDelay = true`):
    /// Отключает алгоритм Nagle, который буферизует короткие пакеты (наши AT-команды =
    /// 2–6 байт) ожидая ACK и добавляя до 200 мс задержки. Без этого флага команды
    /// `"03\r"`, `"04\r"` могут приходить на адаптер с задержкой, что вызывает
    /// `NO DATA` или `STOPPED` при повторных запросах. Критично для интерактивного протокола.
    ///
    /// **NWConnection lifecycle:**
    /// 1. Создаём NWConnection → `.setup`.
    /// 2. `conn.start(queue:)` → `.preparing` → `.ready` (успех) или `.failed` (ошибка).
    /// 3. `stateUpdateHandler` + `ContinuationGuard` обеспечивают однократный resume continuation.
    /// 4. Таймаут через `queue.asyncAfter` — если за 10 с не стало `.ready`, отменяем.
    ///
    /// После успешного подключения вызывается `initializeElm327()` — последовательность
    /// AT-команд для настройки адаптера.
    ///
    /// - Parameters:
    ///   - host: IP-адрес адаптера.
    ///   - port: TCP-порт адаптера.
    /// - Returns: `.success` при успешном подключении и инициализации;
    ///            `.failure` с `ObdError` при ошибке.
    func connectWifi(host: String, port: Int) async -> Result<Void, Error> {
        disconnect()
        info("═══ WiFi connect → \(host):\(port) ═══")

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return .failure(ObdError.connectionFailed("Некорректный порт: \(port)"))
        }

        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: params
        )

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                let guard_ = ContinuationGuard()

                conn.stateUpdateHandler = { state in
                    guard guard_.claim() else { return }
                    switch state {
                    case .ready:
                        cont.resume()
                    case .failed(let error):
                        cont.resume(throwing: error)
                    case .cancelled:
                        cont.resume(throwing: ObdError.cancelled)
                    default:
                        // .preparing, .setup — переходные состояния, ждём дальше
                        guard_.reset()
                    }
                }

                conn.start(queue: self.queue)

                self.queue.asyncAfter(deadline: .now() + .seconds(Self.CONNECT_TIMEOUT_SEC)) {
                    guard guard_.claim() else { return }
                    conn.cancel()
                    cont.resume(throwing: ObdError.timeout)
                }
            }

            connection = conn
            connectedDeviceLabel = "\(host):\(port)"
            try await initializeElm327()
            return .success(())
        } catch {
            warn("WiFi connect failed: \(error.localizedDescription)")
            conn.cancel()
            connection = nil
            connectedDeviceLabel = nil
            return .failure(ObdError.connectionFailed(friendlyWifiError(error)))
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Disconnect
    // ═══════════════════════════════════════════════════════════════════════════

    /// Закрывает TCP-соединение и сбрасывает все ссылки.
    ///
    /// Безопасно вызывать многократно — `NWConnection.cancel()` на уже отменённом
    /// соединении не вызывает ошибок. Сбрасывает `lastEcuCommandMs`, чтобы следующее
    /// подключение начало с warmup.
    ///
    /// Аналог Android: `disconnect()` — закрывает BT/Wi-Fi сокеты и обнуляет потоки.
    func disconnect() {
        info("═══ disconnect ═══")
        connection?.cancel()
        connection = nil
        connectedDeviceLabel = nil
        lastEcuCommandMs = 0
        isCanProtocol = true
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Init ELM327
    // ═══════════════════════════════════════════════════════════════════════════

    /// Последовательность инициализации ELM327 (ISO 15765-4):
    /// ATZ   — полный сброс чипа (нужен delay 2с для перезагрузки)
    /// ATE0  — отключить эхо (иначе каждая команда возвращается в ответе)
    /// ATL0  — отключить linefeeds (компактный формат)
    /// ATH0  — скрыть CAN-заголовки (показывать только данные)
    /// ATS0  — убрать пробелы из ответов (упрощает hex-парсинг)
    /// ATSP0 — автоопределение протокола OBD2
    /// 0100  — warmup PID Supported [01-20], прогрев K-Line/KWP сессии
    ///
    /// **ATH0 / ATS0** критичны для корректного парсинга: без них ответ содержит
    /// CAN-заголовки и пробелы (`"7E8 04 41 0C ..."`), что ломает `parseHexBytes`.
    ///
    /// **Warmup `0100`:** после ATSP0 ОБЯЗАТЕЛЕН — именно он запускает фактическое
    /// определение протокола. CAN: ~500 мс. K-Line: 5–7 с (5-baud slow init).
    /// Без warmup ELM327 будет выводить «SEARCHING...» на первой же OBD2-команде.
    private func initializeElm327() async throws {
        try await sendRaw("ATZ");   await delay(2000); await consumeAtResponse(timeoutMs: 3000)
        try await sendRaw("ATE0");  await delay(300);  await consumeAtResponse()
        try await sendRaw("ATL0");  await delay(300);  await consumeAtResponse()
        try await sendRaw("ATH0");  await delay(300);  await consumeAtResponse()
        try await sendRaw("ATS0");  await delay(300);  await consumeAtResponse()
        try await sendRaw("ATSP0"); await delay(300);  await consumeAtResponse()

        try await sendRaw("0100")
        let warmupResp = (await readUntilPrompt(timeoutMs: Self.WARMUP_TIMEOUT_MS)).cleanObd()
        info("Protocol warmup: '\(warmupResp)'")
        await drainInput()

        let proto = (await elmProtocolDescription()).uppercased()
        isCanProtocol = proto.contains("CAN") || proto.contains("15765")
        info("Detected protocol: '\(proto)', isCAN=\(isCanProtocol)")
        await drainInput()

        info("ELM327 initialization complete")
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Read DTCs (Mode 03)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Читает постоянные коды неисправностей (Mode 03).
    ///
    /// Протокол: клиент отправляет `"03\r"`, ЭБУ отвечает `"43 XX XX XX..."` где
    /// `43` = 0x40 (positive response) | 0x03 (mode) = подтверждение Mode 03.
    /// Далее попарно идут байты кода: 2 байта = один DTC.
    ///
    /// Пример ответа: `"43 01 43 00 00 00 00"`
    ///   → DTC P0143 (байты 0x01, 0x43 → nibble 0 = 'P', тип 0, код 143).
    ///
    /// Вызывается внутри `ioMutex.withLock` — ожидает завершения текущего poll-цикла.
    ///
    /// - Returns: `DtcResult` — список кодов, «нет ошибок» или описание ошибки.
    func readDtcs() async -> DtcResult {
        await ioMutex.withLock {
            do {
                await self.warmupIfNeeded()
                await self.drainInput()
                try await self.sendRaw("03")
                let raw = await self.readUntilPrompt()
                let result = self.parseDtcResponse(responseMarker: "43", raw: raw)
                info("readDtcs → \(result)")
                return result
            } catch {
                err("readDtcs() error", error)
                return DtcResult.error(error.localizedDescription)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - UDS 0x19 (ReadDTCInformation)
    // ═══════════════════════════════════════════════════════════════════════════

    /// UDS service 0x19, subFunction 0x02 (reportDTCByStatusMask).
    /// Запрос: `19 02 FF` (все DTC с любым статусом).
    /// Ответ:  `59 02 <availMask> [DTC_HI DTC_MID DTC_LO STATUS]...`
    ///
    /// DTC кодируется 3 байтами (J2012): первые 2 — как в OBD2 (P/C/B/U + код),
    /// 3-й — Failure Type Byte (FTB). Статус-байт: bit3=confirmed, bit2=pending, bit0=testFailed.
    ///
    /// Используется как fallback, когда Mode 03 не поддерживается блоком.
    func parseUdsDtcResponse(_ raw: String) -> DtcResult {
        let clean = raw.cleanObd()
        if clean.contains("NODATA") || clean.contains("UNABLE") || clean.contains("ERROR") {
            return .error("Блок не поддерживает UDS")
        }
        if clean.contains("7F19") { return .error("UDS service не поддерживается") }

        var dtcs = Set<String>()

        let tokens = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
        for token in tokens {
            let hex = token.replacingOccurrences(of: "^\\d+:", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[^0-9A-Fa-f]", with: "", options: .regularExpression)
                .uppercased()
            guard hex.contains("5902") else { continue }
            guard let idx = hex.range(of: "5902") else { continue }
            let payload = String(hex[idx.upperBound...])
            if payload.count >= 2 {
                let data = String(payload.dropFirst(2)) // пропускаем availabilityMask
                parseUdsDtcRecords(data, into: &dtcs)
            }
        }

        if dtcs.isEmpty {
            if let range = clean.range(of: "5902") {
                let payload = String(clean[range.upperBound...])
                if payload.count >= 2 {
                    parseUdsDtcRecords(String(payload.dropFirst(2)), into: &dtcs)
                }
            }
        }

        if dtcs.isEmpty && clean.contains("5902") { return .noDtcs }
        if dtcs.isEmpty { return .error("Нет ответа UDS") }
        return .dtcList(Array(dtcs))
    }

    /// Парсит записи UDS DTC: 3 байта DTC + 1 байт статус (8 hex символов на запись).
    /// Первые 2 байта — J2012 (decodeDtc), 3-й — Failure Type Byte.
    /// Если FTB != 0, добавляется суффикс `-XX`.
    /// Эвристика как на Android: для редких ЭБУ полный 24-битный DTC по ISO 15031-6 может отличаться.
    func parseUdsDtcRecords(_ data: String, into out: inout Set<String>) {
        var i = data.startIndex
        while data.distance(from: i, to: data.endIndex) >= 8 {
            let dtcEnd = data.index(i, offsetBy: 4)
            let ftbEnd = data.index(dtcEnd, offsetBy: 2)
            let statusEnd = data.index(ftbEnd, offsetBy: 2)
            let dtcHex = String(data[i..<dtcEnd])
            let ftbHex = String(data[dtcEnd..<ftbEnd])
            let _ = String(data[ftbEnd..<statusEnd]) // status byte
            if dtcHex != "0000" && dtcHex != "FFFF" {
                let base = decodeDtc(dtcHex)
                let ftb = UInt8(ftbHex, radix: 16) ?? 0
                let code = ftb != 0 ? "\(base)-\(ftbHex.uppercased())" : base
                out.insert(code)
            }
            i = statusEnd
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Pending DTCs (Mode 07)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Читает ожидающие коды неисправностей (Mode 07, Pending DTC).
    ///
    /// Ожидающие коды фиксируются ЭБУ в текущем ездовом цикле, но становятся
    /// постоянными (Mode 03) только после нескольких подряд подтверждений.
    /// Полезно для ранней диагностики: ошибка есть, но лампа Check Engine ещё не горит.
    ///
    /// Протокол аналогичен Mode 03, но ЭБУ отвечает маркером `"47"` вместо `"43"`.
    /// Отсутствие маркера = нормальная ситуация (ожидающих кодов нет), поэтому
    /// `missingMarkerResult` = `.noDtcs` (в отличие от Mode 03, где это `.rawResponse`).
    ///
    /// - Returns: `DtcResult` — список кодов, «нет ошибок» или описание ошибки.
    func readPendingDtcs() async -> DtcResult {
        await ioMutex.withLock {
            do {
                await self.warmupIfNeeded()
                await self.drainInput()
                try await self.sendRaw("07")
                let raw = await self.readUntilPrompt()
                let result = self.parseDtcResponse(
                    responseMarker: "47",
                    raw: raw,
                    missingMarkerResult: .noDtcs
                )
                info("readPendingDtcs → \(result)")
                return result
            } catch {
                err("readPendingDtcs() error", error)
                return DtcResult.error(error.localizedDescription)
            }
        }
    }

    /// Постоянные эмиссионные DTC (Mode 0A, Permanent DTC / PDTC).
    ///
    /// Часто есть на авто под USA OBD-II (≈2010+); на многих EU — `NO DATA`.
    /// Положительный ответ с маркером `4A`, разбор как у Mode 03.
    func readPermanentDtcs() async -> DtcResult {
        await ioMutex.withLock {
            do {
                await self.warmupIfNeeded()
                await self.drainInput()
                try await self.sendRaw("0A")
                let raw = await self.readUntilPrompt()
                let clean = raw.cleanObd()
                let result: DtcResult
                if clean.contains("NODATA") || clean.contains("UNABLE") ||
                    (clean.contains("ERROR") && !clean.contains("4A")) {
                    result = .noDtcs
                } else {
                    result = self.parseDtcResponse(
                        responseMarker: "4A",
                        raw: raw,
                        missingMarkerResult: .noDtcs
                    )
                }
                info("readPermanentDtcs → \(result)")
                return result
            } catch {
                err("readPermanentDtcs() error", error)
                return .error(error.localizedDescription)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Clear DTCs (Mode 04)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Сбрасывает все постоянные и ожидающие коды, гасит лампу Check Engine (Mode 04).
    ///
    /// ЭБУ также сбрасывает счётчики «Distance with MIL on» и Freeze Frame.
    /// После успешного Mode 04 вызывается `postClearWarmup()` — ЭБУ выполняет
    /// внутренний сброс, и K-Line сессия умирает; нужно её восстановить.
    ///
    /// - Returns: `true`, если в ответе присутствует маркер `"44"` (positive response).
    func clearDtcs() async -> Bool {
        await ioMutex.withLock {
            do {
                await self.warmupIfNeeded()
                await self.drainInput()
                try await self.sendRaw("04")
                let raw = await self.readUntilPrompt()
                let ok = raw.cleanObd().contains("44")
                await self.postClearWarmup()
                return ok
            } catch {
                err("clearDtcs() error", error)
                return false
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Freeze Frame (Mode 02)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Читает снимок параметров в момент появления приоритетной ошибки (Mode 02).
    ///
    /// ЭБУ хранит один freeze frame — состояние датчиков в момент, когда была
    /// зафиксирована наиболее приоритетная неисправность (обычно первая).
    ///
    /// Формат запроса: `"02[PID]\r"`, ответ: `"42[PID][данные]"`.
    /// Декодирование байт идентично Mode 01 (те же PIDs, те же формулы).
    ///
    /// Каждый параметр запрашивается отдельно, т.к. ELM327 не поддерживает мульти-PID
    /// в Mode 02. Параметр, который ЭБУ не поддерживает, вернёт «NO DATA» — он просто
    /// остаётся `nil` в `FreezeFrameData`.
    ///
    /// `drainInput()` перед каждым запросом критичен: хвостовые байты предыдущего
    /// ответа не должны попасть в начало следующего чтения.
    ///
    /// - Returns: `FreezeFrameData` с заполненными полями (или `nil` для неподдерживаемых PID).
    func readFreezeFrame() async -> FreezeFrameData {
        await ioMutex.withLock {
            var data = FreezeFrameData()
            let timeout = Self.SENSOR_TIMEOUT_WIFI_MS

            func query(_ cmd: String, _ marker: String, _ tMs: Int = timeout) async -> [Int]? {
                await self.drainInput()
                try? await self.sendRaw(cmd)
                await self.delay(100)
                let clean = (await self.readUntilPrompt(timeoutMs: tMs)).cleanObd()
                return self.parseHexBytes(from: clean, marker: marker)
            }

            await self.warmupIfNeeded()

            if let b = await query("0202", "4202", 2000), b.count >= 4 {
                let block = String(format: "%02X%02X", b[2], b[3])
                if block != "0000" { data.dtcCode = self.decodeDtc(block) }
            }
            if let b = await query("0203", "4203"), b.count >= 3 {
                let b2 = b.count >= 4 ? b[3] : 0
                data.fuelStatus = Self.decodeFuelSystemStatus(b[2], b2)
            }
            if let b = await query("020C", "420C"), b.count >= 4 { data.rpm = ((b[2] * 256) + b[3]) / 4 }
            if let b = await query("020D", "420D"), b.count >= 3 { data.speed = b[2] }
            if let b = await query("0205", "4205"), b.count >= 3 { data.coolantTemp = b[2] - 40 }
            if let b = await query("0204", "4204"), b.count >= 3 { data.engineLoad = Float(b[2]) * 100.0 / 255.0 }
            if let b = await query("0211", "4211"), b.count >= 3 { data.throttle = Float(b[2]) * 100.0 / 255.0 }
            if let b = await query("0206", "4206"), b.count >= 3 { data.shortFuelTrim = Float(b[2] - 128) * 100.0 / 128.0 }
            if let b = await query("0207", "4207"), b.count >= 3 { data.longFuelTrim = Float(b[2] - 128) * 100.0 / 128.0 }
            if let b = await query("020B", "420B"), b.count >= 3 { data.map = b[2] }
            if let b = await query("020F", "420F"), b.count >= 3 { data.iat = b[2] - 40 }
            if let b = await query("0242", "4242"), b.count >= 4 { data.voltage = Float((b[2] * 256) + b[3]) / 1000.0 }

            return data
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Readiness (Mode 01 PID 01)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Читает статус готовности систем мониторинга OBD2 (Mode 01, PID 0x01).
    ///
    /// ЭБУ отвечает 4 байтами (A, B, C, D):
    ///   - Байт A: бит 7 = MIL on/off, биты 6:0 = количество ошибок.
    ///   - Байт B: биты 0–2 (поддерживается) / биты 4–6 (не завершён):
    ///     - 0/4 — мониторинг пропусков воспламенения
    ///     - 1/5 — система топлива
    ///     - 2/6 — общие компоненты
    ///   - Байты C, D: дополнительные мониторы (катализатор, EVAP, O₂ и др.).
    ///     - `supportBit = 1` → монитор присутствует в этом ЭБУ.
    ///     - `readyBit = 0` → монитор завершил тест — «готов» (инвертированная логика OBD2!).
    ///     - `readyBit = 1` → монитор ещё не завершил тест — «не готов».
    ///
    /// - Returns: Массив `ReadinessMonitor` — только поддерживаемые мониторы.
    ///            Пустой массив, если PID 0x01 не поддерживается.
    func readReadiness() async -> [ReadinessMonitor] {
        await ioMutex.withLock {
            do {
                await self.warmupIfNeeded()
                await self.drainInput()
                try await self.sendRaw("0101")
                await self.delay(200)
                let clean = (await self.readUntilPrompt(timeoutMs: 2000)).cleanObd()
                guard let bytes = self.parseHexBytes(from: clean, marker: "4101"),
                      bytes.count >= 6 else { return [] }
                // ISO 15031-5: byteB[0-2] = support bits (continuous), byteB[4-6] = incomplete bits.
                // bytesC/D: lower nibble = support, upper nibble = incomplete (non-continuous).
                // "Ready" = supported AND incomplete bit == 0.
                let byteB = bytes[3], byteC = bytes[4], byteD = bytes[5]
                var list = [ReadinessMonitor]()

                func add(_ source: Int, _ supportBit: Int, _ readyBit: Int, _ name: String) {
                    if source & supportBit != 0 {
                        list.append(ReadinessMonitor(name: name, ready: source & readyBit == 0))
                    }
                }

                // Байт B — три основных монитора (присутствуют на всех OBD2 машинах)
                add(byteB, 0x01, 0x10, "Пропуски воспламенения")
                add(byteB, 0x02, 0x20, "Система топлива")
                add(byteB, 0x04, 0x40, "Компоненты системы")
                // Байт C — мониторы выхлопа и пара топлива
                add(byteC, 0x01, 0x10, "Каталитический нейтрализатор")
                add(byteC, 0x02, 0x20, "Подогрев катализатора")
                add(byteC, 0x04, 0x40, "Система EVAP")
                add(byteC, 0x08, 0x80, "Вторичный воздух")
                // Байт D — мониторы кислородных датчиков и EGR
                add(byteD, 0x01, 0x10, "Кислородный датчик")
                add(byteD, 0x02, 0x20, "Нагрев O₂ датчика")
                add(byteD, 0x04, 0x40, "EGR / VVT система")
                return list
            } catch {
                err("readReadiness() failed", error)
                return []
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Vehicle Info (Mode 09)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Максимум **универсальных** данных OBD2: Mode 09 (VIN, маска 00, CalID 03, CVN 04, опц. 01/05–09, имя ЭБУ 0A),
    /// на CAN — UDS-пробы одометра щитка (марочные таблицы, при необходимости prelude `10 03`), затем ЭБУ КПП (`ATSH 7E1` + 090A); **0x27/0x2E** не используются;
    /// Mode 01: тип OBD (1C), топливо (51), 21/31. Полный одометр приборки в SAE не задаётся.
    ///
    /// - Returns: `VehicleInfo` — поля `nil`, если PID не поддерживается.
    func readVehicleInfo() async -> VehicleInfo {
        await ioMutex.withLock {
            var vin: String?
            var ecuName: String?
            var distanceMil: Int?
            var distanceCleared: Int?
            var mode09SupportMaskHex: String?
            var calibrationId: String?
            var cvnHex: String?
            var mode09ExtrasSummary: String?
            var obdStandardLabel: String?
            var fuelTypeLabel: String?
            var transmissionEcuName: String?
            var clusterOdometerKm: Int?
            var clusterOdometerNote: String?

            do {
                await self.warmupIfNeeded()
                await self.drainInput()
                try await self.sendRaw("0902")
                await self.delay(200)
                let raw = await self.readUntilPrompt(timeoutMs: 3000)
                dbg("VIN raw: '\(raw)'")
                vin = self.parseVin(raw)
            } catch { warn("VIN read failed: \(error.localizedDescription)") }

            var mode09Mask: [UInt8]?
            do {
                await self.drainInput()
                try await self.sendRaw("0900")
                await self.delay(150)
                let c00 = (await self.readUntilPrompt(timeoutMs: 2000)).cleanObd()
                mode09Mask = ObdVehicleInfoParse.mode09SupportMask(c00)
                if let m = mode09Mask {
                    mode09SupportMaskHex = m.map { String(format: "%02X", $0) }.joined()
                }
            } catch { warn("Mode 09/00 failed: \(error.localizedDescription)") }

            do {
                await self.drainInput()
                try await self.sendRaw("0903")
                await self.delay(200)
                let c = (await self.readUntilPrompt(timeoutMs: 2500)).cleanObd()
                calibrationId = ObdVehicleInfoParse.bestAsciiAfterMarker(c, marker: "4903", maxChars: 96)
            } catch { warn("Calibration ID failed: \(error.localizedDescription)") }

            do {
                await self.drainInput()
                try await self.sendRaw("0904")
                await self.delay(200)
                cvnHex = ObdVehicleInfoParse.cvnHexLine((await self.readUntilPrompt(timeoutMs: 2500)).cleanObd())
            } catch { warn("CVN failed: \(error.localizedDescription)") }

            var extraParts: [String] = []
            for pid in [1, 5, 6, 7, 8, 9] {
                if let mask = mode09Mask, !ObdVehicleInfoParse.isMode09PidSupported(mask, pid: pid) { continue }
                do {
                    await self.drainInput()
                    let cmd = String(format: "09%02X", pid)
                    try await self.sendRaw(cmd)
                    await self.delay(120)
                    let clean = (await self.readUntilPrompt(timeoutMs: 1500)).cleanObd()
                    let marker = String(format: "49%02X", pid)
                    if let hex = ObdVehicleInfoParse.hexPayloadAfterMarker(clean, marker: marker, maxDataBytes: 48) {
                        extraParts.append("09/\(String(format: "%02X", pid)):\(hex)")
                    }
                } catch { /* optional */ }
            }
            if !extraParts.isEmpty {
                mode09ExtrasSummary = extraParts.joined(separator: " ")
                if let s = mode09ExtrasSummary, s.count > 500 { mode09ExtrasSummary = String(s.prefix(500)) }
            }

            do {
                await self.drainInput()
                try await self.sendRaw("090A")
                await self.delay(200)
                let raw = await self.readUntilPrompt(timeoutMs: 2000)
                ecuName = self.parseEcuName(raw)
            } catch { warn("ECU name failed: \(error.localizedDescription)") }

            do {
                await self.drainInput()
                try await self.sendRaw("011C")
                await self.delay(100)
                let c = (await self.readUntilPrompt(timeoutMs: 1500)).cleanObd()
                if let b = ObdVehicleInfoParse.singleByteMode01(c, pidHex2: "1C") {
                    obdStandardLabel = ObdStandardLabels.obdStandard1c(b)
                }
            } catch { warn("OBD standard 1C failed: \(error.localizedDescription)") }

            do {
                await self.drainInput()
                try await self.sendRaw("0151")
                await self.delay(100)
                let c = (await self.readUntilPrompt(timeoutMs: 1500)).cleanObd()
                if let b = ObdVehicleInfoParse.singleByteMode01(c, pidHex2: "51") {
                    fuelTypeLabel = ObdStandardLabels.fuelType51(b)
                }
            } catch { warn("Fuel type 51 failed: \(error.localizedDescription)") }

            func readTwoByteMode1(_ pidCmd: String, _ marker: String) async -> Int? {
                do {
                    await self.drainInput()
                    try await self.sendRaw(pidCmd)
                    await self.delay(100)
                    let clean = (await self.readUntilPrompt(timeoutMs: 1500)).cleanObd()
                    return parseMode01TwoByteFromCleaned(clean, marker: marker)
                } catch { return nil }
            }

            distanceMil     = await readTwoByteMode1("0121", "4121")
            distanceCleared = await readTwoByteMode1("0131", "4131")

            var fuelSystemStatus: String?
            var warmUpsCleared: Int?
            var timeSinceClearedMin: Int?

            do {
                await self.drainInput()
                try await self.sendRaw("0103"); await self.delay(100)
                let clean03 = (await self.readUntilPrompt(timeoutMs: 1500)).cleanObd()
                if let bytes = self.parseHexBytes(from: clean03, marker: "4103") {
                    let b1 = bytes.count >= 3 ? bytes[2] : 0
                    let b2 = bytes.count >= 4 ? bytes[3] : 0
                    fuelSystemStatus = Self.decodeFuelSystemStatus(b1, b2)
                } else { fuelSystemStatus = nil }
            } catch { fuelSystemStatus = nil }

            do {
                await self.drainInput()
                try await self.sendRaw("0130"); await self.delay(100)
                let clean30 = (await self.readUntilPrompt(timeoutMs: 1500)).cleanObd()
                if let bytes = self.parseHexBytes(from: clean30, marker: "4130"), bytes.count >= 3 {
                    warmUpsCleared = bytes[2]
                } else { warmUpsCleared = nil }
            } catch { warmUpsCleared = nil }

            timeSinceClearedMin = await readTwoByteMode1("014E", "414E")

            let make = vin.flatMap { self.decodeVinMake($0) }
            let year = vin.flatMap { self.decodeVinYear($0) }
            let imperial = vin?.first.map { $0 >= "1" && $0 <= "5" } ?? false
            let vds: String? = {
                guard let v = vin, v.count >= 9 else { return nil }
                return String(v.dropFirst(3).prefix(6)).uppercased()
            }()
            let brandGrp = BrandEcuHints.classify(detectedMake: make, vin: vin).rawValue

            let clusterPair = await self.tryReadClusterOdometerKm(detectedMake: make, vin: vin)
            clusterOdometerKm = clusterPair.0
            clusterOdometerNote = clusterPair.1

            transmissionEcuName = await self.tryReadTcmEcuName()

            return VehicleInfo(
                vin: vin,
                detectedMake: make,
                detectedYear: year,
                ecuName: ecuName,
                calibrationId: calibrationId,
                cvnHex: cvnHex,
                mode09SupportMaskHex: mode09SupportMaskHex,
                mode09ExtrasSummary: mode09ExtrasSummary,
                obdStandardLabel: obdStandardLabel,
                fuelTypeLabel: fuelTypeLabel,
                transmissionEcuName: transmissionEcuName,
                clusterOdometerKm: clusterOdometerKm,
                clusterOdometerNote: clusterOdometerNote,
                vinVehicleDescriptor: vds,
                diagnosticBrandGroup: brandGrp,
                distanceMil: distanceMil,
                distanceCleared: distanceCleared,
                fuelSystemStatus: fuelSystemStatus,
                warmUpsCleared: warmUpsCleared,
                timeSinceClearedMin: timeSinceClearedMin,
                usesImperialUnits: imperial
            )
        }
    }

    private func restoreElmAfterAtsh(tag: String) async {
        do {
            try await sendRaw("ATD");   await delay(200); await consumeAtResponse()
            try await sendRaw("ATE0");  await delay(100); await consumeAtResponse()
            try await sendRaw("ATL0");  await delay(100); await consumeAtResponse()
            try await sendRaw("ATH0");  await delay(100); await consumeAtResponse()
            try await sendRaw("ATS0");  await delay(100); await consumeAtResponse()
            try await sendRaw("0100")
            dbg("\(tag) warmup: '\((await readUntilPrompt(timeoutMs: Self.WARMUP_TIMEOUT_MS)).cleanObd())'")
            await drainInput()
            dbg("\(tag): adapter state fully restored")
        } catch {
            warn("\(tag): restore failed: \(error.localizedDescription)")
        }
    }

    private func elmProtocolDescription() async -> String {
        do {
            await drainInput()
            try await sendRaw("ATDP")
            await delay(120)
            return await readUntilPrompt(timeoutMs: 1000)
        } catch {
            return ""
        }
    }

    /// UDS 0x22 на щиток (см. `ClusterOdometerProbes`); prelude — extended session где задано.
    /// Только CAN; в конце `restoreElmAfterAtsh`.
    private func tryReadClusterOdometerKm(detectedMake: String?, vin: String?) async -> (Int?, String?) {
        let proto = (await elmProtocolDescription()).uppercased()
        guard proto.contains("CAN") || proto.contains("15765") else { return (nil, nil) }
        let group = BrandEcuHints.classify(detectedMake: detectedMake, vin: vin)
        let probes = ClusterOdometerProbes.probes(for: group)
        if probes.isEmpty { return (nil, nil) }
        for probe in probes {
            do {
                try await sendRaw("ATSH \(probe.txHeader)")
                await delay(120)
                await consumeAtResponse()
                await drainInput()
                for pre in probe.preludeHex {
                    await drainInput()
                    try await sendRaw(pre)
                    await delay(200)
                    _ = await readUntilPrompt(timeoutMs: 1200)
                    await drainInput()
                }
                try await sendRaw(probe.requestHex)
                await delay(280)
                let raw = await readUntilPrompt(timeoutMs: 4000)
                let clean = normalizeElmMode09Raw(raw).cleanObd()
                if clean.contains("7F22") || clean.contains("7F31") { continue }
                guard let bytes = ClusterOdometerProbes.extractPayloadAfterMarker(clean, marker: probe.positiveMarker),
                      let km = ClusterOdometerProbes.parseOdometerKm(bytes) else { continue }
                dbg("Cluster odo OK: \(probe.groupLabel) \(probe.txHeader) \(probe.requestHex) -> \(km) km")
                await restoreElmAfterAtsh(tag: "clusterOdo")
                return (km, "\(probe.groupLabel) CAN \(probe.txHeader) UDS \(probe.requestHex)")
            } catch { continue }
        }
        await restoreElmAfterAtsh(tag: "clusterOdo")
        return (nil, nil)
    }

    /// Mode 09/0A на `7E1` — только при CAN (иначе `ATSH` ломает K-Line).
    private func tryReadTcmEcuName() async -> String? {
        let proto = (await elmProtocolDescription()).uppercased()
        guard proto.contains("CAN") || proto.contains("15765") else { return nil }
        let name: String?
        do {
            try await sendRaw("ATSH 7E1")
            await delay(120)
            await consumeAtResponse()
            await drainInput()
            try await sendRaw("090A")
            await delay(200)
            let raw = await readUntilPrompt(timeoutMs: 2000)
            name = parseEcuName(raw)
        } catch {
            name = nil
        }
        await restoreElmAfterAtsh(tag: "tryReadTcmEcuName")
        return name
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Other ECU DTCs (CAN Addressing)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Пробует считать DTC с нестандартных блоков: ABS, SRS, TCM, BCM.
    ///
    /// Работает **только на CAN-шине** (большинство машин с 2008+).
    /// Старые протоколы (K-Line, ISO 9141) не поддерживают адресацию блоков.
    ///
    /// **Механизм:** команда `ATSH` устанавливает 11-битный CAN-заголовок запроса.
    /// ELM327 отправляет `"03\r"` (Mode 03) с этим заголовком;
    /// ЭБУ целевого блока отвечает на `canId = txHeader + 8` (стандарт ISO 15765).
    ///
    /// **Типичные CAN-адреса** (могут отличаться у разных производителей):
    ///   - `7DF` — broadcast (OBD2 standard), ответ от `7E8`
    ///   - `7E0` — Engine ECU, ответ `7E8`
    ///   - `7E1` — TCM / АКПП, ответ `7E9`
    ///   - `7B0` — ABS / ESP, ответ `7B8`
    ///   - `7D0` — SRS / Airbag, ответ `7D8`
    ///   - `7E4` — BCM / Кузов, ответ `7EC`
    ///
    /// По `vehicleInfo` добавляются марочные адреса (`BrandEcuHints`): VW Group — `710`, `714`, `7B6`;
    /// часть Toyota/Lexus — `750`; Ford/Lincoln — `720`, `724`, `726`, `732`.
    ///
    /// **Восстановление после опроса:**
    /// После опроса всех блоков ATSH восстанавливается через `ATD` (Set All to Defaults).
    /// Затем: `ATE0`, `ATL0`, `ATH0`, `ATS0` — восстановление настроек, т.к. `ATD` сбрасывает всё.
    /// Финальный warmup `0100` — восстановление K-Line сессии, которая могла истечь
    /// за ~13 сек опроса 4 ЭБУ (P3_Max = 5 с).
    ///
    /// - Parameters:
    ///   - vehicleInfo: для выбора марочных CAN-ID; `nil` — только универсальный набор блоков.
    ///   - manualMakeHint: марка из ручного профиля — при пустом VIN всё равно добавляет марочные адреса.
    /// - Returns: Массив `EcuDtcResult` — по одному элементу на каждый опрошенный блок.
    func readOtherEcuDtcs(vehicleInfo: VehicleInfo? = nil, manualMakeHint: String? = nil) async -> [EcuDtcResult] {
        await ioMutex.withLock {
            let ecus = BrandEcuHints.ecuProbeList(
                detectedMake: vehicleInfo?.detectedMake,
                vin: vehicleInfo?.vin,
                manualMakeHint: manualMakeHint
            )

            await self.warmupIfNeeded()
            var results = [EcuDtcResult]()

            for ecu in ecus {
                do {
                    try await self.sendRaw("ATSH \(ecu.txHeader)")
                    await self.delay(100)
                    await self.consumeAtResponse()

                    // ── Шаг 1: стандартный OBD2 Mode 03 ────────────────────────
                    try await self.sendRaw("03")
                    let raw = await self.readUntilPrompt(timeoutMs: 1500)
                    let clean = raw.cleanObd()
                    let blockResponds = !clean.contains("NODATA") && !clean.contains("UNABLE") &&
                        !clean.contains("ERROR") && !clean.isEmpty
                    var confirmed: DtcResult
                    if !blockResponds {
                        confirmed = .error("Блок не отвечает")
                    } else if clean.contains("43") {
                        confirmed = self.parseDtcResponse(responseMarker: "43", raw: raw)
                    } else {
                        confirmed = .error("Нет ответа")
                    }
                    var pending: DtcResult = .noDtcs
                    var permanent: DtcResult = .noDtcs
                    let mode03Failed = !blockResponds || confirmed.isError

                    if blockResponds && !mode03Failed {
                        do {
                            await self.drainInput()
                            try await self.sendRaw("07")
                            let raw07 = await self.readUntilPrompt(timeoutMs: 1500)
                            if raw07.cleanObd().contains("47") {
                                pending = self.parseDtcResponse(responseMarker: "47", raw: raw07)
                            }
                        } catch { /* optional */ }
                        do {
                            await self.drainInput()
                            try await self.sendRaw("0A")
                            let raw0A = await self.readUntilPrompt(timeoutMs: 1500)
                            if raw0A.cleanObd().contains("4A") {
                                permanent = self.parseDtcResponse(responseMarker: "4A", raw: raw0A)
                            }
                        } catch { /* optional */ }
                    }

                    // ── Шаг 2: UDS 0x19 fallback (только CAN) ──────────────────
                    if mode03Failed && isCanProtocol {
                        do {
                            await self.drainInput()
                            try await self.sendRaw("10 03")
                            await self.delay(200)
                            let _ = await self.readUntilPrompt(timeoutMs: 1500)
                            await self.drainInput()
                            try await self.sendRaw("19 02 FF")
                            let rawUds = await self.readUntilPrompt(timeoutMs: 3000)
                            let udsResult = self.parseUdsDtcResponse(rawUds)
                            if !udsResult.isError {
                                confirmed = udsResult
                                dbg("UDS 0x19 OK for \(ecu.txHeader): \(udsResult)")
                            } else {
                                dbg("UDS 0x19 failed for \(ecu.txHeader): \(udsResult)")
                            }
                        } catch {
                            dbg("UDS 0x19 exception for \(ecu.txHeader): \(error.localizedDescription)")
                        }
                    }

                    results.append(EcuDtcResult(name: ecu.name, address: ecu.txHeader, result: confirmed, pendingResult: pending, permanentResult: permanent))
                } catch {
                    results.append(EcuDtcResult(name: ecu.name, address: ecu.txHeader, result: .error("Ошибка связи")))
                }
                await self.drainInput()
            }

            await self.restoreElmAfterAtsh(tag: "readOtherEcuDtcs")
            return results
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Live Sensor (Mode 01)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Запрашивает один PID в режиме текущих данных (Mode 01) и возвращает `SensorReading`.
    ///
    /// Формат запроса: команда вида `"010C\r"` → `"41 0C 1A F8 >"`
    ///   - `41` = 0x40 | 0x01 — положительный ответ Mode 01
    ///   - `0C` = эхо PID
    ///   - `1A F8` = данные; RPM = (0x1A × 256 + 0xF8) / 4 = 1726 об/мин
    ///
    /// Таймаут `SENSOR_TIMEOUT_WIFI_MS` = 800 мс (на iOS только Wi-Fi).
    ///
    /// **Стратегия мьютекса:** `tryLock()` — если DTC-скан держит мьютекс, немедленно
    /// возвращает `.error` (N/A в UI), не блокируя весь цикл мониторинга на время скана.
    ///
    /// Если ЭБУ ответил «NO DATA» или «?» — PID не поддерживается этой машиной,
    /// возвращается `.unsupported` (не ошибка, карточка скрывается из сетки).
    ///
    /// - Parameter pid: Описание PID для запроса (команда, декодер, пороги).
    /// - Returns: `SensorReading` с декодированным значением и статусом.
    func pollSensor(pid: ObdPid) async -> SensorReading {
        guard isConnected else { return SensorReading(pid: pid, value: nil, status: .disconnected) }
        guard ioMutex.tryLock() else { return SensorReading(pid: pid, value: nil, status: .error) }
        defer { ioMutex.unlock() }

        do {
            await warmupIfNeeded()
            await drainInput()
            try await sendRaw(pid.command)
            let raw = await readUntilPrompt(timeoutMs: Self.SENSOR_TIMEOUT_WIFI_MS)
            return parseSensorResponse(pid: pid, raw: raw)
        } catch {
            warn("pollSensor \(pid.command) error: \(error.localizedDescription)")
            return SensorReading(pid: pid, value: nil, status: .error)
        }
    }

    /// Парсит ответ ЭБУ на запрос live PID (Mode 01) и возвращает `SensorReading`.
    ///
    /// Логика:
    /// 1. Если `SEARCHING` — адаптер ещё определяет протокол → `.error` (не `.unsupported`).
    /// 2. Если `NODATA` / `UNABLE` / `ERROR` / `?` / пусто → `.unsupported` (PID не поддерживается).
    /// 3. Ищет маркер `"41"` (positive response Mode 01), парсит hex-байты.
    /// 4. Вызывает `pid.decode(bytes)` для получения float-значения.
    /// 5. Сравнивает с `minWarning`/`maxWarning` для определения статуса.
    ///
    /// - Parameters:
    ///   - pid: Описание PID (нужен декодер и пороги).
    ///   - raw: Сырой ответ от `readUntilPrompt`.
    /// - Returns: `SensorReading` с декодированным значением и статусом.
    private func parseSensorResponse(pid: ObdPid, raw: String) -> SensorReading {
        let clean = raw.cleanObd()

        if clean.contains("SEARCHING") {
            return SensorReading(pid: pid, value: nil, status: .error)
        }
        if clean.contains("NODATA") || clean.contains("UNABLE") ||
           clean.contains("ERROR")  || clean == "?" || clean.isEmpty {
            return SensorReading(pid: pid, value: nil, status: .unsupported)
        }

        guard let bytes = parseHexBytes(from: clean, marker: "41"),
              bytes.count >= 3 else {
            return SensorReading(pid: pid, value: nil, status: .unsupported)
        }

        let value = pid.decode(bytes)
        let status: SensorStatus
        if let max = pid.maxWarning, value > max       { status = .warning }
        else if let min = pid.minWarning, value < min  { status = .warning }
        else                                            { status = .ok }
        return SensorReading(pid: pid, value: value, status: status)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Hex Parsing Helpers
    // ═══════════════════════════════════════════════════════════════════════════

    /// Находит `marker` в очищенной hex-строке и парсит все последующие hex-пары в массив `Int`.
    ///
    /// Пример: `parseHexBytes(from: "410C1AF8", marker: "41")` → `[0x41, 0x0C, 0x1A, 0xF8]`.
    ///
    /// Используется для разбора ответов Mode 01/02/03/07 и PID 0x01 (readiness).
    ///
    /// - Parameters:
    ///   - cleaned: Строка после `cleanObd()` (без пробелов, uppercase).
    ///   - marker: Hex-маркер начала ответа (напр. `"41"`, `"43"`, `"4101"`).
    /// - Returns: Массив Int от маркера до конца строки, или `nil` если маркер не найден.
    func parseHexBytes(from cleaned: String, marker: String) -> [Int]? {
        guard let idx = cleaned.range(of: marker)?.lowerBound else { return nil }
        return stride(from: 0, to: cleaned[idx...].count, by: 2).compactMap { offset in
            let start = cleaned.index(idx, offsetBy: offset)
            guard cleaned.distance(from: start, to: cleaned.endIndex) >= 2 else { return nil }
            return Int(cleaned[start..<cleaned.index(start, offsetBy: 2)], radix: 16)
        }
    }

    /// Убирает PCI ELM, индексы ISO-TP (`0:`, `1:`) **без** склейки hex в один токен
    /// (иначе ломается VIN: ложные `4331:` внутри данных после удаления пробелов).
    private func normalizeElmMode09Raw(_ raw: String) -> String {
        var s = String(raw.uppercased().prefix { $0 != ">" })
        s = s.replacingOccurrences(
            of: #"SEARCHING\.\.\.[^\r\n>]*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let sep = "\u{001E}"
        s = s.replacingOccurrences(of: #"\s+\d{1,2}:\s*"#, with: sep, options: .regularExpression)
        let parts = s.components(separatedBy: sep)
        var out = ""
        for (i, part) in parts.enumerated() {
            let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if i == 0, t.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil { continue }
            out.append(t)
        }
        return out.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    /// Парсит Mode 09 ASCII-ответ (VIN / ECU name): нормализует ELM ISO-TP, находит маркер,
    /// пропускает опциональный `"01"` sub-index, декодирует hex-байты в ASCII.
    ///
    /// - Parameters:
    ///   - raw: Сырой ответ от `readUntilPrompt`.
    ///   - marker: Hex-маркер (напр. `"4902"` для VIN, `"490A"` для ECU name).
    ///   - maxChars: Максимальное количество символов в результате.
    /// - Returns: Декодированная строка или `nil` при ошибке / маркер не найден.
    private func parseMode09Ascii(_ raw: String, marker: String, maxChars: Int) -> String? {
        let clean = normalizeElmMode09Raw(raw)
        return parseMode09AsciiFromCleaned(clean, marker: marker, maxChars: maxChars)
    }

    /// То же для уже нормализованной строки и смещения поиска маркера (несколько `490A` в буфере).
    private func parseMode09AsciiFromCleaned(
        _ clean: String,
        marker: String,
        maxChars: Int,
        searchFrom: String.Index? = nil
    ) -> String? {
        let start = searchFrom ?? clean.startIndex
        guard let markerRange = clean.range(of: marker, range: start..<clean.endIndex) else { return nil }
        var idx = markerRange.upperBound
        if clean.distance(from: idx, to: clean.endIndex) > 2,
           String(clean[idx..<clean.index(idx, offsetBy: 2)]) == "01" {
            idx = clean.index(idx, offsetBy: 2)
        }
        // Multi-ECU: ограничиваем чтение до следующего маркера,
        // иначе парсер захватывает мусор из соседних ЭБУ-фреймов.
        let boundary: String.Index
        if let nextMarker = clean.range(of: marker, range: idx..<clean.endIndex) {
            boundary = nextMarker.lowerBound
        } else {
            boundary = clean.endIndex
        }
        var result = ""
        var pos = idx
        while clean.distance(from: pos, to: boundary) >= 2 && result.count < maxChars {
            let end = clean.index(pos, offsetBy: 2)
            guard let byte = UInt8(String(clean[pos..<end]), radix: 16) else { break }
            if byte == 0 { break }
            let scalar = UnicodeScalar(byte)
            if scalar.value >= 32 && scalar.value <= 126 {
                result.append(Character(scalar))
            }
            pos = end
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 2 ? trimmed : nil
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - IO Helpers
    // ═══════════════════════════════════════════════════════════════════════════

    /// Отправляет AT/OBD2-команду в TCP-поток.
    ///
    /// ELM327 требует завершающий `\r` (Carriage Return) — без него команда игнорируется.
    /// ISO 8859-1 (Latin-1) используется вместо UTF-8, т.к. ELM327 — ASCII-устройство.
    ///
    /// Обновляет `lastEcuCommandMs` только для OBD2-команд (не AT).
    /// K-Line P3_Max отсчитывается от последней ECU-транзакции на шине;
    /// AT-команды обрабатываются ELM327 локально и не затрагивают шину.
    ///
    /// - Parameter command: Строка команды без `\r` (напр. `"010C"`, `"ATZ"`).
    /// - Throws: `ObdError.notConnected` если нет активного соединения.
    private func sendRaw(_ command: String) async throws {
        guard let connection = connection else { throw ObdError.notConnected }
        guard let data = "\(command)\r".data(using: .isoLatin1) else { throw ObdError.notConnected }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error { cont.resume(throwing: error) }
                else                 { cont.resume() }
            })
        }

        dbg(">> \(command)")
        if !command.uppercased().hasPrefix("AT") {
            lastEcuCommandMs = Self.currentTimeMs()
        }
    }

    /// Читает байты до символа `>` (prompt ELM327) или таймаута.
    ///
    /// **Рекурсивный pump-паттерн:**
    /// `NWConnection` не поддерживает синхронные блокирующие чтения (в отличие от
    /// `InputStream` в Android). Вместо цикла `while (stream.read())` используется
    /// рекурсивная цепочка: `pump() → connection.receive() → callback → pump()`.
    ///
    /// Каждый вызов `connection.receive()` запрашивает 1–4096 байт. Когда callback
    /// получает данные, они побайтово добавляются в `ReadState.buffer`. Если встречен
    /// `>` или произошла ошибка/EOF — вызывается `finish()` через `ContinuationGuard`.
    ///
    /// Timeout: `queue.asyncAfter` устанавливает таймер на `timeoutMs`. При срабатывании
    /// вызывается `finish()` — если данные ещё не получены, continuation resume'ится
    /// с тем, что накоплено в буфере (может быть пустая строка).
    ///
    /// **Аналог Android:** `readUntilPrompt()` с блокирующим `InputStream.read()` в цикле.
    /// На Android для Wi-Fi устанавливается `soTimeout` на сокете; на iOS — таймер на queue.
    ///
    /// - Parameter timeoutMs: Максимальное время ожидания ответа (мс).
    /// - Returns: Строка ответа (без символа `>`). Может быть пустой при таймауте.
    private func readUntilPrompt(timeoutMs: Int = READ_TIMEOUT_MS) async -> String {
        guard let connection = connection else { return "" }

        return await withCheckedContinuation { (outerCont: CheckedContinuation<String, Never>) in
            let state = ReadState()

            func finish() {
                guard state.guard_.claim() else { return }
                let result = String(data: state.buffer, encoding: .isoLatin1) ?? ""
                let preview = result
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                let short = preview.isEmpty ? "(empty)" : (preview.count > 120 ? String(preview.prefix(120)) + "…" : preview)
                dbg("<< \(short)")
                outerCont.resume(returning: result)
            }

            self.queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) { finish() }

            func pump() {
                guard !state.guard_.isDone else { return }
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                    guard !state.guard_.isDone else { return }
                    if let data = data {
                        for byte in data {
                            if byte == UInt8(ascii: ">") {
                                finish()
                                return
                            }
                            state.buffer.append(byte)
                        }
                    }
                    if error != nil || isComplete {
                        finish()
                    } else {
                        pump()
                    }
                }
            }

            self.queue.async { pump() }
        }
    }

    /// Поглощает ответ на AT-команду (например `"OK>"`) после её выполнения.
    ///
    /// Для Wi-Fi TCP обязательно использовать `readUntilPrompt()`:
    /// без этого `"OK>"` накапливаются в TCP-буфере и сбивают парсинг следующих запросов.
    ///
    /// Аналог Android: `consumeAtResponse()` — для Wi-Fi `readUntilPrompt`, для BT `drainInput`.
    /// На iOS только Wi-Fi, поэтому всегда `readUntilPrompt`.
    ///
    /// - Parameter timeoutMs: Таймаут чтения (мс). По умолчанию 1000 мс — AT-ответы быстрые.
    private func consumeAtResponse(timeoutMs: Int = 1000) async {
        _ = await readUntilPrompt(timeoutMs: timeoutMs)
    }

    /// Проверяет, не истекла ли K-Line / KWP2000 сессия (P3_Max = 5 с), и если да —
    /// отправляет `0100` для её восстановления.
    ///
    /// **Вызывать внутри `ioMutex`** — использует сырой I/O без дополнительной блокировки.
    ///
    /// **Поведение по таймаутам:**
    ///   - CAN (большинство машин 2008+): ответ `0100` за ~200 мс.
    ///   - K-Line активная (пауза ≤ P3_Max): ~300 мс.
    ///   - K-Line истёкшая (пауза > 5 с): 5-baud re-init 5–7 с, таймаут 9 с — допустимо.
    ///
    /// **Восстановление через ATPC:**
    /// Если warmup `0100` вернул `NODATA`/пустой ответ — K-Line сессия мертва: ELM327
    /// послал команду в истёкшую сессию. `ATPC` (Protocol Close) закрывает её в ELM327,
    /// следующий `0100` делает 5-baud re-init «с нуля».
    ///
    /// Аналог Android: `warmupIfNeeded()` с тем же порогом 3.5 с и той же логикой ATPC.
    private func warmupIfNeeded() async {
        let idleMs = Self.currentTimeMs() - lastEcuCommandMs
        guard idleMs > Self.WARMUP_IDLE_THRESHOLD_MS else { return }
        info("⚡ warmup: idle \(idleMs)ms > \(Self.WARMUP_IDLE_THRESHOLD_MS)ms → 0100")
        await drainInput()
        try? await sendRaw("0100")
        let resp = (await readUntilPrompt(timeoutMs: Self.WARMUP_TIMEOUT_MS)).cleanObd()
        await drainInput()

        if resp.isEmpty || resp.contains("NODATA") || resp.contains("UNABLE") || resp.contains("ERROR") {
            warn("warmup got '\(resp)' → ATPC + re-init 0100")
            try? await sendRaw("ATPC")
            await delay(500)
            await consumeAtResponse()
            try? await sendRaw("0100")
            let resp2 = (await readUntilPrompt(timeoutMs: Self.WARMUP_TIMEOUT_MS)).cleanObd()
            info("warmup retry: '\(resp2)'")
            await drainInput()
        } else {
            info("warmup OK: '\(resp)'")
        }
    }

    /// Восстанавливает сессию после Mode 04 (Clear DTC). ЭБУ перезагружается — нужна пауза.
    ///
    /// **Алгоритм:**
    /// 1. `delay(POST_CLEAR_DELAY_MS)` — ЭБУ завершает внутренний сброс (на некоторых авто 2+ с).
    /// 2. `drainInput()` — очищаем байты, накопившиеся в буфере за время перезагрузки.
    /// 3. `ATPC` — закрываем мёртвую K-Line сессию в ELM327; без этого ELM327 шлёт
    ///    команды в старую сессию → `NO DATA`.
    /// 4. `0100` — принудительная переинициализация: CAN ~200 мс, K-Line 5–7 с.
    ///
    /// Аналог Android: `postClearWarmup()` с тем же алгоритмом.
    private func postClearWarmup() async {
        info("⚡ postClearWarmup: waiting for ECU reboot after Mode 04…")
        await delay(Self.POST_CLEAR_DELAY_MS)
        await drainInput()
        try? await sendRaw("ATPC"); await delay(500); await consumeAtResponse()
        try? await sendRaw("0100")
        let resp = (await readUntilPrompt(timeoutMs: Self.WARMUP_TIMEOUT_MS)).cleanObd()
        info("postClearWarmup done: '\(resp)'")
        await drainInput()
    }

    /// Пауза между I/O-операциями для предотвращения наложения ответов.
    ///
    /// **Почему не используется `connection.receive()` для drain:**
    /// NWConnection не поддерживает отмену отдельного `receive()`. Если зарегистрировать
    /// `connection.receive()` и завершить drain по таймеру — обработчик останется в очереди
    /// NWConnection и «съест» данные следующего `readUntilPrompt`. На Android такой проблемы
    /// нет: `InputStream.read()` — синхронный блокирующий вызов, после `SocketTimeoutException`
    /// ничего в очереди не остаётся.
    ///
    /// 50 мс достаточно для inter-command gap. В штатном режиме (предыдущий `readUntilPrompt`
    /// успешно получил `>`) в буфере нет остатков; при таймауте предыдущего чтения остатки
    /// попадут в начало следующего ответа, но парсеры (`parseHexBytes`, `parseDtcResponse`)
    /// ищут маркеры и игнорируют мусор перед ними.
    private func drainInput() async {
        guard connection != nil else { return }
        await delay(50)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - DTC Parsing
    // ═══════════════════════════════════════════════════════════════════════════

    /// Разбирает ответ на запрос DTC (Mode 03 или Mode 07).
    ///
    /// - Parameters:
    ///   - responseMarker: Hex-строка маркера ответа: `"43"` для Mode 03, `"47"` для Mode 07.
    ///   - raw: Сырой ответ адаптера (до `cleanObd`).
    ///   - missingMarkerResult: Что вернуть, если маркер не найден.
    ///     - Mode 03: `.rawResponse` (нестандартный ответ — показываем «как есть»).
    ///     - Mode 07: `.noDtcs` (отсутствие маркера = ожидающих кодов нет — норма).
    /// - Returns: `DtcResult` — список кодов, «нет ошибок» или описание ошибки.
    private func parseDtcResponse(
        responseMarker: String,
        raw: String,
        missingMarkerResult: DtcResult = .rawResponse("")
    ) -> DtcResult {
        let missingResult: DtcResult
        if case .rawResponse = missingMarkerResult {
            missingResult = .rawResponse(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            missingResult = missingMarkerResult
        }

        let clean = raw.cleanObd()
        if clean.contains("SEARCHING") {
            return .error("Адаптер ищёт протокол OBD2. Убедитесь, что зажигание включено, и повторите")
        }
        guard clean.contains(responseMarker) else { return missingResult }

        var dtcs = Set<String>()

        // CAN: каждый ЭБУ отвечает отдельным фреймом через пробел/перенос
        let tokens = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        for token in tokens {
            let hex = token.replacingOccurrences(of: "^\\d+:", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[^0-9A-Fa-f]", with: "", options: .regularExpression)
                .uppercased()
            guard hex.hasPrefix(responseMarker) else { continue }
            let data = String(hex.dropFirst(responseMarker.count))
            if data.isEmpty || data.hasPrefix("00") { continue }
            parseDtcFrameData(data, into: &dtcs)
        }

        // Fallback для ISO-TP multi-frame (0: 1: 2: …)
        if dtcs.isEmpty, let r = clean.range(of: responseMarker) {
            let data = String(clean[clean.index(r.lowerBound, offsetBy: responseMarker.count)...])
            if !data.isEmpty, !data.hasPrefix("00") {
                parseDtcFrameData(data, into: &dtcs)
            }
        }
        return dtcs.isEmpty ? .noDtcs : .dtcList(Array(dtcs))
    }

    /// Парсит DTC-данные одного ЭБУ (после маркера 43/47/4A).
    /// На CAN первый байт — количество кодов; на K-Line / KWP / J1850 — сразу DTC-пары.
    /// `isCanProtocol` определяется при инициализации по ATDP.
    private func parseDtcFrameData(_ data: String, into out: inout Set<String>) {
        guard data.count >= 2,
              let firstByte = UInt8(String(data.prefix(2)), radix: 16) else { return }
        let skipCount = isCanProtocol && firstByte >= 1 && data.count >= 2 + Int(firstByte) * 4
        let start = data.index(data.startIndex, offsetBy: skipCount ? 2 : 0)
        let maxPairs = skipCount ? Int(firstByte) : data.count / 4
        var i = start
        var read = 0
        while data.distance(from: i, to: data.endIndex) >= 4, read < maxPairs {
            let end = data.index(i, offsetBy: 4)
            let block = String(data[i..<end])
            if block != "0000" { out.insert(decodeDtc(block)) }
            i = end
            read += 1
        }
    }

    /// Декодирует 4-hex-символьный DTC в стандартный формат (P0420, C0031, B1000, U0100).
    ///
    /// Кодировка OBD2 SAE J2012:
    ///   Старший nibble первого байта определяет систему:
    ///     0–3 → P (Powertrain — двигатель/трансмиссия)
    ///     4–7 → C (Chassis — шасси/тормоза)
    ///     8–B → B (Body — кузов/салон)
    ///     C–F → U (Network/Undefined — CAN-шина)
    ///   Второй символ = firstNibble % 4 (тип: 0=ISO/SAE, 1=manufacturer, 2/3=reserved).
    ///   Оставшиеся 3 hex-символа — специфический номер ошибки.
    ///
    /// Пример: hex `"0143"` → firstNibble=0 → `"P"`, остаток=`"143"` → `"P0143"`.
    ///
    /// - Parameter hex: 4-символьная hex-строка (2 байта DTC).
    /// - Returns: Стандартное обозначение DTC (напр. `"P0420"`).
    func decodeDtc(_ hex: String) -> String {
        guard hex.count >= 4, let first = hex.first,
              let firstNibble = Int(String(first), radix: 16) else { return hex }
        let system: String
        switch firstNibble {
        case 0...3:   system = "P"
        case 4...7:   system = "C"
        case 8...11:  system = "B"
        default:      system = "U"
        }
        return "\(system)\(firstNibble % 4)\(hex.dropFirst())"
    }

    static func decodeFuelSystemStatus(_ byte1: Int, _ byte2: Int) -> String? {
        func label(_ b: Int) -> String? {
            switch b {
            case 0:    return nil
            case 0x01: return "Open loop (холодный)"
            case 0x02: return "Closed loop (O₂)"
            case 0x04: return "Open loop (нагрузка)"
            case 0x08: return "Open loop (сбой)"
            case 0x10: return "Closed loop (сбой O₂)"
            default:   return String(format: "0x%02X", b)
            }
        }
        let parts = [label(byte1), label(byte2)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - VIN / ECU Parsing
    // ═══════════════════════════════════════════════════════════════════════════

    /// Парсит ответ на запрос VIN (Mode 09 PID 02).
    ///
    /// ELM327 возвращает ответ в формате ISO-TP:
    ///   `"0: 49 02 01 XX XX XX\n1: XX XX XX XX XX XX\n2: XX XX XX XX XX XX"`
    /// Номера строк (`"0:"`, `"1:"`) и разделители удаляются, затем ищется маркер `"4902"`.
    /// После маркера: опциональный счётчик `"01"`, затем 17×2 hex-символов VIN.
    ///
    /// VIN фильтруется по ISO 3779: только `[A-Z0-9]`, исключая `I`, `O`, `Q`.
    ///
    /// - Parameter raw: Сырой ответ от `readUntilPrompt`.
    /// - Returns: 17-символьный VIN или `nil` при ошибке.
    func parseVin(_ raw: String) -> String? {
        guard let ascii = parseMode09Ascii(raw, marker: "4902", maxChars: Self.VIN_LENGTH * 2) else { return nil }
        // VIN: filter to alphanumeric, exclude I/O/Q per ISO 3779
        let vin = String(ascii.filter { ch in
            (ch.isLetter || ch.isNumber) && ch != "I" && ch != "O" && ch != "Q"
        }.prefix(Self.VIN_LENGTH))
        return vin.count == Self.VIN_LENGTH ? vin : nil
    }

    /// Парсит ответ на запрос ECU Name (Mode 09 PID 0A).
    ///
    /// Аналогично VIN, но маркер = `"490A"`, строка ASCII до нулевого байта или `MAX_ECU_NAME_LENGTH`.
    ///
    /// - Parameter raw: Сырой ответ от `readUntilPrompt`.
    /// - Returns: Название ЭБУ или `nil` при ошибке / пустом ответе.
    func parseEcuName(_ raw: String) -> String? {
        let clean = normalizeElmMode09Raw(raw)
        var best: String?
        var searchFrom = clean.startIndex
        while searchFrom < clean.endIndex,
              let r = clean.range(of: "490A", range: searchFrom..<clean.endIndex) {
            if let name = parseMode09AsciiFromCleaned(clean, marker: "490A", maxChars: Self.MAX_ECU_NAME_LENGTH, searchFrom: r.lowerBound),
               Self.isPlausibleEcuDisplayName(name) {
                if best == nil || name.count > best!.count { best = name }
            }
            searchFrom = r.upperBound
        }
        return best
    }

    /// Отсекает мусор из ASCII 09/0A (битая выдача вместо имени ЭБУ).
    private static func isPlausibleEcuDisplayName(_ s: String) -> Bool {
        if s.contains("&") || s.contains("\u{7F}") { return false }
        let letters = s.filter { $0.isLetter }.count
        if letters < 3 { return false }
        let digits = s.filter { $0.isNumber }.count
        if digits > s.count / 2 { return false }
        return true
    }

    /// Декодирует производителя/завод из первых трёх символов VIN (WMI).
    /// Таблица `VinWmiTable` (Wikibooks WMI, ~2100 кодов); при отсутствии кода — `nil`.
    func decodeVinMake(_ vin: String) -> String? {
        guard vin.count >= 3 else { return nil }
        return VinWmiTable.getMake(wmi: String(vin.prefix(3)))
    }

    /// Декодирует модельный год из VIN (SAE J1044, 30-летний цикл).
    ///
    /// - **Северная Америка** (WMI `1`…`5`): 7-й символ — цифра ⇒ новый цикл, иначе старый.
    /// - **Остальной мир**: выбирается вариант **ближе к текущему году** (EU/RU VIN с буквой
    ///   на 7-й позиции иначе даёт ложный «1991» для кода `M` и т.п.).
    func decodeVinYear(_ vin: String) -> String? {
        guard vin.count >= 10 else { return nil }
        let u = vin.uppercased()
        let i0 = u.startIndex
        let wmi3 = String(u.prefix(3))
        // WDB Mercedes: 10-й символ в европейском VIN не кодирует год
        if wmi3 == "WDB" { return nil }
        let pos7 = u[u.index(i0, offsetBy: 6)]
        let pos10 = u[u.index(i0, offsetBy: 9)]
        let wmi0 = u[i0]
        guard let pair = Self.vinYearPair(pos10) else { return nil }
        let ref = Calendar.current.component(.year, from: Date())
        let year: Int
        if wmi0.isNumber, let d = Int(String(wmi0)), (1...5).contains(d) {
            year = pos7.isNumber ? pair.new : pair.old
        } else {
            let a = abs(pair.old - ref)
            let b = abs(pair.new - ref)
            if b < a { year = pair.new }
            else if a < b { year = pair.old }
            else { year = pair.new }
        }
        return String(year)
    }

    private static func vinYearPair(_ c: Character) -> (old: Int, new: Int)? {
        switch c {
        case "A": return (1980, 2010); case "B": return (1981, 2011); case "C": return (1982, 2012)
        case "D": return (1983, 2013); case "E": return (1984, 2014); case "F": return (1985, 2015)
        case "G": return (1986, 2016); case "H": return (1987, 2017); case "J": return (1988, 2018)
        case "K": return (1989, 2019); case "L": return (1990, 2020); case "M": return (1991, 2021)
        case "N": return (1992, 2022); case "P": return (1993, 2023); case "R": return (1994, 2024)
        case "S": return (1995, 2025); case "T": return (1996, 2026); case "V": return (1997, 2027)
        case "W": return (1998, 2028); case "X": return (1999, 2029); case "Y": return (2000, 2030)
        case "1": return (2001, 2031); case "2": return (2002, 2032); case "3": return (2003, 2033)
        case "4": return (2004, 2034); case "5": return (2005, 2035); case "6": return (2006, 2036)
        case "7": return (2007, 2037); case "8": return (2008, 2038); case "9": return (2009, 2039)
        default: return nil
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Error Messages
    // ═══════════════════════════════════════════════════════════════════════════

    /// Переводит низкоуровневую ошибку NWConnection в понятный пользователю текст на русском.
    ///
    /// Аналог Android: `friendlyWifiError()` с тем же набором проверок.
    ///
    /// - Parameter e: Ошибка от NWConnection или системы.
    /// - Returns: Человекочитаемое описание проблемы и совет по исправлению.
    func friendlyWifiError(_ e: Error) -> String {
        let msg = e.localizedDescription.lowercased()
        if msg.contains("connect") || msg.contains("refused") || msg.contains("timed out") || msg.contains("timeout") {
            return "Не удалось подключиться. Убедитесь: подключены к Wi-Fi сети адаптера, зажигание ON"
        }
        if msg.contains("host") || msg.contains("network") {
            return "Адрес адаптера не найден. Проверьте IP-адрес и порт"
        }
        return "Ошибка Wi-Fi: \(type(of: e)) — \(e.localizedDescription)"
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Utility
    // ═══════════════════════════════════════════════════════════════════════════

    /// Асинхронная задержка на указанное количество миллисекунд.
    /// Обёртка над `Task.sleep` для удобства (Android-аналог: `kotlinx.coroutines.delay`).
    private func delay(_ ms: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }

    /// Текущее время в миллисекундах (epoch). Используется для отслеживания `lastEcuCommandMs`.
    /// Аналог Android: `System.currentTimeMillis()`.
    private static func currentTimeMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - UNIVERSAL_PIDS
// ═══════════════════════════════════════════════════════════════════════════════

/// Стандартные OBD2 PIDs Mode 01 (28 параметров), которые работают на всех машинах
/// с OBD2 (1996+) при условии исправного ЭБУ.
///
/// Не все ЭБУ поддерживают все PIDs — если машина не отвечает на конкретный PID,
/// `pollSensor` вернёт статус `.unsupported`, и карточка не отображается в UI.
///
/// Формат команды: `"01"` + hex(PID). Ответ: `"41"` + hex(PID) + байты данных.
///
/// Каждый `ObdPid` содержит замыкание `decode`, которое принимает массив `[Int]`
/// (распарсенные hex-байты ответа) и возвращает `Float`. Формулы декодирования
/// соответствуют стандарту SAE J1979 / ISO 15031-5.
///
/// Аналог Android: `val UNIVERSAL_PIDS = listOf(...)` — тот же набор из 28 PIDs.
let UNIVERSAL_PIDS: [ObdPid] = [

    // ── Основные параметры двигателя ─────────────────────────────────────────

    /// RPM: PID 0x0C, 2 байта. Формула: (A×256+B)/4 → об/мин.
    /// Пороги: 500–7000 об/мин (ниже — двигатель глохнет, выше — красная зона большинства ДВС).
    ObdPid(command: "010C", shortCode: "RPM",  name: "Обороты двигателя",          unit: "об/мин", minWarning: 500, maxWarning: 7000,
           decode: { b in b.count >= 4 ? Float((b[2] * 256) + b[3]) / 4.0 : 0 }),

    /// Speed: PID 0x0D, 1 байт. Значение прямо в км/ч (диапазон 0–255).
    /// Верхний порог 280 км/ч — выше этого на дорогах общего пользования ненормально.
    ObdPid(command: "010D", shortCode: "SPD",  name: "Скорость",                   unit: "км/ч",   minWarning: nil, maxWarning: 280,
           decode: { b in b.count >= 3 ? Float(b[2]) : 0 }),

    /// Calculated Engine Load: PID 0x04, 1 байт. Формула: A×100/255 → %.
    ObdPid(command: "0104", shortCode: "ENG",  name: "Нагрузка двигателя",         unit: "%",      minWarning: nil, maxWarning: 100,
           decode: { b in b.count >= 3 ? Float(b[2]) * 100.0 / 255.0 : 0 }),

    /// Throttle Position: PID 0x11, 1 байт. Формула: A×100/255 → %.
    ObdPid(command: "0111", shortCode: "TPS",  name: "Положение дросселя",         unit: "%",      minWarning: nil, maxWarning: 100,
           decode: { b in b.count >= 3 ? Float(b[2]) * 100.0 / 255.0 : 0 }),

    /// Engine Run Time: PID 0x1F, 2 байта. Формула: A×256+B → секунды.
    ObdPid(command: "011F", shortCode: "RUN",  name: "Время работы двигателя",     unit: "сек",    minWarning: nil, maxWarning: nil,
           decode: { b in b.count >= 4 ? Float((b[2] * 256) + b[3]) : 0 }),

    // ── Температуры ──────────────────────────────────────────────────────────

    /// Coolant Temperature: PID 0x05, 1 байт. Формула: A-40 → °C (диапазон -40…+215).
    /// Пороги: 70–115 °C (ниже — двигатель не прогрет, выше — перегрев).
    ObdPid(command: "0105", shortCode: "ECT",  name: "Охлаждающая жидкость",       unit: "°C",     minWarning: 70, maxWarning: 115,
           decode: { b in b.count >= 3 ? Float(b[2] - 40) : 0 }),

    /// Intake Air Temperature: PID 0x0F, 1 байт. Формула: A-40 → °C.
    /// Верхний порог 60 °C — перегрев впуска снижает мощность.
    ObdPid(command: "010F", shortCode: "IAT",  name: "Температура воздуха впуска", unit: "°C",     minWarning: nil, maxWarning: 60,
           decode: { b in b.count >= 3 ? Float(b[2] - 40) : 0 }),

    /// Ambient Air Temperature: PID 0x46, 1 байт. Формула: A-40 → °C.
    ObdPid(command: "0146", shortCode: "AMB",  name: "Температура окружающей среды", unit: "°C",   minWarning: nil, maxWarning: nil,
           decode: { b in b.count >= 3 ? Float(b[2] - 40) : 0 }),

    /// Engine Oil Temperature: PID 0x5C, 1 байт. Формула: A-40 → °C.
    /// Верхний порог 130 °C — выше деградирует масло.
    ObdPid(command: "015C", shortCode: "OIL",  name: "Температура масла",          unit: "°C",     minWarning: nil, maxWarning: 130,
           decode: { b in b.count >= 3 ? Float(b[2] - 40) : 0 }),

    // ── Давление / поток воздуха ──────────────────────────────────────────────

    /// Intake Manifold Absolute Pressure (MAP): PID 0x0B, 1 байт. Значение прямо в кПа.
    /// Пороги: 20–105 кПа (ниже — возможна утечка вакуума, выше — атмосферное давление / наддув).
    ObdPid(command: "010B", shortCode: "MAP",  name: "Давление впуска (MAP)",      unit: "кПа",    minWarning: 20, maxWarning: 105,
           decode: { b in b.count >= 3 ? Float(b[2]) : 0 }),

    /// Mass Air Flow (MAF): PID 0x10, 2 байта. Формула: (A×256+B)/100 → г/с.
    ObdPid(command: "0110", shortCode: "MAF",  name: "Массовый расход воздуха",    unit: "г/с",    minWarning: nil, maxWarning: nil,
           decode: { b in b.count >= 4 ? Float((b[2] * 256) + b[3]) / 100.0 : 0 }),

    /// Barometric Pressure: PID 0x33, 1 байт. Значение прямо в кПа.
    /// Пороги: 85–105 кПа (нормальное атмосферное давление на уровне моря ≈101.3 кПа).
    ObdPid(command: "0133", shortCode: "BAR",  name: "Атм. давление",             unit: "кПа",    minWarning: 85, maxWarning: 105,
           decode: { b in b.count >= 3 ? Float(b[2]) : 0 }),

    // ── Топливная система ─────────────────────────────────────────────────────

    /// Fuel Level Input: PID 0x2F, 1 байт. Формула: A×100/255 → %.
    /// Нижний порог 10% — предупреждение о низком уровне топлива.
    ObdPid(command: "012F", shortCode: "FLV",  name: "Уровень топлива",            unit: "%",      minWarning: 10, maxWarning: nil,
           decode: { b in b.count >= 3 ? Float(b[2]) * 100.0 / 255.0 : 0 }),

    /// Fuel Rail Pressure (gauge): PID 0x0A, 1 байт. Формула: A×3 → кПа.
    ObdPid(command: "010A", shortCode: "FRP",  name: "Давление топлива",           unit: "кПа",    minWarning: nil, maxWarning: nil,
           decode: { b in b.count >= 3 ? Float(b[2]) * 3.0 : 0 }),

    /// Short Term Fuel Trim Bank 1: PID 0x06, 1 байт. Формула: (A-128)×100/128 → %.
    /// Пороги: ±10% — за пределами ЭБУ активно корректирует смесь (возможна неисправность).
    ObdPid(command: "0106", shortCode: "STF1", name: "Краткоср. коррекция B1",     unit: "%",      minWarning: -10, maxWarning: 10,
           decode: { b in b.count >= 3 ? Float(b[2] - 128) * 100.0 / 128.0 : 0 }),

    /// Long Term Fuel Trim Bank 1: PID 0x07, 1 байт. Формула: (A-128)×100/128 → %.
    ObdPid(command: "0107", shortCode: "LTF1", name: "Долгоср. коррекция B1",      unit: "%",      minWarning: -10, maxWarning: 10,
           decode: { b in b.count >= 3 ? Float(b[2] - 128) * 100.0 / 128.0 : 0 }),

    /// Short Term Fuel Trim Bank 2: PID 0x08 (V-образные, bi-turbo двигатели).
    ObdPid(command: "0108", shortCode: "STF2", name: "Краткоср. коррекция B2",     unit: "%",      minWarning: -10, maxWarning: 10,
           decode: { b in b.count >= 3 ? Float(b[2] - 128) * 100.0 / 128.0 : 0 }),

    /// Long Term Fuel Trim Bank 2: PID 0x09.
    ObdPid(command: "0109", shortCode: "LTF2", name: "Долгоср. коррекция B2",      unit: "%",      minWarning: -10, maxWarning: 10,
           decode: { b in b.count >= 3 ? Float(b[2] - 128) * 100.0 / 128.0 : 0 }),

    // ── Электрика ─────────────────────────────────────────────────────────────

    /// Control Module Voltage: PID 0x42, 2 байта. Формула: (A×256+B)/1000 → В.
    /// Пороги: 11.5–14.8 В (ниже — разряд АКБ, выше — перезаряд генератора).
    ObdPid(command: "0142", shortCode: "VLT",  name: "Напряжение бортсети",        unit: "В",      minWarning: 11.5, maxWarning: 14.8,
           decode: { b in b.count >= 4 ? Float((b[2] * 256) + b[3]) / 1000.0 : 0 }),

    // ── Зажигание / выхлоп ───────────────────────────────────────────────────

    /// Timing Advance: PID 0x0E, 1 байт. Формула: A/2 - 64 → ° (относительно ВМТ).
    /// Пороги: -20…+60° — за пределами возможна детонация или неэффективное сгорание.
    ObdPid(command: "010E", shortCode: "IGN",  name: "Угол опережения зажигания",  unit: "°",      minWarning: -20, maxWarning: 60,
           decode: { b in b.count >= 3 ? Float(b[2]) / 2.0 - 64.0 : 0 }),

    /// Catalyst Temperature Bank 1 Sensor 1: PID 0x3C, 2 байта. Формула: (A×256+B)/10 - 40 → °C.
    /// Верхний порог 900 °C — выше катализатор разрушается.
    ObdPid(command: "013C", shortCode: "CT1",  name: "Температура катализатора B1S1", unit: "°C",  minWarning: nil, maxWarning: 900,
           decode: { b in b.count >= 4 ? Float((b[2] * 256) + b[3]) / 10.0 - 40.0 : 0 }),

    /// Catalyst Temperature Bank 2 Sensor 1: PID 0x3E, 2 байта.
    ObdPid(command: "013E", shortCode: "CT2",  name: "Температура катализатора B2S1", unit: "°C",  minWarning: nil, maxWarning: 900,
           decode: { b in b.count >= 4 ? Float((b[2] * 256) + b[3]) / 10.0 - 40.0 : 0 }),

    // ── O₂ датчики ───────────────────────────────────────────────────────────

    /// O₂ Sensor Bank 1 Sensor 1 (перед катализатором): PID 0x14, 1 байт. Формула: A/200 → В.
    /// Пороги: 0.1–0.9 В — нормальный диапазон переключений лямбда-зонда.
    ObdPid(command: "0114", shortCode: "O2S1", name: "Датчик O₂ B1S1",            unit: "В",      minWarning: 0.1, maxWarning: 0.9,
           decode: { b in b.count >= 3 ? Float(b[2]) / 200.0 : 0 }),

    /// O₂ Sensor Bank 1 Sensor 2 (после катализатора): PID 0x15.
    ObdPid(command: "0115", shortCode: "O2S2", name: "Датчик O₂ B1S2",            unit: "В",      minWarning: 0.1, maxWarning: 0.9,
           decode: { b in b.count >= 3 ? Float(b[2]) / 200.0 : 0 }),

    // ── EGR / дополнительные ─────────────────────────────────────────────────

    /// Commanded EGR: PID 0x2C, 1 байт. Формула: A×100/255 → %.
    ObdPid(command: "012C", shortCode: "EGR",  name: "Клапан EGR (команда)",       unit: "%",      minWarning: nil, maxWarning: 100,
           decode: { b in b.count >= 3 ? Float(b[2]) * 100.0 / 255.0 : 0 }),

    /// Absolute Load Value: PID 0x43, 2 байта. Формула: (A×256+B)×100/65535 → %.
    ObdPid(command: "0143", shortCode: "ALD",  name: "Абсолютная нагрузка",        unit: "%",      minWarning: nil, maxWarning: 100,
           decode: { b in b.count >= 4 ? Float((b[2] * 256) + b[3]) * 100.0 / 65535.0 : 0 }),

    /// Commanded Equivalence Ratio (λ): PID 0x44, 2 байта. Формула: (A×256+B)×2/65536.
    /// λ=1.0 — стехиометрическая смесь; <1 — обогащённая; >1 — обеднённая.
    ObdPid(command: "0144", shortCode: "AFR",  name: "Команд. соотношение A/F (λ)", unit: "",      minWarning: nil, maxWarning: nil,
           decode: { b in b.count >= 4 ? Float((b[2] * 256) + b[3]) * 2.0 / 65536.0 : 0 }),

    /// Time Run with MIL on: PID 0x4D, 2 байта. Формула: A×256+B → минуты.
    /// Показывает, сколько минут двигатель работал с горящим Check Engine.
    ObdPid(command: "014D", shortCode: "MLT",  name: "Время с Check Engine",       unit: "мин",    minWarning: nil, maxWarning: nil,
           decode: { b in b.count >= 4 ? Float((b[2] * 256) + b[3]) : 0 }),

    /// Engine Fuel Rate: PID 0x5E, 2 байта. Формула: (A×256+B)/20 → л/ч.
    ObdPid(command: "015E", shortCode: "FRT",  name: "Расход топлива",              unit: "л/ч",    minWarning: nil, maxWarning: nil,
           decode: { b in b.count >= 4 ? Float((b[2] * 256) + b[3]) / 20.0 : 0 }),
]
