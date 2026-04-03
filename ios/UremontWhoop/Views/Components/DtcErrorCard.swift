/// Карточка ошибки DTC: код, severity, причины, ремонт, кнопка «Узнать стоимость» + QR-код.
///
/// Файл содержит компоненты для отображения отдельной ошибки (DTC) из ECU автомобиля:
/// - `NetworkChecker` — синглтон мониторинга интернет-соединения через `NWPathMonitor`
/// - `DtcErrorCard` — основная карточка ошибки с кодом, описанием, причинами и ремонтом
/// - `QrCodeDialog` — модальное окно с QR-кодом ссылки UREMONT (для оффлайн-режима)
/// - `QrCodeImage` — SwiftUI-обёртка генерации QR через `CIQRCodeGenerator`
///
/// Логика кнопки «Узнать стоимость ремонта»:
/// - Онлайн → открывает URL в браузере через `onOpenUrl`
/// - Оффлайн → показывает QR-код той же ссылки, чтобы пользователь
///   мог отсканировать его другим устройством с интернетом
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Network

// MARK: - NetworkChecker

/// Синглтон для мониторинга состояния сетевого подключения устройства.
///
/// Использует `NWPathMonitor` (фреймворк Network) для отслеживания изменений
/// сетевого пути в реальном времени. Публикует `isConnected` для SwiftUI-привязки.
///
/// Применяется в `DtcErrorCard` для переключения поведения кнопки
/// «Узнать стоимость ремонта»: если интернет недоступен (Wi-Fi занят OBD-адаптером),
/// вместо открытия URL показывается QR-код.
final class NetworkChecker: ObservableObject {
    /// Единственный экземпляр, доступный для всех View.
    static let shared = NetworkChecker()

    /// `true`, если устройство имеет доступ к интернету.
    /// Обновляется на main-потоке при каждом изменении сетевого пути.
    @Published private(set) var isConnected = true

    /// Монитор сетевого пути (системный NWPathMonitor).
    private let monitor = NWPathMonitor()
    /// Выделенная очередь для обработки обновлений монитора.
    private let queue = DispatchQueue(label: "com.uremont.whoop.netmon")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}

// MARK: - DtcErrorCard

/// Карточка отображения одной ошибки DTC (Diagnostic Trouble Code).
///
/// Содержит:
/// - Код ошибки (например, P0301) крупным моноширинным шрифтом
/// - Бейдж «ОЖИДАЮЩИЙ» для pending-ошибок
/// - Индикатор серьёзности: «КРИТИЧНО» (severity=3, красный),
///   «ВНИМАНИЕ» (severity=2, оранжевый), «ИНФО» (severity=1, жёлтый)
/// - Описание ошибки (title), возможные причины (causes), рекомендации по ремонту (repair)
/// - Кнопка «Узнать стоимость ремонта» — открывает UREMONT URL или QR-код
///
/// Обводка карточки окрашивается в цвет серьёзности для визуального приоритета.
struct DtcErrorCard: View {
    /// OBD2 DTC-код ошибки (например, «P0300», «C1234», «U0100»).
    let code: String
    /// Структура с описанием ошибки: title, causes, repair, severity.
    let info: DtcInfo
    /// URL страницы UREMONT для оценки стоимости ремонта данной ошибки.
    let url: String
    /// Замыкание для открытия URL (вызывается при наличии интернета).
    let onOpenUrl: (String) -> Void
    /// `true`, если ошибка является «ожидающей» (pending DTC), а не подтверждённой.
    var isPending: Bool = false

    /// Наблюдение за состоянием сети для переключения кнопки (URL vs QR-код).
    @ObservedObject private var networkChecker = NetworkChecker.shared
    /// Флаг отображения модального диалога с QR-кодом (показывается при отсутствии сети).
    @State private var showQrDialog = false

    /// Цвет индикатора серьёзности: красный (3), оранжевый (2), жёлтый (1/default).
    private var sevColor: Color {
        switch info.severity {
        case 3:  return Brand.red
        case 2:  return Brand.orange
        default: return Brand.yellow
        }
    }

