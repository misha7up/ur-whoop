/// Модальный лист Wi-Fi подключения: инструкция, IP:порт, пресеты адаптеров.
///
/// Файл содержит модальный sheet для настройки Wi-Fi подключения к OBD2-адаптеру.
/// iOS не поддерживает Bluetooth ELM327, поэтому подключение идёт через TCP-сокет
/// по Wi-Fi сети адаптера. Пользователь вводит IP-адрес и порт, либо выбирает
/// один из популярных пресетов.
///
/// Компоненты:
/// - `WifiSheet` — основной лист с полями ввода IP и порта, кнопкой «Подключить»
/// - `InstructionsCard` — пошаговая инструкция подключения (3 шага)
/// - `PresetsRow` — горизонтальный ряд чипов с популярными адаптерами
/// - `PresetChip` — отдельный чип пресета
/// - `FieldLabel` — мелкая подпись над полем ввода
/// - `BrandTextFieldStyle` — стилизованное текстовое поле в брендовом стиле
/// - `FlowLayout` — кастомный Layout для переноса чипов на следующую строку
import SwiftUI

/// Модальный лист для ввода параметров Wi-Fi подключения к OBD2-адаптеру.
///
/// При открытии поля заполняются начальными значениями (`initialHost`, `initialPort`).
/// Если начальные значения пустые — подставляются дефолты: `192.168.0.10:35000`
/// (стандарт для Vgate/Kingbolen адаптеров).
///
/// Кнопка «Подключить» активна только при непустых полях. При нажатии вызывается
/// `onConnect(host, port)`, и родительский View инициирует TCP-соединение.
struct WifiSheet: View {
    /// Начальный IP-адрес, переданный из родительского View (может быть пустым).
    let initialHost: String
    /// Начальный порт, переданный из родительского View (может быть пустым).
    let initialPort: String
    /// Замыкание, вызываемое при нажатии «Подключить» с введёнными host и port.
    let onConnect: (_ host: String, _ port: String) -> Void

    /// Текущее значение IP-адреса в поле ввода.
    @State private var host: String = ""
    /// Текущее значение порта в поле ввода.
    @State private var port: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // MARK: - Title

            Text("Подключение по Wi-Fi")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Brand.text)

            // MARK: - Instructions card

            InstructionsCard()

            // MARK: - IP Address

            FieldLabel("IP-адрес адаптера")

            TextField("192.168.0.10", text: $host)
                .keyboardType(.decimalPad)
                .textFieldStyle(BrandTextFieldStyle())

            // MARK: - Port

            FieldLabel("Порт")

            TextField("35000", text: $port)
                .keyboardType(.numberPad)
                .textFieldStyle(BrandTextFieldStyle())

            // MARK: - Presets

            FieldLabel("Популярные адаптеры")

            PresetsRow(onApply: { h, p in host = h; port = p })

            Spacer().frame(height: 4)

            // MARK: - Connect button

            Button {
                let h = host.trimmingCharacters(in: .whitespaces)
                let p = port.trimmingCharacters(in: .whitespaces)
                guard !h.isEmpty, !p.isEmpty else { return }
                onConnect(h, p)
            } label: {
                Text("Подключить")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Brand.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty ||
                      port.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer().frame(height: 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .onAppear {
            host = initialHost.isEmpty ? BrandConfig.defaultWifiHost : initialHost
            port = initialPort.isEmpty ? String(BrandConfig.defaultWifiPort) : initialPort
        }
    }
}

// MARK: - Instructions Card

/// Карточка с пошаговой инструкцией подключения к OBD2 Wi-Fi адаптеру.
///
/// Три шага:
/// 1. Вставить адаптер в OBD2-разъём и включить зажигание
/// 2. Подключиться к Wi-Fi сети адаптера в настройках iOS
/// 3. Вернуться в приложение и нажать «Подключить»
///
/// Каждый шаг визуально пронумерован синим кружком с цифрой.
private struct InstructionsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Как подключиться")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Brand.text)

            let steps = [
                "Вставьте адаптер в OBD2-разъём, включите зажигание",
                "Откройте настройки Wi-Fi и подключитесь к сети адаптера (обычно «OBDII», «ELM327» или «WiFi_OBDII»)",
                "Вернитесь в приложение и нажмите «Подключить»",
            ]

            ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Brand.blue)
                            .frame(width: 18, height: 18)

                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text(text)
                        .font(.system(size: 12))
                        .foregroundColor(Brand.subtext)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        }
        .padding(12)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Brand.border, lineWidth: 1)
        )
    }
}

// MARK: - Presets Row

/// Горизонтальный ряд чипов с пресетами популярных OBD2 Wi-Fi адаптеров.
///
/// При нажатии на чип автоматически заполняются поля IP и порт
/// значениями, типичными для данного адаптера:
/// - Kingbolen / Vgate: `192.168.0.10:35000`
/// - ESP32 AP: `192.168.4.1:35000`
/// - OBDLink WiFi: `192.168.0.10:23`
/// - Alt 10.0.0.x: `10.0.0.1:35000`
///
/// Чипы оборачиваются на следующую строку через `FlowLayout`.
private struct PresetsRow: View {
    /// Замыкание, вызываемое при выборе пресета с host и port адаптера.
    let onApply: (_ host: String, _ port: String) -> Void

    private let presets: [(label: String, host: String, port: String)] = [
        ("Kingbolen / Vgate", BrandConfig.defaultWifiHost, String(BrandConfig.defaultWifiPort)),
        ("ESP32 AP",          "192.168.4.1",  String(BrandConfig.defaultWifiPort)),
        ("OBDLink WiFi",      BrandConfig.defaultWifiHost, "23"),
        ("Alt 10.0.0.x",      "10.0.0.1",     String(BrandConfig.defaultWifiPort)),
    ]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(presets, id: \.label) { preset in
                PresetChip(label: preset.label) {
                    onApply(preset.host, preset.port)
                }
            }
        }
    }
}

/// Отдельный чип пресета адаптера. Отображает название адаптера
/// и при нажатии вызывает замыкание `action` для заполнения полей.
private struct PresetChip: View {
    /// Отображаемое название адаптера.
    let label: String
    /// Замыкание, вызываемое при нажатии.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Brand.subtext)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
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

// MARK: - Helpers

/// Мелкая текстовая подпись над полем ввода (капс-стиль, 11pt, приглушённый цвет).
private struct FieldLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Brand.subtext)
            .tracking(0.6)
    }
}

/// Брендовый стиль текстового поля: тёмный фон `Brand.surface`,
/// обводка `Brand.border`, скруглённые углы 10pt.
private struct BrandTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .font(.system(size: 14))
            .foregroundColor(Brand.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Brand.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Brand.border, lineWidth: 1)
            )
    }
}

// MARK: - FlowLayout (wrapping horizontal layout)

/// Кастомный SwiftUI Layout для горизонтального размещения элементов
/// с автоматическим переносом на следующую строку при нехватке ширины.
///
/// Используется для рендеринга чипов пресетов адаптеров.
/// Каждый элемент размещается слева направо; если следующий элемент
/// не влезает в текущую строку — начинается новая строка с отступом `spacing`.
private struct FlowLayout: Layout {
    /// Расстояние между элементами по горизонтали и вертикали.
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return ArrangeResult(
            size: CGSize(width: maxWidth, height: y + rowHeight),
            positions: positions
        )
    }
}
