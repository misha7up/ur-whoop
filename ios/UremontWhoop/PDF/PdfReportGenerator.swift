/// Генерация PDF A4 отчёта: шапка, VehicleInfo, Readiness, DTC, Freeze Frame, блоки ECU.
///
/// Файл содержит:
/// - Структуры данных для формирования отчёта (`DiagnosticReportData`, `DtcEntry`, `EcuStatusEntry`)
/// - Синглтон `PdfReportGenerator.shared` для генерации и шаринга PDF
/// - Вспомогательный класс `PageState` для управления страницами
///
/// ## Принцип работы
/// Используется `UIGraphicsPDFRenderer` для рендеринга страниц формата A4 (595×842 pt @ 72 DPI).
/// Каждая секция рисуется последовательно сверху вниз; при нехватке места автоматически
/// создаётся новая страница через `PageState.ensureSpace(_:)`.
///
/// ## Структура PDF
/// 1. Тёмная шапка с логотипом, названием авто и датой
/// 2. Секция «Информация об автомобиле» (VIN, марка, пробег и т.д.)
/// 3. Мониторы готовности (двухколоночная сетка, зелёный/оранжевый)
/// 4. Постоянные и ожидающие DTC-коды (карточки с цветной полосой severity)
/// 5. Freeze Frame — снимок параметров в момент ошибки (двухколоночная сетка)
/// 6. Блоки управления (ECU) с вложенными DTC
/// 7. Нижний колонтитул на каждой странице
///
/// ## Хранение
/// Готовый файл сохраняется в `tmp/reports/uremont_report_<timestamp>.pdf`.
/// Для шаринга используется `UIActivityViewController`.
import UIKit

// MARK: - PDF Data Structures

/// Входные данные для генерации PDF-отчёта диагностики.
///
/// Собирается из результатов OBD2-сканирования и передаётся
/// в `PdfReportGenerator.generate(data:)`.
struct DiagnosticReportData {
    /// Unix-время генерации отчёта (секунды с 1970-01-01)
    let generatedAt: TimeInterval
    /// Отображаемое название автомобиля (марка + модель)
    let vehicleDisplayName: String
    /// VIN-номер (может отсутствовать, если ЭБУ не ответил)
    let vin: String?
    /// Марка авто, определённая по VIN или протоколу
    let detectedMake: String?
    /// Год выпуска, определённый по VIN
    let detectedYear: String?
    /// Наименование ЭБУ (ECU), полученное по протоколу
    let ecuName: String?
    let calibrationId: String?
    let cvnHex: String?
    let mode09SupportMaskHex: String?
    let mode09ExtrasSummary: String?
    let obdStandardLabel: String?
    let fuelTypeLabel: String?
    let transmissionEcuName: String?
    /// Одометр щитка (UDS, опытно), км
    let clusterOdometerKm: String?
    let clusterOdometerNote: String?
    let vinVehicleDescriptor: String?
    let diagnosticBrandGroup: String?
    /// Пробег с момента появления Check Engine (км), PID 0x21
    let distanceMilKm: String?
    /// Пробег после последнего сброса кодов (км), PID 0x31
    let distanceClearedKm: String?
    let fuelSystemStatus: String?
    let warmUpsCleared: Int?
    let timeSinceClearedMin: Int?
    /// Список мониторов готовности (Readiness Monitors) из Mode 01 PID 01
    let readinessMonitors: [ReadinessMonitor]
    /// Постоянные (confirmed) коды неисправностей из Mode 03
    let mainDtcs: [DtcEntry]
    /// Ожидающие (pending) коды неисправностей из Mode 07
    let pendingDtcs: [DtcEntry]
    /// Постоянные эмиссионные PDTC (Mode 0A); на EU часто пусто
    let permanentDtcs: [DtcEntry]
    /// Снимок параметров двигателя в момент возникновения ошибки (Mode 02)
    let freezeFrame: FreezeFrameData?
    /// Все блоки управления (ECU), опрошенные при сканировании
    let allBlocks: [EcuStatusEntry]
}

/// Запись об одном диагностическом коде неисправности (DTC).
///
/// Используется для отображения карточек DTC в PDF-отчёте.
/// Severity определяет цвет полосы: 3 — красный, 2 — оранжевый, остальное — жёлтый.
struct DtcEntry {
    /// OBD2-код (например, «P0301»)
    let code: String
    /// Человекочитаемое название неисправности
    let title: String
    /// Описание возможных причин
    let causes: String
    /// Рекомендации по ремонту
    let repair: String
    /// Уровень серьёзности: 3 — критичная, 2 — средняя, 1 — низкая
    let severity: Int
}

/// Статус одного блока управления (ECU), опрошенного при сканировании.
///
/// Каждый ECU характеризуется адресом в CAN-шине и может содержать
/// собственные коды неисправностей.
struct EcuStatusEntry {
    let name: String
    let address: String
    let responded: Bool
    /// Confirmed DTC (Mode 03)
    let dtcs: [DtcEntry]
    /// Pending DTC (Mode 07)
    var pendingDtcs: [DtcEntry] = []
    /// Permanent DTC (Mode 0A)
    var permanentDtcs: [DtcEntry] = []
}

// MARK: - PdfReportGenerator

