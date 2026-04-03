/// Страница диагностики ошибок (страница 1 горизонтального пейджера).
///
/// Отображает:
/// - Кнопки «Прочитать» / «Очистить» / «PDF» для управления диагностикой
/// - Карточку Freeze Frame (``FreezeFrameCard``) — снимок параметров при появлении ошибки
/// - Секцию постоянных DTC-кодов (Mode 03) через ``DtcErrorCard``
/// - Секцию ожидающих DTC-кодов (Mode 07) через ``DtcErrorCard``
/// - Блок ECU (``MainEcuBlockCard`` + ``OtherEcuCard``) — сводка по блокам управления
///
/// Типы: DtcResult, FreezeFrameData, EcuDtcResult, VehicleInfo → ObdConnectionManager.swift
/// Типы: DtcInfo, CarProfile → DtcDatabase.swift  |  ErrorsState → MainTabView.swift
import SwiftUI

/// Экран ошибок: чтение/сброс DTC, Freeze Frame, блоки ECU, экспорт PDF.
/// Типы: DtcResult, FreezeFrameData, EcuDtcResult, VehicleInfo → ObdConnectionManager.swift
/// Типы: DtcInfo, CarProfile → DtcDatabase.swift  |  ErrorsState → MainTabView.swift

// MARK: - DtcSectionHeader

/// Заголовок секции DTC-кодов с цветной полоской, названием и опциональным счётчиком.
///
/// Используется для разделения постоянных, ожидающих ошибок и блоков управления.
/// Может содержать подсказку (hint) для пояснения типа ошибок.
struct DtcSectionHeader: View {
    /// Текст заголовка секции (например, «ПОСТОЯННЫЕ ОШИБКИ»)
    let label: String
    /// Количество элементов в секции (отображается в бейдже); nil — не показывать
    let count: Int?
    /// Цвет полоски и бейджа (Brand.red для постоянных, Brand.yellow для ожидающих и т.д.)
    let color: Color
    /// Подсказка под заголовком (например, описание типа ошибок)
    var hint: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3, height: 14)
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(color)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            if !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(Brand.subtext)
                    .lineSpacing(1)
            }
        }
    }
}

// MARK: - FreezeFrameCard

/// Карточка Freeze Frame — снимок параметров двигателя в момент появления первой ошибки.
///
/// Данные запрашиваются через OBD2 Mode 02.
/// Отображает до 8 параметров (обороты, скорость, температура и т.д.) в сетке 2×N.
struct FreezeFrameCard: View {
    /// Данные Freeze Frame, полученные из ЭБУ
    let ff: FreezeFrameData