    /// Текстовая метка серьёзности для бейджа.
    private var sevLabel: String {
        switch info.severity {
        case 3:  return "КРИТИЧНО"
        case 2:  return "ВНИМАНИЕ"
        default: return "ИНФО"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Code + badges row
            HStack {
                HStack(spacing: 8) {
                    Text(code)
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(Brand.yellow)

                    if isPending {
                        Text("ОЖИДАЮЩИЙ")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(Brand.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Brand.yellow.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Brand.yellow.opacity(0.35), lineWidth: 1)
                            )
                    }
                }

                Spacer()

                Text(sevLabel)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(sevColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(sevColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(sevColor.opacity(0.4), lineWidth: 1)
                    )
            }

            // Title
            Text(info.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Brand.text)
                .lineSpacing(3)

            // Causes
            if !info.causes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Причины:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Brand.subtext)
                    Text(info.causes)
                        .font(.system(size: 12))
                        .foregroundColor(Brand.subtext)
                        .lineSpacing(3)
                }
            }

            // Repair
            if !info.repair.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Действие:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Brand.blue)
                    Text(info.repair)
                        .font(.system(size: 12))
                        .foregroundColor(Brand.text)
                        .lineSpacing(3)
                }
            }

            /// Кнопка «Узнать стоимость ремонта» — переключается между открытием URL
            /// и показом QR-кода в зависимости от наличия интернета.
            Button(action: {
                if networkChecker.isConnected {
                    onOpenUrl(url)
                } else {
                    showQrDialog = true
                }
            }) {
                HStack(spacing: 8) {
                    Text(networkChecker.isConnected ? "🔍" : "📵")
                        .font(.system(size: 14))
                    Text(networkChecker.isConnected
                         ? "Узнать стоимость ремонта"
                         : "Узнать стоимость (QR-код)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Brand.blue)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Brand.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Brand.blue.opacity(0.35), lineWidth: 1)
                )
            }
        }
        .padding(18)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(sevColor.opacity(0.25), lineWidth: 1)
        )
        .sheet(isPresented: $showQrDialog) {
            QrCodeDialog(url: url) { showQrDialog = false }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ошибка \(code): \(info.title). Серьёзность: \(sevLabel)")
    }
}

// MARK: - QrCodeDialog

/// Модальный диалог с QR-кодом ссылки на UREMONT.
///
/// Показывается, когда пользователь нажимает «Узнать стоимость» при отсутствии
/// интернета (Wi-Fi обычно занят подключением к OBD-адаптеру).
/// Пользователь может отсканировать QR-код другим устройством с мобильным интернетом.
///
/// Фон — полупрозрачный чёрный, закрывается тапом по фону или кнопкой «Закрыть».
struct QrCodeDialog: View {
    /// URL, который будет закодирован в QR.
    let url: String
    /// Замыкание для закрытия диалога.
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 14) {
                Text("Нет интернета? Не проблема!")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Brand.text)
                    .multilineTextAlignment(.center)

                Text("Отсканируйте QR-код, чтобы узнать справедливую стоимость ремонта через UREMONT")
                    .font(.system(size: 13))
                    .foregroundColor(Brand.subtext)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                QrCodeImage(content: url, sizePt: 220)

                Button(action: onDismiss) {
                    Text("Закрыть")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Brand.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Brand.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Brand.border, lineWidth: 1)
                        )
                }
            }
            .padding(28)
            .background(Brand.card)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Brand.border, lineWidth: 1)
            )
            .padding(.horizontal, 48)
        }
        .clearPresentationBg()
    }
}

// MARK: - QR Code Image (CoreImage CIQRCodeGenerator)

/// SwiftUI-обёртка для генерации и отображения QR-кода через CoreImage.
///
/// Использует `CIQRCodeGenerator` с уровнем коррекции «M» (15%).
/// Генерирует `UIImage` с масштабированием под заданный размер в points,
/// учитывая `UIScreen.main.scale` для Retina-резкости.
/// Если генерация не удалась — показывает плейсхолдер «QR-код недоступен».
struct QrCodeImage: View {
    /// Строка для кодирования в QR (обычно URL).
    let content: String
    /// Размер QR-изображения в points (ширина = высота).
    let sizePt: CGFloat

    var body: some View {
        if let uiImage = generateQRCode(from: content) {
            Image(uiImage: uiImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: sizePt, height: sizePt)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Brand.surface)
                .frame(width: sizePt, height: sizePt)
                .overlay(
                    Text("QR-код недоступен")
                        .font(.system(size: 12))
                        .foregroundColor(Brand.subtext)
                )
        }
    }

    /// Общий `CIContext` — переиспользуется для экономии памяти при генерации нескольких QR.
    private static let ciContext = CIContext()

    /// Генерирует `UIImage` QR-кода из строки с учётом Retina-масштаба.
    private func generateQRCode(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scaleX = (sizePt * UIScreen.main.scale) / outputImage.extent.size.width
        let scaleY = (sizePt * UIScreen.main.scale) / outputImage.extent.size.height
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let cgImage = Self.ciContext.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - iOS 16.4+ presentationBackground compatibility

/// Обёртка совместимости для `presentationBackground(.clear)`,
/// доступного только с iOS 16.4+. На более ранних версиях — no-op.
private extension View {
    @ViewBuilder
    func clearPresentationBg() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(.clear)
        } else {
            self
        }
    }
}