/// Генератор PDF-отчётов по результатам OBD2-диагностики.
///
/// ## Использование
/// ```swift
/// let url = PdfReportGenerator.shared.generate(data: reportData)
/// PdfReportGenerator.shared.share(from: viewController, file: url)
/// ```
///
/// ## Паттерн
/// Синглтон (`shared`). Приватный инициализатор предотвращает
/// создание дополнительных экземпляров.
///
/// ## Формат
/// PDF формата A4 (595×842 pt), рендерится через `UIGraphicsPDFRenderer`.
/// Отступы слева/справа — 36 pt. Каждая секция рисуется вручную
/// через Core Graphics (без Auto Layout / UIKit views).
final class PdfReportGenerator {

    /// Единственный экземпляр генератора (синглтон)
    static let shared = PdfReportGenerator()
    private init() {}

    // MARK: Page dimensions & margins (A4 @ 72 DPI: 210mm × 297mm → 595pt × 842pt)

    /// Ширина страницы A4 в пунктах (595 pt)
    private let PW: CGFloat = 595
    /// Высота страницы A4 в пунктах (842 pt)
    private let PH: CGFloat = 842
    /// Левый отступ (margin left), 36 pt
    private let ML: CGFloat = 36
    /// Правый отступ (margin right), 36 pt
    private let MR: CGFloat = 36
    /// Ширина контентной области (страница минус оба отступа)
    private var CW: CGFloat { PW - ML - MR }

