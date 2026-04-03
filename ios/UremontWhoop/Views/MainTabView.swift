/// Главный контейнер приложения: Splash → 3-page OBD pager.
/// Управляет всем состоянием (подключение, диагностика, мониторинг, история).
///
/// Файл содержит:
/// - ``ErrorsState`` — перечисление состояний экрана ошибок (idle / loading / result)
/// - ``AppRoot`` — точка входа: показывает SplashScreen, затем OBDScreen
/// - ``OBDScreen`` — основной экран с горизонтальным пейджером (3 страницы)
///   и sheet-презентациями (настройки, история, ручной выбор авто, Wi-Fi)
/// - ``CornerButton`` — маленькая кнопка-иконка в правом верхнем углу
///
/// Навигация между страницами реализована через TabView(.page) без стандартных точек;
/// вместо них используется кастомный компонент ``PageDots``.
import SwiftUI
import Combine
import QuickLook

// MARK: - ErrorsState

/// Состояние экрана диагностики ошибок.
///
/// - ``idle``: начальное — ошибки ещё не запрашивались
/// - ``loading``: идёт чтение DTC-кодов из ЭБУ
/// - ``result``: получены результаты (постоянные, ожидающие, permanent 0A, freeze frame, доп. блоки)
enum ErrorsState {
    case idle
    case loading
    case result(
        main: DtcResult,
        pending: DtcResult,
        permanent: DtcResult,
        freezeFrame: FreezeFrameData?,
        ecuResults: [EcuDtcResult]
    )
}

// MARK: - Page Indices

/// Индекс страницы «Подключение» в горизонтальном пейджере
private let PAGE_CONNECTION = 0
/// Индекс страницы «Ошибки» в горизонтальном пейджере
private let PAGE_ERRORS     = 1
/// Индекс страницы «Live-датчики» в горизонтальном пейджере
private let PAGE_DASHBOARD  = 2

// MARK: - AppRoot

/// Корневой View приложения.
///
/// Отвечает за переход от splash-экрана к основному интерфейсу OBDScreen.
/// Использует ZStack + .transition(.opacity) для плавного fade-перехода.
struct AppRoot: View {
    /// Менеджер OBD-подключения, прокинутый через EnvironmentObject из UremontWhoopApp
    @EnvironmentObject var obdManager: ObdConnectionManager

    /// Флаг отображения splash-экрана; после завершения анимации сбрасывается в false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashScreen {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
                .transition(.opacity)
            } else {
                OBDScreen(obdManager: obdManager)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: showSplash)
    }
}

// MARK: - OBDScreen

/// Основной экран приложения с горизонтальным пейджером из 3 страниц:
/// 1. ``ConnectionPage`` — подключение и профиль авто
/// 2. ``ErrorsPage`` — чтение/сброс DTC-кодов
/// 3. ``LiveDashboardPage`` — мониторинг датчиков в реальном времени
///
/// Также управляет sheet-презентациями: настройки, история диагностик,
/// ручной выбор марки/модели, подключение по Wi-Fi.
private struct OBDScreen: View {
    /// ViewModel приложения: хранит состояние подключения, ошибок, датчиков, настроек
    @StateObject private var vm: AppViewModel

    /// Показывать ли sheet настроек (SettingsSheet)
    @State private var showSettings = false
    /// Показывать ли sheet истории диагностик (HistorySheet)
    @State private var showHistory = false
    /// Показывать ли sheet ручного выбора марки/модели авто (ManualCarPickerSheet)
    @State private var showManualPicker = false
    /// Показывать ли sheet ввода Wi-Fi хоста/порта (WifiSheet)
    @State private var showWifiSheet = false
    /// Показывать ли алерт после генерации PDF-отчёта
    @State private var showPdfAlert = false
    /// URL сгенерированного PDF для QuickLook-превью
    @State private var pdfPreviewURL: URL?
    /// Текущая страница горизонтального пейджера (0/1/2)
    @State private var currentPage = 0

    init(obdManager: ObdConnectionManager) {
        _vm = StateObject(wrappedValue: AppViewModel(obdManager: obdManager))
    }

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()