    var body: some View {
        let cols = buildColumns()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Brand.blue)
                    .frame(width: 3, height: 14)
                Text("СНИМОК ПАРАМЕТРОВ ПРИ ОШИБКЕ")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundColor(Brand.blue)
            }
            Text("Состояние датчиков в момент появления первой ошибки")
                .font(.system(size: 11))
                .foregroundColor(Brand.subtext)

            let rows = cols.chunked(into: 2)
            ForEach(rows.indices, id: \.self) { rowIdx in
                HStack(spacing: 8) {
                    ForEach(rows[rowIdx].indices, id: \.self) { colIdx in
                        let item = rows[rowIdx][colIdx]
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(.system(size: 10))
                                .foregroundColor(Brand.subtext)
                            Text(item.value)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Brand.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Brand.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if rows[rowIdx].count == 1 {
                        Spacer().frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(14)
        .background(Brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Brand.blue.opacity(0.3), lineWidth: 1)
        )
    }

    /// Внутренняя модель для одного параметра Freeze Frame (название + значение)
    private struct FreezeItem { let label: String; let value: String }

    /// Формирует список параметров Freeze Frame из доступных данных
    private func buildColumns() -> [FreezeItem] {
        var items: [FreezeItem] = []
        if let v = ff.dtcCode      { items.append(.init(label: "DTC снимка",        value: v)) }
        if let v = ff.rpm          { items.append(.init(label: "Обороты",           value: "\(v) об/мин")) }
        if let v = ff.speed        { items.append(.init(label: "Скорость",          value: "\(v) км/ч")) }
        if let v = ff.coolantTemp  { items.append(.init(label: "Охлаждающая ж-сть", value: "\(v) °C")) }
        if let v = ff.engineLoad   { items.append(.init(label: "Нагрузка",          value: "\(Int(v)) %")) }
        if let v = ff.throttle     { items.append(.init(label: "Дроссель",          value: "\(Int(v)) %")) }
        if let v = ff.shortFuelTrim { items.append(.init(label: "Коррекция (краткоср.)", value: String(format: "%.1f %%", v))) }
        if let v = ff.longFuelTrim { items.append(.init(label: "Коррекция (долгоср.)", value: String(format: "%.1f %%", v))) }
        if let v = ff.map          { items.append(.init(label: "Давление впуска",   value: "\(v) кПа")) }
        if let v = ff.iat          { items.append(.init(label: "Темп. воздуха",     value: "\(v) °C")) }
        if let v = ff.voltage      { items.append(.init(label: "Напряжение борт.",  value: String(format: "%.1f В", v))) }
        if let v = ff.fuelStatus   { items.append(.init(label: "Топливоподача",     value: v)) }
        return items
    }
}

// MARK: - MainEcuBlockCard

/// Карточка главного блока управления двигателем (ECU адрес 7E0).
///
/// Показывает сводку: количество постоянных и ожидающих ошибок.
/// Цвет рамки — зелёный (нет ошибок) или оранжевый (есть ошибки).
struct MainEcuBlockCard: View {
    /// Результат чтения постоянных DTC (Mode 03) для основного ЭБУ
    let mainResult: DtcResult
    /// Результат чтения ожидающих DTC (Mode 07) для основного ЭБУ
    let pendingResult: DtcResult

    var body: some View {
        let mainCount = dtcCount(mainResult)
        let pendingCount = dtcCount(pendingResult)
        let hasErrors = mainCount > 0 || pendingCount > 0
        let borderColor: Color = hasErrors ? Brand.orange : Brand.green
        let statusText: String = {
            switch (mainCount > 0, pendingCount > 0) {
            case (true, true):  return "\(mainCount) пост. / \(pendingCount) ожид."
            case (true, false): return "\(mainCount) постоянных"
            case (false, true): return "\(pendingCount) ожидающих"
            default:            return "Ошибок нет"
            }
        }()

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Двигатель / ЭБУ")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Brand.text)
                Text("Подробности — в разделах выше")
                    .font(.system(size: 11))
                    .foregroundColor(Brand.subtext)
            }
            Spacer()
            HStack(spacing: 6) {
                Text(statusText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(borderColor)
                Text("7E0")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Brand.subtext)
            }
        }
        .padding(14)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor.opacity(0.2), lineWidth: 1)
        )
    }

    /// Возвращает количество DTC-кодов из результата; 0 если результат не .dtcList
    private func dtcCount(_ result: DtcResult) -> Int {
        if case .dtcList(let codes) = result { return codes.count }
        return 0
    }
}

// MARK: - OtherEcuCard (expandable)

/// Раскрываемая карточка дополнительного блока управления (ABS, SRS, КПП, Кузов и др.).
///
/// В свёрнутом состоянии показывает сводку (количество ошибок или «Ошибок нет»).
/// При раскрытии — полный список DTC-кодов с карточками ``DtcErrorCard``.
struct OtherEcuCard: View {
    /// Данные дополнительного ЭБУ (имя, OBD-адрес, результат чтения)
    let ecu: EcuDtcResult
    /// Профиль авто — нужен для поиска расшифровки DTC в базе
    let carProfile: CarProfile
    /// Данные автомобиля — для формирования URL на сайт UREMONT
    let vehicleInfo: VehicleInfo?
    /// Колбэк при нажатии на DTC-карточку — открывает URL в браузере
    let onDtcClick: (String) -> Void

    /// Флаг раскрытия списка ошибок (анимированное разворачивание)
    @State private var isExpanded = false

