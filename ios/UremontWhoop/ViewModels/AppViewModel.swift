/// Вся бизнес-логика OBD-экрана: подключение, диагностика, мониторинг, история.
/// OBDScreen (View) делегирует всё сюда, оставляя себе только UI-состояние.
///
/// Архитектурная роль — **ViewModel** в паттерне MVVM:
/// - **View** → `OBDScreen` (SwiftUI) — отображает `@Published`-свойства и вызывает методы ViewModel.
/// - **ViewModel** → `AppViewModel` (этот файл) — хранит UI-состояние, оркестрирует бизнес-логику.
/// - **Service** → `ObdConnectionManager` — низкоуровневое общение с ELM327 (TCP/WiFi).
///
/// `@MainActor` гарантирует, что все изменения `@Published`-свойств происходят
/// на главном потоке, поэтому SwiftUI может безопасно подписываться без `DispatchQueue.main`.
import SwiftUI
import Combine

/// Центральная ViewModel OBD-диагностики.
///
/// Управляет жизненным циклом подключения, чтением ошибок (DTC),
/// мониторингом датчиков в реальном времени, сохранением истории сессий
/// и экспортом PDF-отчётов. Все асинхронные операции выполняются через
/// `ObdConnectionManager`, а результаты публикуются в `@Published`-свойства
/// для реактивного обновления UI.
@MainActor
final class AppViewModel: ObservableObject {

    /// Сервис-уровень для общения с ELM327-адаптером.
    /// Инжектится при создании ViewModel — позволяет подменять в тестах.
    let obdManager: ObdConnectionManager

    // MARK: - Published State

    /// Текстовое описание текущего статуса подключения, отображаемое в UI.
    /// Меняется при каждом этапе: «Нет соединения» → «Подключение к …» → «Подключено: …» / ошибка.
    @Published var connectionStatus = "Нет соединения"

    /// `true`, когда TCP-соединение с адаптером установлено и ELM327 прошёл инициализацию.
    /// Используется для переключения UI между состояниями «подключено» / «отключено».
    @Published var isConnected = false

    /// `true` во время асинхронного подключения (после нажатия «Подключить», до результата).
    /// Позволяет отображать индикатор загрузки и блокировать повторные нажатия.
    @Published var isConnecting = false

    /// Профиль автомобиля: `.auto` (определение по VIN) или `.manual(make, model, year)`.
    /// Влияет на выбор OEM-базы DTC (BMW / VAG / Mercedes) и текст в PDF-отчёте.
    @Published var carProfile: CarProfile = .auto

    /// Информация об автомобиле, полученная от ЭБУ (VIN, марка, год, пробег и т.д.).
    /// Заполняется после успешного подключения через `obdManager.readVehicleInfo()`.
    /// `nil` до подключения или при ошибке чтения.
    @Published var vehicleInfo: VehicleInfo?

    /// Результат чтения мониторов готовности (Mode 01, PID 0101).
    /// Массив пуст до первого подключения; заполняется вместе с `vehicleInfo`.
    @Published var readinessMonitors: [ReadinessMonitor] = []

    /// Пользовательские настройки (Freeze Frame вкл/выкл, опрос дополнительных ЭБУ и т.д.).
    /// Загружаются из UserDefaults при старте; сохраняются автоматически при изменении.
    @Published var settings = AppSettings.load()

    /// Сохранённый IP-адрес WiFi-адаптера (по умолчанию 192.168.0.10 — стандарт ELM327 WiFi).
    @Published var savedWifiHost = BrandConfig.defaultWifiHost

    /// Сохранённый порт WiFi-адаптера (по умолчанию 35000 — стандарт ELM327 WiFi).
    @Published var savedWifiPort = String(BrandConfig.defaultWifiPort)

    /// Текущее состояние экрана диагностики ошибок: `.idle` / `.loading` / `.result(…)`.
    /// Определяет, какой контент показывать: пустой экран, прогресс или список DTC.
    @Published var errorsState: ErrorsState = .idle