    /// Форматтер даты для шапки отчёта (русская локаль, формат «d MMM yyyy, HH:mm»)
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.dateFormat = "d MMM yyyy, HH:mm"
        return fmt
    }()

    // MARK: Colors

    /// Фон тёмной шапки (#0D0D14)
    private let C_HEADER_BG = UIColor(red: 13/255, green: 13/255, blue: 20/255, alpha: 1)
    /// Основной акцентный цвет (синий, #227DF5)
    private let C_ACCENT    = UIColor(red: 34/255, green: 125/255, blue: 245/255, alpha: 1)
    /// Основной цвет текста (#14141A)
    private let C_TEXT      = UIColor(red: 20/255, green: 20/255, blue: 26/255, alpha: 1)
    /// Вторичный цвет текста (серый, #6E6E78)
    private let C_SUBTEXT   = UIColor(red: 110/255, green: 110/255, blue: 120/255, alpha: 1)
    /// Цвет разделительных линий (#DADAE2)
    private let C_DIVIDER   = UIColor(red: 218/255, green: 218/255, blue: 226/255, alpha: 1)
    /// Фон карточек (#F5F5FC)
    private let C_CARD      = UIColor(red: 245/255, green: 245/255, blue: 252/255, alpha: 1)
    /// Зелёный — «ОК» / «Готов» (#34C759)
    private let C_GREEN     = UIColor(red: 52/255, green: 199/255, blue: 89/255, alpha: 1)
    /// Оранжевый — предупреждение (#FF9500)
    private let C_ORANGE    = UIColor(red: 255/255, green: 149/255, blue: 0/255, alpha: 1)
    /// Красный — критическая ошибка (#FF3B30)
    private let C_RED       = UIColor(red: 255/255, green: 59/255, blue: 48/255, alpha: 1)
    /// Жёлтый — низкая серьёзность (#FCC900)
    private let C_YELLOW    = UIColor(red: 252/255, green: 201/255, blue: 0/255, alpha: 1)
    /// Фон бейджа «ожидающий» (#FFF6E4)
    private let C_PENDING   = UIColor(red: 255/255, green: 246/255, blue: 228/255, alpha: 1)

    // MARK: - Public API

    /// Генерирует PDF-отчёт и сохраняет его во временный файл.
    ///
    /// - Parameter data: Данные диагностики для формирования отчёта
    /// - Returns: URL сохранённого PDF-файла в `tmp/reports/`
    ///
    /// Последовательность отрисовки:
    /// 1. Тёмная шапка с логотипом и названием авто
    /// 2. Информация об автомобиле (VIN, марка, пробег)
    /// 3. Мониторы готовности (если есть)
    /// 4. Постоянные и ожидающие DTC
    /// 5. Freeze Frame (если есть)
    /// 6. Блоки управления ECU (если есть)
    func generate(data: DiagnosticReportData) -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: PW, height: PH))
        let state = PageState(pageWidth: PW, pageHeight: PH)

        let pdfData = renderer.pdfData { context in
            state.context = context
            state.newPage()

            drawHeader(state: state, data: data)
            drawVehicleInfoSection(state: state, data: data)
            if !data.readinessMonitors.isEmpty {
                drawReadinessSection(state: state, data: data)
            }
            drawDtcSection(state: state, data: data)
            if let ff = data.freezeFrame, !ff.isEmpty {
                drawFreezeSection(state: state, ff: ff)
            }
            if !data.allBlocks.isEmpty {
                drawBlocksSummarySection(state: state, blocks: data.allBlocks)
            }

            state.finish()
        }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ts = Int(data.generatedAt)
        let fileURL = dir.appendingPathComponent("uremont_report_\(ts).pdf")
        try? pdfData.write(to: fileURL)
        return fileURL
    }

    /// Открывает системный диалог «Поделиться» для отправки PDF-файла.
    ///
    /// - Parameters:
    ///   - viewController: Контроллер, с которого показывается `UIActivityViewController`
    ///   - file: URL PDF-файла для отправки
    ///
    /// На iPad popover привязывается к центру экрана.
    func share(from viewController: UIViewController, file: URL) {
        let ac = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        ac.setValue("UREMONT WHOOP — Отчёт диагностики", forKey: "subject")
        if let popover = ac.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX,
                                        y: viewController.view.bounds.midY, width: 0, height: 0)
        }
        viewController.present(ac, animated: true)
    }

    // MARK: - Section Renderers

    /// Рисует тёмную шапку отчёта (высота 106 pt).
    ///
    /// Структура:
    /// - Тёмный фон (`C_HEADER_BG`) на всю ширину страницы
    /// - Синяя акцентная полоса (5 pt) под шапкой
    /// - Логотип: синий скруглённый прямоугольник + изображение «UremontLogo» из Asset Catalog
    /// - Заголовок «UREMONT WHOOP» и подзаголовок «OBD2 Диагностика автомобиля»
    /// - Название авто и дата (выровнены по правому краю)
    ///
    /// После отрисовки устанавливает `state.y = 124` (начало контентной области).
    private func drawHeader(state: PageState, data: DiagnosticReportData) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Dark background
        ctx.setFillColor(C_HEADER_BG.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: PW, height: 106))

        // Blue accent bar
        ctx.setFillColor(C_ACCENT.cgColor)
        ctx.fill(CGRect(x: 0, y: 104, width: PW, height: 5))

        // Logo: blue rounded rect + SVG logo pre-rendered to bitmap
        // (SVG из Asset Catalog не рендерится напрямую в UIGraphicsPDFRenderer)
        let logoRect = CGRect(x: ML, y: 20, width: 50, height: 50)
        let logoPath = UIBezierPath(roundedRect: logoRect, cornerRadius: 12)
        ctx.setFillColor(C_ACCENT.cgColor)
        ctx.addPath(logoPath.cgPath)
        ctx.fillPath()

        if let logoImage = UIImage(named: "UremontLogo") {
            let inset = logoRect.insetBy(dx: 10, dy: 8)
            let bitmapRenderer = UIGraphicsImageRenderer(size: inset.size)
            let rendered = bitmapRenderer.image { _ in
                logoImage.withTintColor(.white, renderingMode: .alwaysOriginal)
                    .draw(in: CGRect(origin: .zero, size: inset.size))
            }
            rendered.draw(in: inset)
        }

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20),
            .foregroundColor: UIColor.white
        ]
        ("UREMONT WHOOP" as NSString).draw(at: CGPoint(x: ML + 62, y: 28), withAttributes: titleAttrs)

        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor(red: 160/255, green: 172/255, blue: 195/255, alpha: 1)
        ]
        ("OBD2 Диагностика автомобиля" as NSString).draw(at: CGPoint(x: ML + 62, y: 52), withAttributes: subtitleAttrs)

        let dateStr = Self.dateFormatter.string(from: Date(timeIntervalSince1970: data.generatedAt))

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor(red: 200/255, green: 212/255, blue: 235/255, alpha: 1)
        ]
        let nameStr = data.vehicleDisplayName as NSString
        let nameSize = nameStr.size(withAttributes: nameAttrs)
        nameStr.draw(at: CGPoint(x: PW - MR - nameSize.width, y: 34), withAttributes: nameAttrs)

        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor(red: 140/255, green: 152/255, blue: 175/255, alpha: 1)
        ]
        let dateNS = dateStr as NSString
        let dateSize = dateNS.size(withAttributes: dateAttrs)
        dateNS.draw(at: CGPoint(x: PW - MR - dateSize.width, y: 50), withAttributes: dateAttrs)

        state.y = 124
    }

    /// Рисует секцию «Информация об автомобиле».
    ///
    /// Отображает пары «ключ — значение»: марка, год, VIN, название ЭБУ,
    /// пробеги. Если данные не получены от ЭБУ — показывает placeholder.
    private func drawVehicleInfoSection(state: PageState, data: DiagnosticReportData) {
        var rows: [(String, String)] = []
        if let v = data.detectedMake { rows.append(("Марка автомобиля", v)) }
        if let v = data.detectedYear { rows.append(("Год выпуска", v)) }
        if let v = data.vin { rows.append(("VIN", v)) }
        if let v = data.vinVehicleDescriptor { rows.append(("VDS (VIN 4–9)", v)) }
        if let g = data.diagnosticBrandGroup, g != "OTHER" {
            rows.append(("Диагност. группа марки", g))
        }
        if let v = data.ecuName { rows.append(("ЭБУ двигателя", v)) }
        if let v = data.transmissionEcuName { rows.append(("ЭБУ КПП (CAN 7E1)", v)) }
        if let km = data.clusterOdometerKm {
            let note = data.clusterOdometerNote.map { " (\($0))" } ?? ""
            rows.append(("Одометр щитка (UDS, опытно)\(note)", "\(km) км"))
        }
        if let v = data.obdStandardLabel { rows.append(("Тип OBD (PID 1C)", v)) }
        if let v = data.fuelTypeLabel { rows.append(("Топливо (PID 51)", v)) }
        if let v = data.calibrationId { rows.append(("Calibration ID (09/03)", v)) }
        if let v = data.cvnHex { rows.append(("CVN (09/04)", v)) }
        if let v = data.mode09SupportMaskHex { rows.append(("Маска Mode 09 (00)", v)) }
        if let v = data.mode09ExtrasSummary { rows.append(("Mode 09 (доп.)", v)) }
        if let v = data.distanceMilKm { rows.append(("Пробег с Check Engine (PID 0x21)", "\(v) км")) }
        if let v = data.distanceClearedKm { rows.append(("С последнего сброса DTC (0x31, не одометр)", "\(v) км")) }
        if let v = data.fuelSystemStatus { rows.append(("Система топливоподачи (PID 03)", v)) }
        if let v = data.warmUpsCleared { rows.append(("Прогревов после сброса DTC (PID 30)", "\(v)")) }
        if let v = data.timeSinceClearedMin { rows.append(("Минут с момента сброса DTC (PID 4E)", "\(v) мин")) }

        drawSectionHeader(state: state, title: "ИНФОРМАЦИЯ ОБ АВТОМОБИЛЕ")
        if rows.isEmpty {
            drawSmallText(state: state, text: "   Данные об автомобиле не получены от ЭБУ", color: C_SUBTEXT)
        } else {
            for (k, v) in rows { drawKVRow(state: state, key: k, value: v) }
        }
        state.y += 8
    }

    /// Рисует секцию «Готовность систем мониторинга» (Readiness Monitors).
    ///
    /// Мониторы отображаются в двухколоночной сетке. Каждая ячейка имеет
    /// фон (зелёный/оранжевый), цветной индикатор-кружок и статус «ГОТОВ» / «НЕ ГОТОВ».
    /// Высота одной строки — 24 pt.
    private func drawReadinessSection(state: PageState, data: DiagnosticReportData) {
        drawSectionHeader(state: state, title: "ГОТОВНОСТЬ СИСТЕМ МОНИТОРИНГА")
        let monitors = data.readinessMonitors
        var i = 0
        while i < monitors.count {
            state.ensureSpace(24)
            let left = monitors[i]
            let right: ReadinessMonitor? = (i + 1 < monitors.count) ? monitors[i + 1] : nil
            let halfW = CW / 2 - 5
            drawReadinessCell(y: state.y, monitor: left, x: ML, w: halfW)
            if let r = right {
                drawReadinessCell(y: state.y, monitor: r, x: ML + halfW + 10, w: halfW)
            }
            state.y += 24
            i += 2
        }
        state.y += 8
    }

    /// Рисует секции постоянных и ожидающих DTC-кодов.
    ///
    /// Постоянные (confirmed, Mode 03) отображаются всегда.
    /// Если ошибок нет — выводится зелёная строка «Постоянных ошибок не обнаружено».
    /// Ожидающие (pending, Mode 07) отображаются только при наличии.
    private func drawDtcSection(state: PageState, data: DiagnosticReportData) {
        drawSectionHeader(state: state, title: "ПОСТОЯННЫЕ КОДЫ НЕИСПРАВНОСТЕЙ (\(data.mainDtcs.count))")
        if data.mainDtcs.isEmpty {
            drawSmallText(state: state, text: "   ✓   Постоянных ошибок не обнаружено", color: C_GREEN)
        } else {
            for dtc in data.mainDtcs { drawDtcCard(state: state, entry: dtc, isPending: false) }
        }
        state.y += 4

        if !data.pendingDtcs.isEmpty {
            drawSectionHeader(state: state, title: "ОЖИДАЮЩИЕ КОДЫ (\(data.pendingDtcs.count))")
            for dtc in data.pendingDtcs { drawDtcCard(state: state, entry: dtc, isPending: true) }
            state.y += 4
        }

        if !data.permanentDtcs.isEmpty {
            drawSectionHeader(state: state, title: "ПОСТОЯННЫЕ ЭМИССИОННЫЕ (MODE 0A) (\(data.permanentDtcs.count))")
            for dtc in data.permanentDtcs { drawDtcCard(state: state, entry: dtc, isPending: false) }
            state.y += 4
        }
    }

    /// Рисует секцию «Freeze Frame» — снимок параметров двигателя в момент ошибки.
    ///
    /// Параметры (обороты, скорость, температура и т.д.) располагаются
    /// в двухколоночной сетке скруглённых ячеек. Высота ячейки — 28 pt,
    /// шаг по вертикали — 32 pt.
    private func drawFreezeSection(state: PageState, ff: FreezeFrameData) {
        drawSectionHeader(state: state, title: "СНИМОК ПАРАМЕТРОВ В МОМЕНТ ОШИБКИ (FREEZE FRAME)")
        var cells: [(String, String)] = []
        if let v = ff.dtcCode      { cells.append(("DTC, вызвавший снимок", v)) }
        if let v = ff.rpm          { cells.append(("Обороты", "\(v) об/мин")) }
        if let v = ff.speed        { cells.append(("Скорость", "\(v) км/ч")) }
        if let v = ff.coolantTemp  { cells.append(("Охлаждающая жидкость", "\(v) °C")) }
        if let v = ff.iat          { cells.append(("Температура воздуха", "\(v) °C")) }
        if let v = ff.engineLoad   { cells.append(("Нагрузка двигателя", String(format: "%.1f %%", v))) }
        if let v = ff.throttle     { cells.append(("Положение дросселя", String(format: "%.1f %%", v))) }
        if let v = ff.shortFuelTrim { cells.append(("Коррекция топлива (краткоср.)", String(format: "%.1f %%", v))) }
        if let v = ff.longFuelTrim { cells.append(("Коррекция топлива (долгоср.)", String(format: "%.1f %%", v))) }
        if let v = ff.map          { cells.append(("Давление впуска", "\(v) кПа")) }
        if let v = ff.voltage      { cells.append(("Напряжение бортсети", String(format: "%.1f В", v))) }
        if let v = ff.fuelStatus   { cells.append(("Система топливоподачи", v)) }

        let half = CW / 2 - 5
        var i = 0
        while i < cells.count {
            state.ensureSpace(32)
            let left = cells[i]
            let right: (String, String)? = (i + 1 < cells.count) ? cells[i + 1] : nil
            drawFreezeCell(y: state.y, label: left.0, value: left.1, x: ML, w: half)
            if let r = right {
                drawFreezeCell(y: state.y, label: r.0, value: r.1, x: ML + half + 10, w: half)
            }
            state.y += 32
            i += 2
        }
        state.y += 4
    }

    /// Рисует секцию «Блоки управления» — список всех опрошенных ECU.
    ///
    /// Каждый ECU отображается строкой со скруглённым фоном:
    /// - Имя блока (жирный, слева)
    /// - CAN-адрес (серый, перед статусом)
    /// - Статус: «ОШИБОК НЕТ» (зелёный), «N ОШИБОК» (оранжевый), «НЕТ ОТВЕТА» (серый)
    ///
    /// Если у блока есть DTC — они рисуются карточками ниже строки ECU.
    private func drawBlocksSummarySection(state: PageState, blocks: [EcuStatusEntry]) {
        drawSectionHeader(state: state, title: "БЛОКИ УПРАВЛЕНИЯ (\(blocks.count))")
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        for block in blocks {
            state.ensureSpace(24)

            let statusText: String
            let statusColor: UIColor
            let totalErrs = block.dtcs.count + block.pendingDtcs.count + block.permanentDtcs.count
            if !block.responded {
                statusText = "НЕТ ОТВЕТА"; statusColor = C_SUBTEXT
            } else if totalErrs == 0 {
                statusText = "ОШИБОК НЕТ"; statusColor = C_GREEN
            } else {
                statusText = "\(totalErrs) ОШИБОК"; statusColor = C_ORANGE
            }

            // Row background
            let rowBg = UIColor(red: 238/255, green: 238/255, blue: 248/255, alpha: 1)
            let rowRect = CGRect(x: ML, y: state.y, width: CW, height: 20)
            let rowPath = UIBezierPath(roundedRect: rowRect, cornerRadius: 5)
            ctx.setFillColor(rowBg.cgColor)
            ctx.addPath(rowPath.cgPath)
            ctx.fillPath()

            // Block name
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 9),
                .foregroundColor: C_TEXT
            ]
            (block.name.uppercased() as NSString).draw(
                at: CGPoint(x: ML + 8, y: state.y + 4), withAttributes: nameAttrs)

            // Address (gray, right of name)
            let addrAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 7.5),
                .foregroundColor: C_SUBTEXT
            ]
            let addrStr = block.address as NSString
            let addrSize = addrStr.size(withAttributes: addrAttrs)
            addrStr.draw(at: CGPoint(x: ML + CW - 60 - addrSize.width, y: state.y + 5),
                         withAttributes: addrAttrs)

            // Status (colored, right edge)
            let statusAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 8),
                .foregroundColor: statusColor
            ]
            let statusNS = statusText as NSString
            let statusSize = statusNS.size(withAttributes: statusAttrs)
            statusNS.draw(at: CGPoint(x: ML + CW - 6 - statusSize.width, y: state.y + 5),
                          withAttributes: statusAttrs)

            state.y += 24

            for dtc in block.dtcs { drawDtcCard(state: state, entry: dtc, isPending: false) }
            for dtc in block.pendingDtcs { drawDtcCard(state: state, entry: dtc, isPending: true) }
            for dtc in block.permanentDtcs { drawDtcCard(state: state, entry: dtc, isPending: false) }
        }
    }

    // MARK: - Primitive Drawing Helpers

    /// Рисует заголовок секции: синяя вертикальная полоса (4 pt) + текст + горизонтальный разделитель.
    ///
    /// - Parameters:
    ///   - state: Текущее состояние страницы
    ///   - title: Текст заголовка (обычно ВЕРХНИЙ_РЕГИСТР)
    ///
    /// Высота секции — 32 pt. Перед отрисовкой запрашивает минимум 38 pt свободного места.
    private func drawSectionHeader(state: PageState, title: String) {
        state.ensureSpace(38)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Blue vertical bar
        ctx.setFillColor(C_ACCENT.cgColor)
        ctx.fill(CGRect(x: ML, y: state.y, width: 4, height: 22))

        // Title text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 11),
            .foregroundColor: C_TEXT
        ]
        (title as NSString).draw(at: CGPoint(x: ML + 12, y: state.y + 3), withAttributes: attrs)

        // Divider line
        ctx.setStrokeColor(C_DIVIDER.cgColor)
        ctx.setLineWidth(0.8)
        ctx.move(to: CGPoint(x: ML, y: state.y + 24))
        ctx.addLine(to: CGPoint(x: ML + CW, y: state.y + 24))
        ctx.strokePath()

        state.y += 32
    }

    /// Рисует строку «ключ — значение» для секции информации об автомобиле.
    ///
    /// - Parameters:
    ///   - state: Текущее состояние страницы
    ///   - key: Название параметра (серый текст, слева)
    ///   - value: Значение параметра (жирный текст, выровнен вправо)
    ///
    /// Высота строки — 21 pt, с тонким разделителем внизу.
    private func drawKVRow(state: PageState, key: String, value: String) {
        state.ensureSpace(22)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: C_SUBTEXT
        ]
        (key as NSString).draw(at: CGPoint(x: ML + 8, y: state.y + 3), withAttributes: keyAttrs)

        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: C_TEXT
        ]
        let valNS = value as NSString
        let valSize = valNS.size(withAttributes: valAttrs)
        valNS.draw(at: CGPoint(x: ML + CW - 6 - valSize.width, y: state.y + 2), withAttributes: valAttrs)

        // Divider
        ctx.setStrokeColor(C_DIVIDER.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: ML + 4, y: state.y + 19))
        ctx.addLine(to: CGPoint(x: ML + CW - 4, y: state.y + 19))
        ctx.strokePath()

        state.y += 21
    }

    /// Рисует строку мелкого текста (placeholder / статус).
    ///
    /// - Parameters:
    ///   - state: Текущее состояние страницы
    ///   - text: Текст для отображения
    ///   - color: Цвет текста
    private func drawSmallText(state: PageState, text: String, color: UIColor) {
        state.ensureSpace(18)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: color
        ]
        (text as NSString).draw(at: CGPoint(x: ML + 8, y: state.y + 1), withAttributes: attrs)
        state.y += 18
    }

    /// Рисует одну ячейку монитора готовности (Readiness Monitor).
    ///
    /// - Parameters:
    ///   - y: Вертикальная позиция ячейки
    ///   - monitor: Данные монитора (имя + статус готовности)
    ///   - x: Горизонтальная позиция ячейки
    ///   - w: Ширина ячейки
    ///
    /// Ячейка содержит:
    /// - Скруглённый фон (зелёный если готов, оранжевый если нет)
    /// - Цветной кружок-индикатор (8×8 pt)
    /// - Название монитора (слева от кружка)
    /// - Статус «ГОТОВ» / «НЕ ГОТОВ» (жирный, выровнен вправо)
    private func drawReadinessCell(y: CGFloat, monitor: ReadinessMonitor, x: CGFloat, w: CGFloat) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let bgColor = monitor.ready
            ? UIColor(red: 232/255, green: 252/255, blue: 238/255, alpha: 1)
            : UIColor(red: 255/255, green: 244/255, blue: 224/255, alpha: 1)
        let cellRect = CGRect(x: x, y: y, width: w, height: 20)
        let cellPath = UIBezierPath(roundedRect: cellRect, cornerRadius: 5)
        ctx.setFillColor(bgColor.cgColor)
        ctx.addPath(cellPath.cgPath)
        ctx.fillPath()

        // Status circle
        let dotColor = monitor.ready ? C_GREEN : C_ORANGE
        ctx.setFillColor(dotColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: x + 6, y: y + 6, width: 8, height: 8))

        // Monitor name
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5),
            .foregroundColor: C_TEXT
        ]
        (monitor.name as NSString).draw(at: CGPoint(x: x + 19, y: y + 3), withAttributes: nameAttrs)

        // Ready status label
        let statusLabel = monitor.ready ? "ГОТОВ" : "НЕ ГОТОВ"
        let statusAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 7),
            .foregroundColor: dotColor
        ]
        let statusNS = statusLabel as NSString
        let statusSize = statusNS.size(withAttributes: statusAttrs)
        statusNS.draw(at: CGPoint(x: x + w - 5 - statusSize.width, y: y + 5),
                      withAttributes: statusAttrs)
    }

    /// Рисует одну ячейку Freeze Frame (параметр двигателя).
    ///
    /// - Parameters:
    ///   - y: Вертикальная позиция ячейки
    ///   - label: Название параметра (мелкий серый текст сверху)
    ///   - value: Значение с единицей измерения (жирный текст снизу)
    ///   - x: Горизонтальная позиция ячейки
    ///   - w: Ширина ячейки
    ///
    /// Ячейка — скруглённый прямоугольник 28 pt высотой с фоном `C_CARD`.
    private func drawFreezeCell(y: CGFloat, label: String, value: String, x: CGFloat, w: CGFloat) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let cellRect = CGRect(x: x, y: y, width: w, height: 28)
        let cellPath = UIBezierPath(roundedRect: cellRect, cornerRadius: 5)
        ctx.setFillColor(C_CARD.cgColor)
        ctx.addPath(cellPath.cgPath)
        ctx.fillPath()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: C_SUBTEXT
        ]
        (label as NSString).draw(at: CGPoint(x: x + 8, y: y + 1), withAttributes: labelAttrs)

        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 13),
            .foregroundColor: C_TEXT
        ]
        (value as NSString).draw(at: CGPoint(x: x + 8, y: y + 12), withAttributes: valAttrs)
    }

    /// Рисует карточку одного DTC-кода неисправности.
    ///
    /// - Parameters:
    ///   - state: Текущее состояние страницы
    ///   - entry: Данные о коде (код, название, причины, ремонт, severity)
    ///   - isPending: `true` для ожидающих кодов (добавляется бейдж «ОЖИДАЮЩИЙ»)
    ///
    /// Структура карточки:
    /// - Скруглённый фон `C_CARD` (7 pt radius)
    /// - Цветная полоса severity по левому краю (5 pt шириной):
    ///   красная (severity 3), оранжевая (2), жёлтая (остальное)
    /// - Бейдж с кодом (синий или оранжевый фон для pending)
    /// - Бейдж «ОЖИДАЮЩИЙ» (только для pending-кодов)
    /// - Название неисправности
    /// - Блок «Причина:» с автопереносом строк
    /// - Блок «Ремонт:» (зелёный текст) с автопереносом строк
    ///
    /// Высота карточки динамическая — зависит от длины текста причин/ремонта.
    private func drawDtcCard(state: PageState, entry: DtcEntry, isPending: Bool) {
        let causeLines = wrapText(entry.causes, fontSize: 8.5, maxWidth: CW - 95)
        let repairLines = wrapText(entry.repair, fontSize: 8.5, maxWidth: CW - 95)
        var cardH: CGFloat = 14 + 14
        if !entry.causes.isEmpty { cardH += CGFloat(causeLines.count) * 12 + 14 }
        if !entry.repair.isEmpty { cardH += CGFloat(repairLines.count) * 12 + 14 }
        cardH += 10

        state.ensureSpace(cardH + 8)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let top = state.y

        // Card background
        let cardRect = CGRect(x: ML, y: top, width: CW, height: cardH)
        let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 7)
        ctx.setFillColor(C_CARD.cgColor)
        ctx.addPath(cardPath.cgPath)
        ctx.fillPath()

        // Severity bar (left edge)
        let barColor: UIColor
        switch entry.severity {
        case 3:  barColor = C_RED
        case 2:  barColor = C_ORANGE
        default: barColor = C_YELLOW
        }
        let barRect = CGRect(x: ML, y: top, width: 5, height: cardH)
        let barPath = UIBezierPath(roundedRect: barRect, cornerRadius: 7)
        ctx.setFillColor(barColor.cgColor)
        ctx.addPath(barPath.cgPath)
        ctx.fillPath()
        ctx.fill(CGRect(x: ML + 2, y: top, width: 3, height: cardH))

        // Code badge
        let badgeBg = isPending ? C_PENDING : UIColor(red: 228/255, green: 240/255, blue: 255/255, alpha: 1)
        let badgeRect = CGRect(x: ML + 12, y: top + 7, width: 50, height: 14)
        let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 4)
        ctx.setFillColor(badgeBg.cgColor)
        ctx.addPath(badgePath.cgPath)
        ctx.fillPath()

        let codeColor = isPending ? C_ORANGE : C_ACCENT
        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 9),
            .foregroundColor: codeColor
        ]
        let codeNS = entry.code as NSString
        let codeSize = codeNS.size(withAttributes: codeAttrs)
        codeNS.draw(at: CGPoint(x: ML + 12 + (50 - codeSize.width) / 2,
                                y: top + 7 + (14 - codeSize.height) / 2),
                    withAttributes: codeAttrs)

        // "ОЖИДАЮЩИЙ" badge
        var xTitle: CGFloat = ML + 68
        if isPending {
            let pendRect = CGRect(x: xTitle, y: top + 7, width: 64, height: 14)
            let pendPath = UIBezierPath(roundedRect: pendRect, cornerRadius: 4)
            ctx.setFillColor(C_PENDING.cgColor)
            ctx.addPath(pendPath.cgPath)
            ctx.fillPath()

            let pendAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 7),
                .foregroundColor: C_ORANGE
            ]
            let pendNS = "ОЖИДАЮЩИЙ" as NSString
            let pendSize = pendNS.size(withAttributes: pendAttrs)
            pendNS.draw(at: CGPoint(x: xTitle + (64 - pendSize.width) / 2,
                                    y: top + 7 + (14 - pendSize.height) / 2),
                        withAttributes: pendAttrs)
            xTitle += 70
        }

        // DTC title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: C_TEXT
        ]
        (entry.title as NSString).draw(at: CGPoint(x: xTitle, y: top + 7), withAttributes: titleAttrs)

        var rowY = top + 30

        // Causes
        if !entry.causes.isEmpty {
            let causeHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 8),
                .foregroundColor: C_SUBTEXT
            ]
            ("Причина:" as NSString).draw(at: CGPoint(x: ML + 12, y: rowY), withAttributes: causeHeaderAttrs)
            rowY += 13

            let causeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8.5),
                .foregroundColor: C_TEXT
            ]
            for line in causeLines {
                (line as NSString).draw(at: CGPoint(x: ML + 20, y: rowY), withAttributes: causeAttrs)
                rowY += 12
            }
        }

        // Repair
        if !entry.repair.isEmpty {
            let repairHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 8),
                .foregroundColor: UIColor(red: 30/255, green: 110/255, blue: 60/255, alpha: 1)
            ]
            ("Ремонт:" as NSString).draw(at: CGPoint(x: ML + 12, y: rowY), withAttributes: repairHeaderAttrs)
            rowY += 13

            let repairAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8.5),
                .foregroundColor: UIColor(red: 30/255, green: 100/255, blue: 55/255, alpha: 1)
            ]
            for line in repairLines {
                (line as NSString).draw(at: CGPoint(x: ML + 20, y: rowY), withAttributes: repairAttrs)
                rowY += 12
            }
        }

        state.y = top + cardH + 8
    }

    // MARK: - Text Wrapping

    /// Разбивает текст на строки, укладывающиеся в заданную ширину.
    ///
    /// - Parameters:
    ///   - text: Исходный текст
    ///   - fontSize: Размер шрифта для расчёта ширины
    ///   - maxWidth: Максимальная ширина строки в пунктах
    /// - Returns: Массив строк, каждая из которых помещается в `maxWidth`
    ///
    /// Использует `NSString.size(withAttributes:)` для точного измерения ширины.
    /// Перенос выполняется по словам (пробелам).
    private func wrapText(_ text: String, fontSize: CGFloat, maxWidth: CGFloat) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fontSize)]
        let words = trimmed.components(separatedBy: " ")
        var lines: [String] = []
        var current = ""

        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            let size = (candidate as NSString).size(withAttributes: attrs)
            if size.width <= maxWidth {
                current = candidate
            } else {
                if !current.isEmpty { lines.append(current) }
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [text] : lines
    }
}

