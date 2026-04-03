/// Страница мониторинга датчиков в реальном времени (страница 2 горизонтального пейджера).
///
/// Отображает сетку ``SensorCard`` по всем PID из массива ``UNIVERSAL_PIDS``.
/// Каждая карточка показывает текущее значение датчика, единицу измерения,
/// цветной индикатор статуса (ok / warning / error / unsupported)
/// и анимированный прогресс-бар.
///
/// Polling датчиков управляется из ``AppViewModel.pollSensors()`` —
/// этот View только отображает данные из словаря ``sensorReadings``.
import SwiftUI

// MARK: - SensorCard

/// Карточка одного OBD2-датчика для Live Dashboard.
///
/// Содержит:
/// - Бейдж с коротким кодом PID (например, «RPM», «SPD»)
/// - Цветную точку статуса (зелёный / жёлтый / красный / серый)
/// - Крупное моноширинное значение с анимацией перехода
/// - Единицу измерения и название датчика
/// - Прогресс-бар внизу (доля от максимального значения)
struct SensorCard: View {
    /// Описание PID-команды (код, название, единицы, пороги)
    let pid: ObdPid
    /// Последнее показание датчика — nil если ещё не было ответа
    let reading: SensorReading?

    /// Анимируемое значение — плавно переходит к новому при каждом обновлении
    @State private var animatedValue: Float = 0

    /// Цвет индикатора статуса на основе SensorReading.status
    private var statusColor: Color {
        switch reading?.status {
        case .ok:          return Brand.green
        case .warning:     return Brand.yellow
        case .unsupported: return Brand.border
        case .error:       return Brand.red
        default:           return Brand.border
        }
    }

    /// Форматированное значение для отображения: целое или с 1 знаком после запятой
    private var displayValue: String {
        if reading?.status == .unsupported { return "N/A" }
        guard reading?.value != nil else { return "—" }
        let v = animatedValue
        if v == Float(Int(v)) { return "\(Int(v))" }
        return String(format: "%.1f", v)
    }

    /// Максимальное значение для прогресс-бара; берётся из pid.maxWarning или из дефолтов по типу PID
    private var maxForBar: Float {
        pid.maxWarning ?? {
            switch pid.shortCode {
            case "RPM": return 8000
            case "SPD": return 240
            case "ECT": return 130
            case "VLT": return 16
            case "IGN": return 60
            case "MAF": return 50
            case "RUN": return 3600
            default:    return 100
            }
        }()
    }

    /// Доля заполнения прогресс-бара (0…1)
    private var barProgress: CGFloat {
        CGFloat(min(max((reading?.value ?? 0) / maxForBar, 0), 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Short code badge + status dot
            HStack {
                Text(pid.shortCode)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Brand.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Brand.blue.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }

            // Large monospace value
            Text(displayValue)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(reading?.status == .unsupported ? Brand.subtext : Brand.text)
                .animation(.easeInOut(duration: 0.4), value: animatedValue)

            // Unit
            Text(pid.unit)
                .font(.system(size: 10))
                .foregroundColor(Brand.subtext)

            // Name (gray, 2 lines max)
            Text(pid.name)
                .font(.system(size: 9))
                .foregroundColor(Brand.subtext.opacity(0.65))
                .lineSpacing(1)
                .lineLimit(2)
                .truncationMode(.tail)

            // Progress bar at bottom
            if reading?.value != nil && reading?.status != .unsupported {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Brand.border)
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(statusColor)
                            .frame(width: geo.size.width * barProgress, height: 3)
                            .animation(.easeInOut(duration: 0.4), value: barProgress)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(12)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Brand.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pid.name): \(displayValue) \(pid.unit)")
        .onChange(of: reading?.value) { newValue in
            withAnimation(.easeInOut(duration: 0.4)) {
                animatedValue = newValue ?? 0
            }
        }
    }
}

// MARK: - LiveDashboardPage

/// Контейнер страницы Live-мониторинга OBD2-датчиков.
///
/// В зависимости от состояния показывает:
/// - Заглушку «Нет соединения» если адаптер не подключён
/// - Заглушку «Нажмите Запустить» если мониторинг ещё не запущен
/// - ``LazyVGrid`` с ``SensorCard`` для каждого PID из ``UNIVERSAL_PIDS``
///
/// Пульсирующая зелёная точка в заголовке указывает на активный мониторинг.
struct LiveDashboardPage: View {
    /// Флаг подключения к OBD2-адаптеру
    let isConnected: Bool
    /// Флаг активного мониторинга (polling датчиков)
    let isMonitoring: Bool
    /// Словарь последних показаний датчиков: ключ = OBD-команда (например, "010C"), значение = SensorReading
    let sensorReadings: [String: SensorReading]
    /// Колбэк: переключение мониторинга (старт/стоп)
    let onToggle: () -> Void
    /// Колбэк: сброс всех накопленных показаний датчиков
    let onClearReadings: () -> Void

    /// Адаптивный флаг: true на iPad для увеличенных отступов и ширины колонок
    private var tablet: Bool { isTablet() }

    /// Прозрачность пульсирующей точки — анимируется 0.4↔1.0 при активном мониторинге
    @State private var pulseAlpha: CGFloat = 0.4

    /// Адаптивная сетка: минимальная ширина колонки 155 (iPad) / 130 (iPhone)
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: tablet ? 155 : 130), spacing: 8)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row with pulsing dot
            HStack {
                PageHeader(
                    title: "LIVE ДАТЧИКИ",
                    subtitle: isConnected ? "● Онлайн" : "Нет соединения",
                    subtitleColor: isConnected ? Brand.green : Brand.red
                )
                Spacer()
                if isMonitoring {
                    Circle()
                        .fill(Brand.green)
                        .frame(width: 10, height: 10)
                        .opacity(pulseAlpha)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 0.9)
                                .repeatForever(autoreverses: true)
                            ) {
                                pulseAlpha = 1.0
                            }
                        }
                        .onDisappear { pulseAlpha = 0.4 }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, tablet ? 24 : 16)

            Spacer().frame(height: 10)

            // Buttons
            HStack(spacing: 10) {
                WhoopButton(
                    text: !isConnected
                        ? "Нет соединения"
                        : isMonitoring ? "Остановить" : "Запустить мониторинг",
                    label: isMonitoring ? "■" : "▶",
                    enabled: isConnected,
                    action: onToggle
                )

                if !sensorReadings.isEmpty {
                    Button(action: onClearReadings) {
                        Text("Сброс")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Brand.subtext)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Brand.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Brand.border, lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 16)

            Spacer().frame(height: 12)

            // Content
            if !isConnected {
                EmptyHint(icon: "📡", title: "Нет соединения", subtitle: "Подключите адаптер ELM327")
            } else if !isMonitoring && sensorReadings.isEmpty {
                EmptyHint(
                    icon: "▶",
                    title: "Нажмите «Запустить мониторинг»",
                    subtitle: "Данные всех датчиков обновляются в реальном времени"
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(UNIVERSAL_PIDS) { pid in
                            SensorCard(
                                pid: pid,
                                reading: sensorReadings[pid.command]
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 80)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.bg)
    }
}