    /// Текст текущего этапа чтения ошибок, отображаемый под индикатором загрузки.
    /// Обновляется пошагово: Mode 03 → Mode 07 → Freeze Frame → другие ЭБУ.
    @Published var errorsLoadingMessage = "Опрашиваю ЭБУ…"

    /// Словарь текущих показаний датчиков: ключ = OBD-команда PID, значение = `SensorReading`.
    /// Обновляется циклически в `pollSensors()` пока `isMonitoring == true`.
    @Published var sensorReadings: [String: SensorReading] = [:]

    /// `true`, когда активен непрерывный опрос датчиков в реальном времени.
    /// Переключается кнопкой «Старт / Стоп мониторинг»; при `false` цикл `pollSensors()` завершается.
    @Published var isMonitoring = false

    /// Список сохранённых сессий диагностики, отображаемый на вкладке «История».
    /// Загружается из JSON-файла при старте и обновляется после каждого сканирования.
    @Published var sessions: [SessionRecord] = []

    /// URL сгенерированного PDF-отчёта. Устанавливается после вызова `exportPdf()`.
    /// Передаётся в `ShareLink` / `UIActivityViewController` для отправки.
    @Published var pdfFileURL: URL?

    // MARK: - Computed

    /// Человекочитаемое имя автомобиля для заголовков и отчётов.
    ///
    /// Приоритет: данные из ЭБУ (марка + год из VIN) → ручной профиль → «Автомобиль».
    var vehicleDisplayName: String {
        if let info = vehicleInfo {
            let parts = [info.detectedMake, info.detectedYear].compactMap { $0 }
            let joined = parts.joined(separator: " ")
            return joined.isEmpty ? (info.vin ?? "Автомобиль") : joined
        }
        if case .manual = carProfile { return carProfile.displayName }
        return "Автомобиль"
    }

    /// Токен для `.task(id:)` в SwiftUI — при изменении `isMonitoring` или `isConnected`
    /// SwiftUI автоматически отменяет старый Task и запускает новый.
    /// Это заменяет ручное управление `Task.cancel()` и гарантирует корректный lifecycle.
    var pollingToken: String { "\(isMonitoring)-\(isConnected)" }

    // MARK: - Init

    /// Создаёт ViewModel с переданным менеджером подключения.
    ///
    /// - Parameter obdManager: Сервис для общения с ELM327-адаптером.
    init(obdManager: ObdConnectionManager) {
        self.obdManager = obdManager
    }

    // MARK: - Lifecycle

    /// Начальная загрузка состояния при появлении экрана.
    ///
    /// Загружает историю сессий и, если адаптер уже подключён (hot-start),
    /// синхронизирует UI-состояние и запрашивает VIN + мониторы готовности.
    func loadInitialState() async {
        sessions = SessionRepository.shared.loadAll()
        if obdManager.isConnected {
            isConnected = true
            isConnecting = false
            connectionStatus = obdManager.connectedDeviceLabel.map { "Подключено: \($0)" } ?? "Подключено"
            vehicleInfo = await obdManager.readVehicleInfo()
            readinessMonitors = await obdManager.readReadiness()
        }
    }

    /// Вызывается при потере соединения (обрыв TCP, таймаут).
    /// Сбрасывает флаги мониторинга и диагностики в исходное состояние.
    func onDisconnect() {
        isMonitoring = false
        errorsState = .idle
    }

    // MARK: - Connection

    /// Переключает подключение: если подключено — отключает.
    ///
    /// Подключение инициируется отдельными методами (`connectWifi`),
    /// поэтому здесь обрабатывается только disconnect-логика.
    func toggleConnection() {
        if isConnected {
            obdManager.disconnect()
            isConnected = false
            isConnecting = false
            connectionStatus = "Нет соединения"
        }
    }