// MARK: - PageState

/// Вспомогательный класс для управления состоянием многостраничного PDF.
///
/// Отслеживает текущую вертикальную позицию (`y`), номер страницы и
/// автоматически создаёт новые страницы при нехватке места.
///
/// ## Жизненный цикл
/// 1. Создание: `PageState(pageWidth:pageHeight:)`
/// 2. Установка контекста: `state.context = rendererContext`
/// 3. Первая страница: `state.newPage()`
/// 4. Отрисовка секций с проверкой места: `state.ensureSpace(_:)`
/// 5. Завершение: `state.finish()` — рисует нижний колонтитул последней страницы
private class PageState {

    /// Ширина страницы в пунктах
    let pageWidth: CGFloat
    /// Высота страницы в пунктах
    let pageHeight: CGFloat

    /// Контекст PDF-рендерера (устанавливается перед началом отрисовки)
    var context: UIGraphicsPDFRendererContext?
    /// Текущая вертикальная позиция курсора на странице (pt от верхнего края)
    var y: CGFloat = 0
    /// Номер текущей страницы (начинается с 1 после первого вызова `newPage()`)
    var pageNum = 0

    /// - Parameters:
    ///   - pageWidth: Ширина страницы (595 pt для A4)
    ///   - pageHeight: Высота страницы (842 pt для A4)
    init(pageWidth: CGFloat, pageHeight: CGFloat) {
        self.pageWidth = pageWidth
        self.pageHeight = pageHeight
    }

