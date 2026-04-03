/// Страница подключения (страница 0 горизонтального пейджера).
///
/// Отображает:
/// - Логотип и название приложения (``LogoHeader``)
/// - Переключатель профиля авто (Авто / Ручной режим) через ``ProfileChip``
/// - Карточку статуса подключения (``StatusCard``)
/// - Кнопку подключения/отключения адаптера (``WhoopButton``)
/// - После подключения: данные автомобиля (``VehicleInfoCard``),
///   мониторы готовности систем (``ReadinessCard``),
///   навигационную кнопку перехода к диагностике (``DiagnosticsNavigationBar``)
///
/// Все данные приходят извне через let-параметры и замыкания —
/// View не владеет бизнес-логикой, а только отображает состояние.
import SwiftUI

/// Страница подключения к OBD2-адаптеру и отображения профиля автомобиля.
///
/// Принимает все данные через параметры конструктора (unidirectional data flow).
/// Единственный @Binding — ``carProfile`` — для двустороннего обновления профиля авто.
struct ConnectionPage: View {
    /// Текстовый статус подключения для отображения в StatusCard ("Подключено", "Подключение…" и т.д.)
    let connectionStatus: String
    /// Флаг активного подключения к адаптеру
    let isConnected: Bool
    /// Флаг процесса подключения (показывает спиннер в StatusCard)
    let isConnecting: Bool

    /// Профиль автомобиля: .auto (определение по VIN) или .manual (выбран вручную)
    @Binding var carProfile: CarProfile
    /// Данные автомобиля (VIN, марка, год, ЭБУ, пробег) — nil пока не загружены
    let vehicleInfo: VehicleInfo?
    /// Массив мониторов готовности OBD2 (Catalyst, O2 Sensor, EGR и т.д.)
    let readinessMonitors: [ReadinessMonitor]

    /// Колбэк: выбран профиль «Авто» (определение марки по VIN)
    let onProfileAuto: () -> Void
    /// Колбэк: нажата кнопка ручного выбора марки/модели → открывает ManualCarPickerSheet
    let onProfileManual: () -> Void
    /// Колбэк: нажата кнопка адаптера → подключение (WifiSheet) или отключение
    let onSelectAdapter: () -> Void
    /// Колбэк: нажата навигационная кнопка «Перейти к диагностике» → скролл на страницу ошибок
    let onNavigateDiagnostics: () -> Void

    /// Анимация появления страницы (fade-in при onAppear)
    @State private var appearAlpha: Double = 0

    /// Адаптивный флаг: true на iPad для увеличенных отступов
    private var tablet: Bool { isTablet() }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: tablet ? 20 : 8)

                    // MARK: - Logo header

                    LogoHeader(tablet: tablet)

                    Spacer().frame(height: tablet ? 28 : 20)

                    // MARK: - Profile selector

                    Text("ПРОФИЛЬ АВТОМОБИЛЯ")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Brand.subtext)
                        .tracking(1.4)

                    Spacer().frame(height: 8)

                    HStack(spacing: 8) {
                        ProfileChip(
                            label: "Авто",
                            active: carProfile.isAuto,
                            action: onProfileAuto
                        )
                        ProfileChip(
                            label: carProfile.isAuto ? "Ручной режим" : carProfile.displayName,
                            active: !carProfile.isAuto,
                            action: onProfileManual
                        )
                    }

                    Spacer().frame(height: tablet ? 20 : 14)

                    // MARK: - Status card

                    StatusCard(
                        status: connectionStatus,
                        isConnected: isConnected,
                        isLoading: isConnecting
                    )

                    Spacer().frame(height: tablet ? 16 : 12)

                    // MARK: - Adapter button

                    if isConnected {
                        WhoopButton(text: "Отключиться", action: onSelectAdapter)
                    } else {
                        WhoopButton(text: "Выбрать адаптер", action: onSelectAdapter)
                    }

                    // MARK: - Vehicle info (animated)

                    if isConnected {
                        VStack(spacing: 0) {
                            Spacer().frame(height: 20)

                            VehicleInfoCard(vehicleInfo: vehicleInfo)

                            if !readinessMonitors.isEmpty {
                                Spacer().frame(height: 12)
                                ReadinessCard(monitors: readinessMonitors)
                            }

                            Spacer().frame(height: 16)

                            DiagnosticsNavigationBar(action: onNavigateDiagnostics)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.easeInOut(duration: 0.35), value: isConnected)
                    }

                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, tablet ? 32 : 20)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Brand.bg.ignoresSafeArea())
        .opacity(appearAlpha)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appearAlpha = 1 }
        }
    }
}