            /// Горизонтальный пейджер — TabView в стиле .page без встроенных точек
            TabView(selection: $currentPage) {
                ConnectionPage(
                    connectionStatus: vm.connectionStatus,
                    isConnected: vm.isConnected,
                    isConnecting: vm.isConnecting,
                    carProfile: $vm.carProfile,
                    vehicleInfo: vm.vehicleInfo,
                    readinessMonitors: vm.readinessMonitors,
                    onProfileAuto: { vm.carProfile = .auto },
                    onProfileManual: { showManualPicker = true },
                    onSelectAdapter: {
                        if vm.isConnected { vm.toggleConnection() }
                        else { showWifiSheet = true }
                    },
                    onNavigateDiagnostics: { withAnimation { currentPage = PAGE_ERRORS } }
                )
                .tag(PAGE_CONNECTION)

                ErrorsPage(
                    isConnected: vm.isConnected,
                    errorsState: vm.errorsState,
                    loadingMessage: vm.errorsLoadingMessage,
                    carProfile: vm.carProfile,
                    vehicleInfo: vm.vehicleInfo,
                    onRead: { Task { await vm.readErrors() } },
                    onClear: { Task { await vm.clearErrors() } },
                    onDtcClick: { url in
                        if let u = URL(string: url) { UIApplication.shared.open(u) }
                    },
                    onExportPdf: {
                        vm.pdfFileURL = vm.exportPdf()
                        if vm.pdfFileURL != nil { showPdfAlert = true }
                    }
                )
                .tag(PAGE_ERRORS)

                LiveDashboardPage(
                    isConnected: vm.isConnected,
                    isMonitoring: vm.isMonitoring,
                    sensorReadings: vm.sensorReadings,
                    onToggle: { vm.isMonitoring.toggle() },
                    onClearReadings: { vm.sensorReadings = [:] }
                )
                .tag(PAGE_DASHBOARD)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            /// Кастомный индикатор страниц (три точки внизу экрана)
            VStack {
                Spacer()
                PageDots(currentPage: currentPage)
                    .padding(.bottom, 10)
            }

            /// Кнопки «История» и «Настройки» в правом верхнем углу
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        CornerButton(emoji: "📋", accessLabel: "История диагностик") { showHistory = true }
                        CornerButton(emoji: "⚙", accessLabel: "Настройки") { showSettings = true }
                    }
                    .padding(.trailing, 16)
                }
                .padding(.top, 10)
                Spacer()
            }
        }
        .task { await vm.loadInitialState() }
        .onChange(of: vm.isConnected) { connected in
            if !connected { vm.onDisconnect() }
        }
        /// Перезапуск polling-задачи при изменении pollingToken (начало/остановка мониторинга)
        .task(id: vm.pollingToken) { await vm.pollSensors() }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                ScrollView {
                    SettingsSheet(settings: $vm.settings)
                }
                .background(Brand.surface)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                HistorySheet(
                    sessions: vm.sessions,
                    onClear: {
                        SessionRepository.shared.clear()
                        vm.sessions = []
                    }
                )
                .background(Brand.surface)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showManualPicker) {
            NavigationStack {
                ManualCarPickerSheet(current: vm.carProfile) { profile in
                    vm.carProfile = profile
                    showManualPicker = false
                }
                .background(Brand.surface)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showWifiSheet) {
            ScrollView {
                WifiSheet(
                    initialHost: vm.savedWifiHost,
                    initialPort: vm.savedWifiPort,
                    onConnect: { host, port in
                        showWifiSheet = false
                        vm.savedWifiHost = host
                        vm.savedWifiPort = port
                        Task { await vm.connectWifi(host: host, port: port) }
                    }
                )
            }
            .background(Brand.surface)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .alert("Отчёт готов", isPresented: $showPdfAlert) {
            Button("Открыть") {
                pdfPreviewURL = vm.pdfFileURL
                vm.pdfFileURL = nil
            }
            Button("Поделиться") {
                if let url = vm.pdfFileURL { shareFile(url) }
                vm.pdfFileURL = nil
            }
            Button("Отмена", role: .cancel) { vm.pdfFileURL = nil }
        } message: {
            Text("Открыть PDF в приложении для просмотра или отправить файл (мессенджер, почта…)?")
        }
        .quickLookPreview($pdfPreviewURL)
    }

    /// Открывает системный share-sheet для PDF-файла
    private func shareFile(_ url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        PdfReportGenerator.shared.share(from: root, file: url)
    }
}

// MARK: - CornerButton

/// Маленькая круглая кнопка с эмодзи для правого верхнего угла экрана.
///
/// Используется для быстрого доступа к истории диагностик и настройкам.
/// Стилизована под карточку (Brand.card + Brand.border).
private struct CornerButton: View {
    /// Эмодзи, отображаемый внутри кнопки
    let emoji: String
    /// Текст для VoiceOver (accessibility)
    var accessLabel: String = ""
    /// Действие при нажатии
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 16))
                .frame(width: 36, height: 36)
                .background(Brand.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Brand.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessLabel)
    }
}