    private var totalDtcCount: Int {
        let confirmed = { () -> Int in if case .dtcList(let c) = ecu.result { return c.count } else { return 0 } }()
        let pending   = { () -> Int in if case .dtcList(let c) = ecu.pendingResult { return c.count } else { return 0 } }()
        let permanent = { () -> Int in if case .dtcList(let c) = ecu.permanentResult { return c.count } else { return 0 } }()
        return confirmed + pending + permanent
    }

    var body: some View {
        let hasErrors = totalDtcCount > 0
        let borderColor: Color = {
            if case .error = ecu.result { return Brand.subtext }
            return hasErrors ? Brand.orange : Brand.green
        }()
        let icon: String = {
            if case .error = ecu.result { return "—" }
            return hasErrors ? "⚠" : "✅"
        }()

        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() } }) {
                HStack {
                    Text(ecu.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Brand.text)
                    Spacer()
                    HStack(spacing: 4) {
                        Text(icon).font(.system(size: 12))
                        Text(ecu.address)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Brand.subtext)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Brand.subtext)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded { ecuContentExpanded } else { ecuSummary }
        }
        .padding(14)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var ecuSummary: some View {
        if case .error(let msg) = ecu.result {
            Text(msg).font(.system(size: 12)).foregroundColor(Brand.subtext)
        } else if totalDtcCount == 0 {
            Text("Ошибок нет").font(.system(size: 12)).foregroundColor(Brand.green)
        } else {
            Text("\(totalDtcCount) ошибок найдено").font(.system(size: 12, weight: .semibold)).foregroundColor(Brand.orange)
        }
    }

    @ViewBuilder
    private var ecuContentExpanded: some View {
        if case .error(let msg) = ecu.result {
            Text(msg).font(.system(size: 12)).foregroundColor(Brand.subtext)
        } else if totalDtcCount == 0 {
            Text("Ошибок нет").font(.system(size: 12)).foregroundColor(Brand.green)
        } else {
            if case .dtcList(let codes) = ecu.result, !codes.isEmpty {
                dtcSection(codes: codes, label: "Постоянные", color: Brand.red)
            }
            if case .dtcList(let codes) = ecu.pendingResult, !codes.isEmpty {
                dtcSection(codes: codes, label: "Ожидающие", color: Brand.yellow)
            }
            if case .dtcList(let codes) = ecu.permanentResult, !codes.isEmpty {
                dtcSection(codes: codes, label: "Permanent", color: Brand.orange)
            }
        }
    }

    @ViewBuilder
    private func dtcSection(codes: [String], label: String, color: Color) -> some View {
        Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(color)
        ForEach(codes, id: \.self) { code in
            let info = DtcLookup.dtcInfo(code: code, profile: carProfile, detectedMake: vehicleInfo?.detectedMake)
            DtcErrorCard(
                code: code, info: info,
                url: DtcLookup.buildUremontUrl(profile: carProfile, vehicleInfo: vehicleInfo, code: code, info: info),
                onOpenUrl: onDtcClick
            )
        }
    }
}

// MARK: - ErrorsPage

/// Основной контейнер страницы ошибок (страница 1 пейджера).
///
/// Переключается между тремя состояниями (``ErrorsState``):
/// - ``idle``: заглушка «Нажмите Прочитать» или «Подключите адаптер»
/// - ``loading``: спиннер с текстом прогресса
/// - ``result``: ScrollView с секциями DTC, Freeze Frame и блоками ECU
struct ErrorsPage: View {
    /// Флаг подключения к OBD2-адаптеру
    let isConnected: Bool
    /// Текущее состояние экрана ошибок (idle / loading / result)
    let errorsState: ErrorsState
    /// Текст прогресса при чтении ошибок (например, «Опрашиваю ECU 3/5…»)
    let loadingMessage: String
    /// Профиль автомобиля — для поиска расшифровки DTC-кодов
    let carProfile: CarProfile
    /// Данные автомобиля — для формирования URL и PDF-отчёта
    let vehicleInfo: VehicleInfo?
    /// Колбэк: нажата кнопка «Прочитать» → запускает чтение DTC
    let onRead: () -> Void
    /// Колбэк: нажата кнопка «Очистить» → отправляет команду сброса DTC (Mode 04)
    let onClear: () -> Void
    /// Колбэк: нажата карточка DTC → открывает URL на сайт UREMONT в браузере
    let onDtcClick: (String) -> Void
    /// Колбэк: нажата кнопка «PDF» → генерирует PDF-отчёт
    let onExportPdf: () -> Void

