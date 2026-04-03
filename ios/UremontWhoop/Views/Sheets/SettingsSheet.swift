/// Настройки диагностики: toggle Freeze Frame, toggle других ECU, консоль отладки.
///
/// Файл содержит модальный sheet настроек, управляющий параметрами
/// OBD2-диагностики, и встроенную консоль отладки:
///
/// - `SettingsSheet` — два переключателя (`freezeFrameEnabled`, `otherEcusEnabled`)
///   и кнопка открытия консоли отладки
/// - `SettingToggleRow` — строка-переключатель с заголовком и описанием
/// - `TogglePill` — кастомный визуальный toggle (капсула со скользящим кружком)
/// - `DebugConsoleView` — полноэкранный просмотрщик логов `DebugLogger`
///   с авто-обновлением каждые 500 мс, копированием и очисткой
/// - `ConsoleButton` — маленькая кнопка действия в шапке консоли
/// - `LogEntryRow` — строка лог-записи с временем, уровнем и сообщением
import SwiftUI

// MARK: - SettingsSheet

/// Модальный лист настроек диагностики.
///
/// Содержит два переключателя, влияющих на процесс сканирования:
/// 1. **Снимок параметров при ошибке** (Freeze Frame, Mode 02) — фиксирует
///    показатели датчиков на момент появления каждой DTC. Увеличивает время чтения.
/// 2. **Опрос других блоков** — пробует считать DTC из ABS, SRS, КПП и BCM
///    по CAN-шине (работает на авто с 2008+ года).
///
/// Также содержит кнопку открытия `DebugConsoleView` — полноэкранной консоли
/// с логами OBD2-команд и событий соединения.
struct SettingsSheet: View {
    /// Двунаправленная привязка к модели настроек `AppSettings`.
    /// Изменения автоматически сохраняются в `UserDefaults` через `didSet` свойств.
    @Binding var settings: AppSettings
    /// Флаг отображения модальной консоли отладки.
    @State private var showConsole = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer().frame(height: 24)

            Text("НАСТРОЙКИ ДИАГНОСТИКИ")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Brand.subtext)
                .kerning(1.4)

            Spacer().frame(height: 12)

            SettingToggleRow(
                title: "Снимок параметров при ошибке",
                subtitle: "Mode 02 — фиксирует показатели датчиков в момент появления каждой ошибки. Увеличивает время чтения.",
                enabled: settings.freezeFrameEnabled
            ) { settings.freezeFrameEnabled = $0 }

            Spacer().frame(height: 4)

            SettingToggleRow(
                title: "Опрос других блоков",
                subtitle: "Пробует считать DTC из ABS, SRS, КПП и BCM по CAN-шине. Работает только на машинах с 2008+ (CAN). Может занять 10–20 сек.",
                enabled: settings.otherEcusEnabled
            ) { settings.otherEcusEnabled = $0 }

            Spacer().frame(height: 12)

            // Debug console button
            Button {
                showConsole = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Консоль отладки")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Brand.text)
                        Text("Логи соединения и OBD2-команд — \(DebugLogger.shared.size) записей")
                            .font(.system(size: 11))
                            .foregroundColor(Brand.subtext)
                    }
                    Spacer()
                    Text("›")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Brand.subtext)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Brand.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Brand.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 36)
        .sheet(isPresented: $showConsole) {
            DebugConsoleView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - SettingToggleRow

/// Строка-переключатель настройки с заголовком, описанием и кастомным toggle.
///
/// Вся строка является кнопкой — нажатие в любом месте переключает состояние.
/// Визуально: карточка с заголовком (14pt, bold), описанием (11pt, subtext)
/// и `TogglePill` справа.
private struct SettingToggleRow: View {
    /// Заголовок настройки (основной текст).
    let title: String
    /// Подробное описание, что делает настройка.
    let subtitle: String
    /// Текущее состояние переключателя.
    let enabled: Bool
    /// Замыкание, вызываемое при переключении с новым значением.
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!enabled)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Brand.text)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Brand.subtext)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                TogglePill(enabled: enabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Brand.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Brand.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TogglePill

/// Кастомный визуальный переключатель в виде капсулы (pill toggle).
///
/// Анимированный кружок скользит внутри капсулы: вправо — включено (Brand.blue),
/// влево — выключено (Brand.border). Размер: 46×26pt.
/// Используется вместо стандартного `Toggle` для единого брендового стиля.
private struct TogglePill: View {
    /// Текущее состояние: `true` — включено, `false` — выключено.
    let enabled: Bool

    var body: some View {
        ZStack(alignment: enabled ? .trailing : .leading) {
            Capsule()
                .fill(enabled ? Brand.blue : Brand.border)
                .frame(width: 46, height: 26)
            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)
                .padding(3)
        }
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }
}