    /// Устанавливает WiFi-соединение с ELM327-адаптером.
    ///
    /// Последовательность: TCP-подключение → инициализация ELM327 (ATZ, ATE0, ATSP0) →
    /// чтение VIN и мониторов готовности.
    ///
    /// - Parameters:
    ///   - host: IP-адрес адаптера (обычно 192.168.0.10).
    ///   - port: TCP-порт в виде строки (обычно "35000"). Парсится в Int, fallback = 35000.
    func connectWifi(host: String, port: String) async {
        let portNum = Int(port) ?? BrandConfig.defaultWifiPort
        connectionStatus = "Подключение к \(host):\(portNum)…"
        isConnecting = true
        isConnected = false

        let result = await obdManager.connectWifi(host: host, port: portNum)
        isConnecting = false

        switch result {
        case .success:
            connectionStatus = "Подключено: \(host):\(portNum)"
            isConnected = true
            vehicleInfo = nil
            readinessMonitors = []
            try? await Task.sleep(nanoseconds: UInt64(BrandConfig.postConnectDelaySeconds * 1_000_000_000))
            vehicleInfo = await obdManager.readVehicleInfo()
            readinessMonitors = await obdManager.readReadiness()
        case .failure(let error):
            connectionStatus = error.localizedDescription
        }
    }

    // MARK: - Diagnostics

    /// Полный цикл чтения ошибок из ЭБУ.
    ///
    /// Выполняется последовательно:
    /// 1. **Mode 03** — постоянные (confirmed) DTC из основного ЭБУ двигателя.
    /// 2. **Mode 07** — ожидающие (pending) DTC, которые ещё не подтверждены.
    /// 3. **Mode 0A** — постоянные эмиссионные (PDTC).
    /// 4. **Mode 02** (опционально) — Freeze Frame, если включён в настройках и есть постоянные ошибки.
    /// 5. **Доп. ЭБУ** (опционально, `otherEcusEnabled`): для каждого адреса `ATSH` + Mode 03/07/0A;
    ///    если Mode 03 на CAN не поддерживается — fallback **UDS** `10 03` + `19 02 FF` (`readOtherEcuDtcs`).
    ///
    /// После завершения автоматически сохраняет сессию в JSON (`saveSession`).
    func readErrors() async {
        errorsState = .loading
        errorsLoadingMessage = "Читаю постоянные ошибки (Mode 03)…"
        let mainResult = await obdManager.readDtcs()

        errorsLoadingMessage = "Читаю ожидающие ошибки (Mode 07)…"
        let pendingResult = await obdManager.readPendingDtcs()

        errorsLoadingMessage = "Читаю постоянные эмиссионные (Mode 0A)…"
        let permanentResult = await obdManager.readPermanentDtcs()

        var ff: FreezeFrameData?
        if settings.freezeFrameEnabled,
           case .dtcList(let codes) = mainResult, !codes.isEmpty {
            errorsLoadingMessage = "Читаю снимок параметров (Freeze Frame)…"
            ff = await obdManager.readFreezeFrame()
        }

        var ecuResults: [EcuDtcResult] = []
        if settings.otherEcusEnabled {
            errorsLoadingMessage = "Опрашиваю доп. ЭБУ (CAN, по марке — расширенный список)…"
            let makeHint: String? = {
                if case let .manual(make, _, _) = carProfile { return make }
                return nil
            }()
            ecuResults = await obdManager.readOtherEcuDtcs(vehicleInfo: vehicleInfo, manualMakeHint: makeHint)
            errorsLoadingMessage = "Завершение…"
        }

        errorsState = .result(
            main: mainResult,
            pending: pendingResult,
            permanent: permanentResult,
            freezeFrame: ff,
            ecuResults: ecuResults
        )

        saveSession(main: mainResult, pending: pendingResult, permanent: permanentResult, ff: ff, ecuResults: ecuResults)
    }