    /// Адаптивный флаг: true на iPad для увеличенных отступов
    private var tablet: Bool { isTablet() }

    var body: some View {
        let hPad: CGFloat = tablet ? 24 : 16
        let topPad: CGFloat = tablet ? 24 : 16

        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "ДИАГНОСТИКА ОШИБОК",
                subtitle: isConnected
                    ? "● \(vehicleInfo?.detectedMake ?? carProfile.displayName)"
                    : "Нет соединения",
                subtitleColor: isConnected ? Brand.green : Brand.red
            )
            .padding(.horizontal, hPad)
            .padding(.top, topPad)

            Spacer().frame(height: 14)

            // Action buttons
            HStack(spacing: 10) {
                WhoopButton(
                    text: isLoadingState ? "Опрашиваю…" : "Прочитать",
                    label: "OBD",
                    isLoading: isLoadingState,
                    enabled: isConnected && !isLoadingState,
                    action: onRead
                )
                ClearButton(
                    enabled: isConnected && !isLoadingState,
                    action: onClear
                )
                if isResultState {
                    Button(action: onExportPdf) {
                        Text("📤 PDF")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Brand.text)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Brand.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.border, lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, hPad)

            Spacer().frame(height: 16)

            Group {
                switch errorsState {
                case .idle:
                    EmptyHint(
                        icon: "🔍",
                        title: isConnected ? "Нажмите «Прочитать»" : "Подключите адаптер",
                        subtitle: isConnected ? "Запрос кодов неисправности OBD2" : "Выберите ELM327 адаптер на первом экране"
                    )

                case .loading:
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Brand.blue))
                            .scaleEffect(1.2)
                        Text(loadingMessage)
                            .font(.system(size: 14))
                            .foregroundColor(Brand.subtext)
                        Text("Не закрывайте приложение")
                            .font(.system(size: 12))
                            .foregroundColor(Brand.subtext.opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)

                case .result(let main, let pending, let permanent, let freezeFrame, let ecuResults):
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if let ff = freezeFrame, !ff.isEmpty {
                                FreezeFrameCard(ff: ff)
                            }
                            mainDtcSection(main)
                            pendingDtcSection(pending)
                            permanentDtcSection(permanent)
                            ecuBlocksSection(main: main, pending: pending, ecuResults: ecuResults)
                        }
                        .padding(.bottom, 80)
                        .padding(.horizontal, hPad)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.bg)
    }

    // MARK: - Sections

    /// Секция постоянных DTC-кодов (Mode 03): заголовок + карточки ошибок
    @ViewBuilder
    private func mainDtcSection(_ result: DtcResult) -> some View {
        switch result {
        case .noDtcs:
            EmptyHint(
                icon: "✅",
                title: "Постоянных ошибок нет",
                subtitle: "Mode 03: подтверждённых кодов в памяти ЭБУ нет. По другим блокам (КПП, ABS…) см. раздел ниже, если включены «Другие блоки»."
            )
                .frame(height: 200)
        case .rawResponse(let raw):
            EmptyHint(icon: "⚠", title: "Нераспознанный ответ", subtitle: raw)
                .frame(height: 200)
        case .error(let msg):
            EmptyHint(icon: "✕", title: "Ошибка соединения", subtitle: msg)
                .frame(height: 200)
        case .dtcList(let codes):
            DtcSectionHeader(
                label: "ПОСТОЯННЫЕ ОШИБКИ",
                count: codes.count,
                color: Brand.red,
                hint: "Mode 03 — подтверждённые коды в памяти ЭБУ (то, что обычно называют «сохранёнными» в OBD-II)"
            )
            ForEach(codes, id: \.self) { code in
                let info = DtcLookup.dtcInfo(code: code, profile: carProfile, detectedMake: vehicleInfo?.detectedMake)
                DtcErrorCard(
                    code: code, info: info,
                    url: DtcLookup.buildUremontUrl(profile: carProfile, vehicleInfo: vehicleInfo, code: code, info: info),
                    onOpenUrl: onDtcClick
                )
            }
        }
    }

    /// Секция PDTC (Mode 0A): постоянные эмиссионные коды (часто USA); показывается только если есть коды
    @ViewBuilder
    private func permanentDtcSection(_ result: DtcResult) -> some View {
        if case .dtcList(let codes) = result, !codes.isEmpty {
            Spacer().frame(height: 4)
            DtcSectionHeader(
                label: "ПОСТОЯННЫЕ ЭМИССИОННЫЕ (0A)",
                count: codes.count,
                color: Brand.orange,
                hint: "Mode 0A (Permanent DTC): не гасятся сразу после Clear; чаще встречается на авто под USA OBD-II"
            )
            ForEach(codes, id: \.self) { code in
                let info = DtcLookup.dtcInfo(code: code, profile: carProfile, detectedMake: vehicleInfo?.detectedMake)
                DtcErrorCard(
                    code: code, info: info,
                    url: DtcLookup.buildUremontUrl(profile: carProfile, vehicleInfo: vehicleInfo, code: code, info: info),
                    onOpenUrl: onDtcClick
                )
            }
        }
    }

    /// Секция ожидающих DTC-кодов (Mode 07): показывается только при наличии кодов
    @ViewBuilder
    private func pendingDtcSection(_ result: DtcResult) -> some View {
        if case .dtcList(let codes) = result, !codes.isEmpty {
            Spacer().frame(height: 4)
            DtcSectionHeader(
                label: "ОЖИДАЮЩИЕ ОШИБКИ", count: codes.count, color: Brand.yellow,
                hint: "Зафиксированы в текущем цикле, но ещё не стали постоянными"
            )
            ForEach(codes, id: \.self) { code in
                let info = DtcLookup.dtcInfo(code: code, profile: carProfile, detectedMake: vehicleInfo?.detectedMake)
                DtcErrorCard(
                    code: code, info: info,
                    url: DtcLookup.buildUremontUrl(profile: carProfile, vehicleInfo: vehicleInfo, code: code, info: info),
                    onOpenUrl: onDtcClick,
                    isPending: true
                )
            }
        }
    }

    /// Секция блоков управления: главный ЭБУ (7E0) + дополнительные ECU (ABS, SRS и т.д.)
    @ViewBuilder
    private func ecuBlocksSection(main: DtcResult, pending: DtcResult, ecuResults: [EcuDtcResult]) -> some View {
        Spacer().frame(height: 4)
        DtcSectionHeader(
            label: "БЛОКИ УПРАВЛЕНИЯ", count: nil, color: Brand.blue,
            hint: "По каждому CAN-адресу — те же «сохранённые» коды OBD Mode 03, что и в профессиональных сканерах (КПП: 7E1; у Ford добавлены марочные адреса)"
        )
        MainEcuBlockCard(mainResult: main, pendingResult: pending)

        if !ecuResults.isEmpty {
            ForEach(ecuResults) { ecu in
                OtherEcuCard(ecu: ecu, carProfile: carProfile, vehicleInfo: vehicleInfo, onDtcClick: onDtcClick)
            }
        } else {
            EmptyHint(icon: "⚙", title: "Дополнительные блоки не опрошены", subtitle: "Включите «Другие блоки» в настройках")
                .frame(height: 120)
        }
    }

    /// Вспомогательное: true если сейчас идёт чтение ошибок
    private var isLoadingState: Bool {
        if case .loading = errorsState { return true }
        return false
    }

    /// Вспомогательное: true если результаты уже получены (для показа кнопки PDF)
    private var isResultState: Bool {
        if case .result = errorsState { return true }
        return false
    }
}
