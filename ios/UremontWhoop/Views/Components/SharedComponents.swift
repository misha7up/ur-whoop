/// Общие UI-компоненты: WhoopButton, StatusCard, PageDots, ProfileChip, AppSettings, Array+Chunked и др.
///
/// Файл содержит переиспользуемые элементы интерфейса, которые применяются
/// на нескольких экранах приложения OBD2-диагностики. Сюда вынесены:
/// - Кнопки действий (`WhoopButton`, `ClearButton`)
/// - Карточка статуса подключения (`StatusCard`) с пульсирующим индикатором
/// - Заголовок страницы (`PageHeader`) и подсказка для пустого состояния (`EmptyHint`)
/// - Переключатель профилей Auto/Manual (`ProfileChip`)
/// - Индикатор текущей страницы (`PageDots`)
/// - Строка информации об автомобиле (`VehicleInfoRow`)
/// - Модель настроек `AppSettings` с персистентностью через `UserDefaults`
/// - Вспомогательное расширение `Array.chunked(into:)` для разбиения массива на группы
/// - Утилита определения iPad (`isTablet()`)
import SwiftUI

// MARK: - Array+Chunked

/// Расширение `Array` для разбиения массива на подмассивы фиксированного размера.
///
/// Используется для вёрстки сетки датчиков: массив PID-значений разбивается
/// на строки по 2–3 элемента в зависимости от ширины экрана.
extension Array {
    /// Разбивает массив на подмассивы по `size` элементов.
    /// Последний подмассив может содержать менее `size` элементов.
    /// - Parameter size: Количество элементов в каждой группе (> 0).
    /// - Returns: Массив подмассивов типа `[[Element]]`.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - AppSettings (persisted via UserDefaults)

/// Модель пользовательских настроек диагностики.
///
/// Хранит два флага, определяющих поведение сканирования:
/// - `freezeFrameEnabled` — запрашивать ли Freeze Frame (Mode 02) при чтении DTC
/// - `otherEcusEnabled` — опрашивать ли доп. ЭБУ по `ATSH` (универсальные + марочные; на CAN — UDS 0x19 при сбое Mode 03)
///
/// Каждое свойство автоматически сохраняется в `UserDefaults` через `didSet`.
/// Загрузка начальных значений — через статический метод `load()`.
struct AppSettings: Equatable {
    /// Включён ли запрос снимка параметров (Freeze Frame, Mode 02) при чтении ошибок.
    /// При `true` время диагностики увеличивается, но для каждой DTC фиксируются показатели датчиков
    /// на момент возникновения ошибки. Сохраняется в `UserDefaults` по ключу `"freezeFrameEnabled"`.
    var freezeFrameEnabled: Bool = false {
        didSet { UserDefaults.standard.set(freezeFrameEnabled, forKey: "freezeFrameEnabled") }
    }
    /// Включён ли опрос доп. ЭБУ по CAN (`ATSH` + 03/07/0A; при необходимости UDS). Долго по времени. По умолчанию `true`.
    /// Сохраняется в `UserDefaults` по ключу `"otherEcusEnabled"`.
    var otherEcusEnabled: Bool = true {
        didSet { UserDefaults.standard.set(otherEcusEnabled, forKey: "otherEcusEnabled") }
    }

    /// Загружает настройки из `UserDefaults`.
    ///
    /// Для `otherEcusEnabled` учитывается случай, когда ключ ещё не записан
    /// (первый запуск) — тогда возвращается `true` по умолчанию.
    static func load() -> AppSettings {
        let defaults = UserDefaults.standard
        return AppSettings(
            freezeFrameEnabled: defaults.bool(forKey: "freezeFrameEnabled"),
            otherEcusEnabled: defaults.object(forKey: "otherEcusEnabled") == nil
                ? true
                : defaults.bool(forKey: "otherEcusEnabled")
        )
    }
}

// MARK: - Tablet detection

/// Расширение `UIDevice` для быстрого определения типа устройства.
extension UIDevice {
    /// `true`, если устройство — iPad.
    static var isTablet: Bool { current.userInterfaceIdiom == .pad }
}

/// Глобальная функция-обёртка для проверки, запущено ли приложение на iPad.
///
/// Используется в view-билдерах для адаптации размеров сетки датчиков
/// и отступов под планшетный экран.
func isTablet() -> Bool { UIDevice.isTablet }

// MARK: - WhoopButton

/// Основная кнопка действия приложения (градиентная, брендовая).
///
/// Используется для ключевых операций: «Подключить», «Читать ошибки», «Читать датчики».
/// Поддерживает:
/// - Состояние загрузки (`isLoading`) — показывает спиннер вместо текста
/// - Неактивное состояние (`enabled`) — понижает непрозрачность до 0.45
/// - Опциональный лейбл-бейдж (`label`) — маленький тег слева от текста (например, «OBD»)
///
/// Визуал: линейный градиент `Brand.blue → Brand.blueDark`, скруглённые углы 14pt, высота 52pt.
struct WhoopButton: View {
    /// Основной текст кнопки, отображаемый по центру.
    let text: String
    /// Опциональный мини-бейдж слева от текста (например, номер режима OBD).
    /// Если пустая строка — бейдж не отображается.
    var label: String = ""
    /// Флаг состояния загрузки. При `true` вместо лейбла показывается `ProgressView`.
    var isLoading: Bool = false
    /// Доступна ли кнопка для нажатия. При `false` — визуально затемняется и не реагирует на тапы.
    var enabled: Bool = true
    /// Замыкание, вызываемое при нажатии (только если `enabled && !isLoading`).
    let action: () -> Void