    /// Начинает новую страницу PDF.
    ///
    /// Перед началом новой страницы рисует нижний колонтитул на предыдущей (если она не первая).
    /// Заливает фон белым. На первой странице `y = 0` (шапка начинается сверху),
    /// на последующих — `y = 40` (отступ от верхнего края).
    func newPage() {
        if pageNum > 0 {
            drawPageFooter()
        }
        context?.beginPage()
        pageNum += 1

        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        y = (pageNum == 1) ? 0 : 40
    }

    /// Проверяет, достаточно ли места для контента заданной высоты.
    ///
    /// Если текущая позиция `y` + `needed` выходит за нижний предел страницы
    /// (с учётом 50 pt резерва для колонтитула), автоматически вызывает `newPage()`.
    ///
    /// - Parameter needed: Требуемая высота свободного пространства в пунктах
    func ensureSpace(_ needed: CGFloat) {
        if y + needed > pageHeight - 50 {
            newPage()
        }
    }

    /// Завершает генерацию PDF — рисует нижний колонтитул на последней странице.
    func finish() {
        if pageNum > 0 {
            drawPageFooter()
        }
    }

    /// Рисует нижний колонтитул страницы.
    ///
    /// Содержит горизонтальную линию, текст «UREMONT WHOOP — Отчёт OBD2 диагностики»
    /// слева и номер страницы «Стр. N» справа. Расположен на 34 pt выше нижнего края.
    private func drawPageFooter() {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let ml: CGFloat = 36
        let rightEdge = pageWidth - ml
        let lineY = pageHeight - 34
        let textY = pageHeight - 28

        ctx.setStrokeColor(UIColor(red: 218/255, green: 218/255, blue: 226/255, alpha: 1).cgColor)
        ctx.setLineWidth(0.7)
        ctx.move(to: CGPoint(x: ml, y: lineY))
        ctx.addLine(to: CGPoint(x: rightEdge, y: lineY))
        ctx.strokePath()

        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor(red: 110/255, green: 110/255, blue: 120/255, alpha: 1)
        ]
        ("UREMONT WHOOP — Отчёт OBD2 диагностики" as NSString).draw(
            at: CGPoint(x: ml, y: textY), withAttributes: footerAttrs)

        let pageStr = "Стр. \(pageNum)" as NSString
        let pageSize = pageStr.size(withAttributes: footerAttrs)
        pageStr.draw(at: CGPoint(x: rightEdge - pageSize.width, y: textY), withAttributes: footerAttrs)
    }
}