    /// Сброс ошибок в ЭБУ (Mode 04 — Clear Diagnostic Trouble Codes).
    ///
    /// После успешной отправки команды возвращает экран в исходное состояние `.idle`.
    /// **Внимание:** сброс очищает Freeze Frame и сбрасывает мониторы готовности.
    func clearErrors() async {
        errorsState = .loading
        errorsLoadingMessage = "Сбрасываю ошибки (Mode 04)…"
        _ = await obdManager.clearDtcs()
        errorsState = .idle
    }

    // MARK: - Monitoring

    /// Непрерывный опрос всех датчиков из `UNIVERSAL_PIDS` в цикле.
    ///
    /// Запускается через `.task(id: pollingToken)` в SwiftUI — при изменении `pollingToken`
    /// предыдущий Task автоматически отменяется и запускается новый.
    ///
    /// Цикл завершается при: отмене Task (`Task.isCancelled`), выключении мониторинга
    /// (`isMonitoring == false`) или потере соединения. Минимальный интервал между
    /// полными циклами опроса — 300 мс (для предотвращения перегрузки адаптера).
    func pollSensors() async {
        guard isMonitoring, obdManager.isConnected else { return }
        while !Task.isCancelled && isMonitoring && obdManager.isConnected {
            let start = CFAbsoluteTimeGetCurrent()
            for pid in UNIVERSAL_PIDS {
                guard isMonitoring else { break }
                let reading = await obdManager.pollSensor(pid: pid)
                sensorReadings[pid.command] = reading
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            if elapsed < BrandConfig.livePollMinIntervalSeconds {
                let gap = BrandConfig.livePollMinIntervalSeconds - elapsed
                try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
            }
        }
    }

    // MARK: - PDF Export

    /// Генерирует PDF-отчёт на основе текущих результатов диагностики.
    ///
    /// Собирает `DiagnosticReportData` из: информации об автомобиле, мониторов готовности,
    /// постоянных и ожидающих DTC (с расшифровкой через `DtcLookup`), Freeze Frame
    /// и результатов дополнительных ЭБУ. Передаёт данные в `PdfReportGenerator`.
    ///
    /// - Returns: URL временного PDF-файла или `nil`, если нет результатов диагностики.
    func exportPdf() -> URL? {
        guard case .result(let main, let pending, let permanent, let freezeFrame, let ecuResults) = errorsState else { return nil }

        /// Конвертирует `DtcResult` в массив `DtcEntry` для PDF-отчёта,
        /// обогащая каждый код расшифровкой из `DtcLookup`.
        func toDtcEntries(_ result: DtcResult) -> [DtcEntry] {
            guard case .dtcList(let codes) = result else { return [] }
            return codes.map { code in
                let info = DtcLookup.dtcInfo(code: code, profile: carProfile, detectedMake: vehicleInfo?.detectedMake)
                return DtcEntry(code: code, title: info.title, causes: info.causes,
                                repair: info.repair, severity: info.severity)
            }
        }

        let mainDtcEntries = toDtcEntries(main)

        var ecuBlocks: [EcuStatusEntry] = [
            EcuStatusEntry(name: "Двигатель / ЭБУ", address: "7E0",
                           responded: true, dtcs: mainDtcEntries,
                           pendingDtcs: toDtcEntries(pending),
                           permanentDtcs: toDtcEntries(permanent))
        ]
        ecuBlocks += ecuResults.map { ecu in
            let dtcs = toDtcEntries(ecu.result)
            let responded: Bool
            if case .error = ecu.result { responded = false } else { responded = true }
            return EcuStatusEntry(name: ecu.name, address: ecu.address,
                                  responded: responded, dtcs: dtcs,
                                  pendingDtcs: toDtcEntries(ecu.pendingResult),
                                  permanentDtcs: toDtcEntries(ecu.permanentResult))
        }

        let data = DiagnosticReportData(
            generatedAt: Date().timeIntervalSince1970,
            vehicleDisplayName: vehicleDisplayName,
            vin: vehicleInfo?.vin,
            detectedMake: vehicleInfo?.detectedMake,
            detectedYear: vehicleInfo?.detectedYear,
            ecuName: vehicleInfo?.ecuName,
            calibrationId: vehicleInfo?.calibrationId,
            cvnHex: vehicleInfo?.cvnHex,
            mode09SupportMaskHex: vehicleInfo?.mode09SupportMaskHex,
            mode09ExtrasSummary: vehicleInfo?.mode09ExtrasSummary,
            obdStandardLabel: vehicleInfo?.obdStandardLabel,
            fuelTypeLabel: vehicleInfo?.fuelTypeLabel,
            transmissionEcuName: vehicleInfo?.transmissionEcuName,
            clusterOdometerKm: vehicleInfo?.clusterOdometerKm.map { "\($0)" },
            clusterOdometerNote: vehicleInfo?.clusterOdometerNote,
            vinVehicleDescriptor: vehicleInfo?.vinVehicleDescriptor,
            diagnosticBrandGroup: vehicleInfo?.diagnosticBrandGroup,
            distanceMilKm: vehicleInfo?.distanceMilKm().map { "\($0)" },
            distanceClearedKm: vehicleInfo?.distanceClearedKm().map { "\($0)" },
            fuelSystemStatus: vehicleInfo?.fuelSystemStatus,
            warmUpsCleared: vehicleInfo?.warmUpsCleared,
            timeSinceClearedMin: vehicleInfo?.timeSinceClearedMin,
            readinessMonitors: readinessMonitors,
            mainDtcs: mainDtcEntries,
            pendingDtcs: toDtcEntries(pending),
            permanentDtcs: toDtcEntries(permanent),
            freezeFrame: freezeFrame,
            allBlocks: ecuBlocks
        )

        return PdfReportGenerator.shared.generate(data: data)
    }

    // MARK: - Private

    /// Сохраняет результаты текущей диагностики в JSON-файл через `SessionRepository`.
    ///
    /// Вызывается автоматически в конце `readErrors()`. Извлекает коды ошибок из
    /// `DtcResult`, формирует `SessionRecord` и обновляет список `sessions` для UI.
    ///
    /// - Parameters:
    ///   - main: Результат Mode 03 (постоянные DTC).
    ///   - pending: Результат Mode 07 (ожидающие DTC).
    ///   - permanent: Результат Mode 0A (PDTC, часто пусто на EU).
    ///   - ff: Данные Freeze Frame (может быть `nil`).
    ///   - ecuResults: Результаты опроса дополнительных ЭБУ (ABS, SRS, TCM, BCM).
    private func saveSession(main: DtcResult, pending: DtcResult, permanent: DtcResult, ff: FreezeFrameData?, ecuResults: [EcuDtcResult]) {
        let mainCodes: [String]
        if case .dtcList(let codes) = main { mainCodes = codes } else { mainCodes = [] }

        let pendingCodes: [String]
        if case .dtcList(let codes) = pending { pendingCodes = codes } else { pendingCodes = [] }

        let permanentCodes: [String]
        if case .dtcList(let codes) = permanent { permanentCodes = codes } else { permanentCodes = [] }

        var ecuErrors: [String: [String]] = [:]
        for ecu in ecuResults {
            var allCodes: [String] = []
            if case .dtcList(let codes) = ecu.result { allCodes += codes }
            if case .dtcList(let codes) = ecu.pendingResult { allCodes += codes }
            if case .dtcList(let codes) = ecu.permanentResult { allCodes += codes }
            if !allCodes.isEmpty { ecuErrors[ecu.name] = allCodes }
        }

        let record = SessionRecord(
            vehicleName: vehicleDisplayName,
            vin: vehicleInfo?.vin,
            mainDtcs: mainCodes,
            pendingDtcs: pendingCodes,
            permanentDtcs: permanentCodes,
            hasFreezeFrame: ff != nil && !(ff?.isEmpty ?? true),
            otherEcuErrors: ecuErrors
        )
        SessionRepository.shared.save(record: record)
        sessions = SessionRepository.shared.loadAll()
    }
}