    var body: some View {
        Button(action: { if enabled && !isLoading { action() } }) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.7)
                } else if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Text(text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Brand.blue, Brand.blueDark],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isLoading)
        .animation(.easeInOut(duration: 0.2), value: enabled)
        .accessibilityLabel(text)
        .accessibilityHint(isLoading ? "Загрузка" : (enabled ? "Нажмите для выполнения" : "Недоступно"))
    }
}

// MARK: - ClearButton

/// Кнопка сброса (стирания) ошибок DTC.
///
/// Деструктивная кнопка красного цвета, отправляющая команду Mode 04
/// через `ObdConnectionManager` для очистки кодов неисправностей из ECU.
/// Визуал: красный текст «✕ Стереть ошибки» на полупрозрачном красном фоне с обводкой.
struct ClearButton: View {
    /// Доступна ли кнопка. При `false` — затемняется и не реагирует на нажатие.
    var enabled: Bool = true
    /// Замыкание, вызываемое при нажатии (только если `enabled`).
    let action: () -> Void

    var body: some View {
        Button(action: { if enabled { action() } }) {
            HStack(spacing: 8) {
                Text("✕")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Brand.red)

                Text("Стереть ошибки")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Brand.red)
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(Brand.red.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Brand.red.opacity(0.4), lineWidth: 1)
            )
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
        .accessibilityLabel("Стереть ошибки")
        .accessibilityHint(enabled ? "Сбросить все коды неисправностей" : "Недоступно")
    }
}

// MARK: - StatusCard

/// Карточка текущего статуса подключения к OBD2-адаптеру.
///
/// Отображает текстовое описание состояния и цветной индикатор:
/// - Зелёный пульсирующий кружок — подключено
/// - Красный пульсирующий кружок — отключено
/// - Жёлтый спиннер — идёт подключение / загрузка
///
/// Анимация пульсации (opacity 0.4 ↔ 1.0) запускается при `onAppear`
/// и работает бесконечно с `autoreverses`.
struct StatusCard: View {
    /// Текстовое описание текущего статуса (например, «Подключён к 192.168.0.10:35000»).
    let status: String
    /// Флаг успешного подключения. Определяет цвет индикатора и обводки карточки.
    let isConnected: Bool
    /// Флаг процесса подключения. При `true` вместо кружка показывается жёлтый спиннер.
    var isLoading: Bool = false

    /// Текущая непрозрачность пульсирующего кружка, анимируется между 0.4 и 1.0.
    @State private var dotOpacity: Double = 0.4

    private var dotColor: Color {
        if isLoading { return Brand.yellow }
        return isConnected ? Brand.green : Brand.red
    }

    private var statusColor: Color {
        isConnected ? Brand.green : Brand.red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("СТАТУС")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Brand.subtext)
                .tracking(1.4)

            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Brand.yellow))
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                } else {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .opacity(dotOpacity)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 0.9)
                                .repeatForever(autoreverses: true)
                            ) {
                                dotOpacity = 1.0
                            }
                        }
                }

                Text(status)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(statusColor)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isConnected ? Brand.green.opacity(0.3) : Brand.border,
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Статус подключения: \(status)")
    }
}

// MARK: - PageHeader