// MARK: - DebugConsoleView

/// Полноэкранная консоль отладки с логами OBD2-команд и событий соединения.
///
/// Функции:
/// - Автоматическое обновление списка логов каждые 500 мс через `Timer.publish`
/// - Автоскролл к последней записи при появлении новых
/// - Кнопка «Скопировать» — копирует все записи в буфер обмена через `UIPasteboard`
/// - Кнопка «Очистить» — сбрасывает `DebugLogger` и очищает список
///
/// Каждая запись показывает время (HH:mm:ss.SSS), уровень (D/I/W/E),
/// тег модуля и сообщение. Фон строки подсвечивается по уровню серьёзности.
struct DebugConsoleView: View {
    /// Действие для закрытия модального sheet.
    @Environment(\.dismiss) private var dismiss
    /// Локальная копия массива лог-записей, обновляемая по таймеру.
    @State private var entries: [LogEntry] = []

    /// Таймер обновления логов (каждые 500 мс).
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    /// Форматтер времени для отображения в каждой строке лога.
    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Консоль отладки")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Brand.text)
                        Text("\(entries.count) записей · обновляется каждые 500 мс")
                            .font(.system(size: 11))
                            .foregroundColor(Brand.subtext)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Text("✕")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Brand.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Brand.red.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Brand.red.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    ConsoleButton(label: "Скопировать", color: Brand.blue) {
                        UIPasteboard.general.string = DebugLogger.shared.formatAll()
                    }
                    ConsoleButton(label: "Очистить", color: Brand.yellow) {
                        DebugLogger.shared.clear()
                        entries = []
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Brand.surface)

            // Log entries
            if entries.isEmpty {
                Spacer()
                Text("Логов пока нет.\nНачните диагностику.")
                    .font(.system(size: 13))
                    .foregroundColor(Brand.subtext)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                                LogEntryRow(entry: entry, formatter: Self.timeFormatter)
                                    .id(index)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onChange(of: entries.count) { _ in
                        if let last = entries.indices.last {
                            withAnimation {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(red: 10/255, green: 10/255, blue: 13/255))
        .onReceive(timer) { _ in
            entries = DebugLogger.shared.entries
        }
        .onAppear {
            entries = DebugLogger.shared.entries
        }
    }
}

// MARK: - ConsoleButton

/// Маленькая кнопка действия в шапке консоли отладки (например, «Скопировать», «Очистить»).
private struct ConsoleButton: View {
    /// Текст на кнопке.
    let label: String
    /// Цвет текста кнопки (определяет визуальное значение: синий = нейтральное, жёлтый = предупреждение).
    let color: Color
    /// Замыкание, вызываемое при нажатии.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Brand.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Brand.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - LogEntryRow

/// Строка одной записи в консоли отладки.
///
/// Формат: `[HH:mm:ss.SSS] [D|I|W|E] [tag]: message`
///
/// Фон строки окрашивается по уровню:
/// - `.debug` — без фона, серый текст
/// - `.info` — лёгкий синий фон
/// - `.warn` — лёгкий жёлтый фон
/// - `.error` — лёгкий красный фон
private struct LogEntryRow: View {
    /// Запись лога с данными: время, уровень, тег, сообщение.
    let entry: LogEntry
    /// Форматтер для отображения времени записи.
    let formatter: DateFormatter

    /// Цвет буквы уровня (D/I/W/E).
    private var levelColor: Color {
        switch entry.level {
        case .debug: return Brand.subtext
        case .info:  return Brand.blue
        case .warn:  return Brand.yellow
        case .error: return Brand.red
        }
    }

    /// Фоновый цвет строки, зависит от уровня записи.
    private var levelBg: Color {
        switch entry.level {
        case .debug: return .clear
        case .info:  return Brand.blue.opacity(0.06)
        case .warn:  return Brand.yellow.opacity(0.06)
        case .error: return Brand.red.opacity(0.08)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(formatter.string(from: Date(timeIntervalSince1970: entry.timeMs)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Brand.subtext.opacity(0.6))
                .frame(width: 80, alignment: .leading)

            Text(entry.level.letter)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(levelColor)
                .frame(width: 12)

            Text("\(entry.tag): \(entry.message)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(entry.level == .debug ? Brand.subtext : Brand.text)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(levelBg)
    }
}