// MARK: - Logo Header

/// Верхний блок с логотипом UREMONT, названием приложения и подзаголовком.
///
/// Адаптируется по размеру: на iPad увеличенный логотип и шрифт.
private struct LogoHeader: View {
    /// true на iPad — увеличивает размеры логотипа и текста
    let tablet: Bool

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: tablet ? 16 : 14)
                .fill(Brand.blue)
                .frame(width: tablet ? 64 : 52, height: tablet ? 64 : 52)
                .overlay(
                    Image("UremontLogo")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white)
                        .frame(width: tablet ? 36 : 28, height: tablet ? 38 : 30)
                )

            Text("UREMONT WHOOP")
                .font(.system(size: tablet ? 18 : 16, weight: .black))
                .foregroundColor(Brand.text)
                .tracking(1.5)

            Text("OBD2 Диагностика")
                .font(.system(size: 12))
                .foregroundColor(Brand.subtext)
        }
    }
}

// MARK: - VehicleInfoCard

/// Карточка с данными автомобиля, полученными из ЭБУ (Mode 09).
///
/// Показывает VIN, марку, год выпуска, имя ЭБУ, пробег с MIL и после сброса кодов.
/// Пока данные загружаются (vehicleInfo == nil), отображает линейный прогресс-бар.
/// Если Mode 09 не поддерживается — показывает соответствующее сообщение.
struct VehicleInfoCard: View {
    /// Данные автомобиля — nil пока идёт чтение из ЭБУ
    let vehicleInfo: VehicleInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ДАННЫЕ АВТОМОБИЛЯ")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Brand.subtext)
                .tracking(1.4)

            if let info = vehicleInfo {
                let hasData = info.vin != nil || info.detectedMake != nil

                if !hasData {
                    Text("Автомобиль не передаёт данные (Mode 09 не поддерживается)")
                        .font(.system(size: 13))
                        .foregroundColor(Brand.subtext)
                        .lineSpacing(4)
                } else {
                    // Порядок и подписи как в PDF: слева смысл параметра, справа значение, разделители между строками
                    VStack(alignment: .leading, spacing: 0) {
                        if let make = info.detectedMake {
                            VehicleInfoRow(label: "Марка автомобиля", value: make)
                            VehicleInfoCardRowDivider()
                        }
                        if let year = info.detectedYear {
                            VehicleInfoRow(label: "Год выпуска", value: year)
                            VehicleInfoCardRowDivider()
                        }
                        if let vin = info.vin {
                            VehicleInfoRow(label: "VIN", value: vin, isMonospace: true)
                            VehicleInfoCardRowDivider()
                        }
                        if let vds = info.vinVehicleDescriptor {
                            VehicleInfoRow(label: "VDS (VIN 4–9)", value: vds, isMonospace: true)
                            VehicleInfoCardRowDivider()
                        }
                        if let g = info.diagnosticBrandGroup, g != "OTHER" {
                            VehicleInfoRow(label: "Диагност. группа марки", value: g, isMonospace: true)
                            VehicleInfoCardRowDivider()
                        }
                        if let ecu = info.ecuName {
                            VehicleInfoRow(label: "ЭБУ двигателя", value: ecu)
                            VehicleInfoCardRowDivider()
                        }
                        if let t = info.transmissionEcuName {
                            VehicleInfoRow(label: "ЭБУ КПП (CAN 7E1)", value: t)
                            VehicleInfoCardRowDivider()
                        }
                        if let km = info.clusterOdometerKm {
                            let note = info.clusterOdometerNote.map { " (\($0))" } ?? ""
                            VehicleInfoRow(label: "Одометр щитка (UDS, опытно)\(note)", value: "\(km) км")
                            VehicleInfoCardRowDivider()
                        }
                        if let o = info.obdStandardLabel {
                            VehicleInfoRow(label: "Тип OBD (PID 1C)", value: o)
                            VehicleInfoCardRowDivider()
                        }
                        if let f = info.fuelTypeLabel {
                            VehicleInfoRow(label: "Топливо (PID 51)", value: f)
                            VehicleInfoCardRowDivider()
                        }
                        if let c = info.calibrationId {
                            VehicleInfoRow(label: "Calibration ID (09/03)", value: c)
                            VehicleInfoCardRowDivider()
                        }
                        if let cvn = info.cvnHex {
                            VehicleInfoRow(label: "CVN (09/04)", value: cvn, isMonospace: true)
                            VehicleInfoCardRowDivider()
                        }
                        if let m = info.mode09SupportMaskHex {
                            VehicleInfoRow(label: "Маска Mode 09 (00)", value: m, isMonospace: true)
                            VehicleInfoCardRowDivider()
                        }
                        if let ex = info.mode09ExtrasSummary {
                            VehicleInfoRow(label: "Mode 09 (доп.)", value: ex, isMonospace: true)
                            VehicleInfoCardRowDivider()
                        }
                        if let d = info.distanceMilKm() {
                            let suffix = info.usesImperialUnits ? " км (конв.)" : " км"
                            VehicleInfoRow(
                                label: "Пробег с Check Engine (PID 0x21)",
                                value: "\(d)\(suffix)",
                                valueColor: d > 0 ? Brand.yellow : Brand.green
                            )
                            VehicleInfoCardRowDivider()
                        }
                        if let d = info.distanceClearedKm() {
                            let suffix = info.usesImperialUnits ? " км (конв.)" : " км"
                            VehicleInfoRow(
                                label: "С последнего сброса DTC (0x31, не одометр)",
                                value: "\(d)\(suffix)"
                            )
                            VehicleInfoCardRowDivider()
                        }
                        if let v = info.fuelSystemStatus {
                            VehicleInfoRow(label: "Система топливоподачи (PID 03)", value: v)
                            VehicleInfoCardRowDivider()
                        }
                        if let v = info.warmUpsCleared {
                            VehicleInfoRow(label: "Прогревов после сброса DTC", value: "\(v)")
                            VehicleInfoCardRowDivider()
                        }
                        if let v = info.timeSinceClearedMin {
                            VehicleInfoRow(label: "Минут с момента сброса DTC", value: "\(v) мин")
                            VehicleInfoCardRowDivider()
                        }
                        if info.distanceMilKm() != nil || info.distanceClearedKm() != nil {
                            Text("PID 0x31 — не одометр приборки, а пробег после сброса ошибок сканером (max 65535 км).")
                                .font(.system(size: 10))
                                .foregroundColor(Brand.subtext.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                    }
                }
            } else {
                ProgressView()
                    .progressViewStyle(LinearProgressViewStyle(tint: Brand.blue))
                    .frame(maxWidth: .infinity)

                Text("Читаю данные из ЭБУ…")
                    .font(.system(size: 13))
                    .foregroundColor(Brand.subtext)

                Text("Занимает 5–10 секунд")
                    .font(.system(size: 11))
                    .foregroundColor(Brand.subtext.opacity(0.55))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Brand.blue.opacity(0.25), lineWidth: 1)
        )
    }
}