/// Заголовок страницы с основным названием и подзаголовком.
///
/// Используется в верхней части каждого таба (Connect, Ошибки, Датчики).
/// Подзаголовок обычно содержит информацию о подключённом авто или статусе.
struct PageHeader: View {
    /// Основной текст заголовка (крупный, жирный, белый).
    let title: String
    /// Вспомогательный текст под заголовком (мелкий, приглушённый).
    let subtitle: String
    /// Цвет подзаголовка. По умолчанию — `Brand.subtext` (приглушённый серый).
    var subtitleColor: Color = Brand.subtext

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 18, weight: .black))
                .foregroundColor(Brand.text)
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(subtitleColor)
                .lineLimit(1)
        }
    }
}

// MARK: - EmptyHint

/// Заглушка для пустого состояния экрана.
///
/// Показывается, когда данных нет: например, «Ошибок не найдено» на вкладке DTC
/// или «Нет данных датчиков» на вкладке Sensors. Содержит эмодзи-иконку, заголовок
/// и описание, центрированные по вертикали и горизонтали.
struct EmptyHint: View {
    /// Эмодзи-иконка, отображаемая крупным шрифтом (40pt) в верхней части.
    let icon: String
    /// Заголовок подсказки (белый, 16pt, полужирный).
    let title: String
    /// Описание под заголовком (серый, 13pt), может быть многострочным.
    let subtitle: String

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 0) {
                Text(icon)
                    .font(.system(size: 40))

                Spacer().frame(height: 12)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Brand.text)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 6)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Brand.subtext)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ProfileChip

/// Чип-кнопка для выбора профиля автомобиля (Auto / Manual).
///
/// Два чипа размещаются в горизонтальном ряду на экране Connect:
/// - «Авто» — определение VIN автоматически через OBD
/// - «Ручной» — выбор марки/модели/года вручную через `ManualCarPickerSheet`
///
/// Активный чип подсвечен `Brand.blue` с белым текстом, неактивный — серый.
struct ProfileChip: View {
    /// Текст на чипе (например, «Авто» или «Ручной»).
    let label: String
    /// Флаг выбранного состояния. Определяет цвет фона и текста.
    let active: Bool
    /// Замыкание, вызываемое при нажатии на чип.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: active ? .bold : .regular))
                .foregroundColor(active ? .white : Brand.subtext)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(active ? Brand.blue : Brand.card)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(active ? Brand.blue : Brand.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Профиль: \(label)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// MARK: - PageDots

/// Индикатор текущей страницы (page control) с текстовыми метками.
///
/// Отображает три точки с подписями: «CONNECT», «ОШИБКИ», «ДАТЧИКИ».
/// Текущая страница подсвечена `Brand.blue`, остальные — `Brand.border`.
/// Размещается поверх контента внизу экрана с полупрозрачным фоном-капсулой.
struct PageDots: View {
    /// Индекс текущей активной страницы (0-based).
    let currentPage: Int
    /// Массив текстовых меток для каждой страницы.
    /// По умолчанию: `["CONNECT", "ОШИБКИ", "ДАТЧИКИ"]`.
    let labels: [String]

    init(currentPage: Int, labels: [String] = ["CONNECT", "ОШИБКИ", "ДАТЧИКИ"]) {
        self.currentPage = currentPage
        self.labels = labels
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let active = index == currentPage
                HStack(spacing: 4) {
                    Circle()
                        .fill(active ? Brand.blue : Brand.border)
                        .frame(width: 6, height: 6)

                    Text(label)
                        .font(.system(size: 9, weight: active ? .bold : .regular))
                        .foregroundColor(active ? Brand.blue : Brand.border)
                        .tracking(0.8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Brand.bg.opacity(0.9))
        .clipShape(Capsule())
    }
}

// MARK: - VehicleInfoRow

/// Строка «ключ — значение» для отображения информации об автомобиле.
///
/// Используется на экране Connect для показа данных, полученных от ECU:
/// VIN, протокол, напряжение батареи и т.д.
/// Метка занимает ~42% ширины, значение — ~58% (через `layoutPriority`).
struct VehicleInfoRow: View {
    /// Название параметра (левая сторона), отображается приглушённым цветом.
    let label: String
    /// Значение параметра (правая сторона), выравнено по правому краю.
    let value: String
    /// Использовать ли моноширинный шрифт для значения (удобно для VIN, HEX-данных).
    var isMonospace: Bool = false
    /// Цвет текста значения. По умолчанию — `Brand.text` (белый).
    var valueColor: Color = Brand.text

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Brand.subtext)
                .frame(maxWidth: 168, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: isMonospace ? .monospaced : .default))
                .foregroundColor(valueColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .lineLimit(6)
        }
    }
}