/// Тонкая линия между строками карточки авто (как в PDF).
private struct VehicleInfoCardRowDivider: View {
    var body: some View {
        Divider()
            .background(Brand.subtext.opacity(0.18))
            .padding(.vertical, 5)
    }
}

// MARK: - ReadinessCard

/// Карточка мониторов готовности OBD2-систем.
///
/// Каждый монитор (Catalyst, O2 Sensor, EGR и др.) показывается строкой
/// с цветным индикатором: зелёный = «Готов», жёлтый = «Не готов».
/// Данные поступают из PID 01 01 (Mode 01, PID 01).
struct ReadinessCard: View {
    /// Список мониторов готовности, полученных при подключении
    let monitors: [ReadinessMonitor]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ГОТОВНОСТЬ СИСТЕМ")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Brand.subtext)
                .tracking(1.2)

            ForEach(monitors, id: \.name) { monitor in
                HStack {
                    Text(monitor.name)
                        .font(.system(size: 12))
                        .foregroundColor(Brand.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(monitor.ready ? Brand.green : Brand.yellow)
                            .frame(width: 8, height: 8)

                        Text(monitor.ready ? "Готов" : "Не готов")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(monitor.ready ? Brand.green : Brand.yellow)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Brand.border, lineWidth: 1)
        )
    }
}

// MARK: - Diagnostics Navigation Bar

/// Кнопка-бар «Перейти к диагностике» внизу страницы подключения.
///
/// Появляется только при активном подключении; по нажатию
/// программно переключает пейджер на страницу ошибок (PAGE_ERRORS).
private struct DiagnosticsNavigationBar: View {
    /// Колбэк при нажатии — скроллит пейджер на страницу ошибок
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("Перейти к диагностике")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Brand.green)

                Spacer()

                Text("→")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Brand.green)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Brand.green.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Brand.green.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
