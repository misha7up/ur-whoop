/// Анимированный splash-экран приложения UREMONT WHOOP.
///
/// Показывается при запуске, содержит:
/// - Логотип UREMONT с эффектом масштабирования (scale 0.6 → 1.0)
/// - Название приложения и подзаголовок «OBD2 Диагностика»
/// - Линейный прогресс-бар, заполняющийся за ~2.4 сек (40 шагов × 60 мс)
/// - Фоновый радиальный градиент для визуального акцента
///
/// После завершения анимации (+ 300 мс задержки) вызывает ``onFinished``,
/// что запускает fade-переход к ``OBDScreen`` в ``AppRoot``.
import SwiftUI

/// Splash-экран с анимацией логотипа и прогресс-баром.
///
/// Полная длительность: ~2.7 сек (2.4 сек прогресс + 0.3 сек задержка перед переходом).
/// По завершении вызывает замыкание ``onFinished`` для перехода к основному экрану.
struct SplashScreen: View {
    /// Замыкание, вызываемое после завершения анимации — переключает на OBDScreen
    let onFinished: () -> Void

    /// Масштаб логотипа и текста: анимируется 0.6 → 1.0 при появлении
    @State private var scale: CGFloat = 0.6
    /// Прозрачность контента: анимируется 0 → 1 при появлении
    @State private var opacity: Double = 0
    /// Прогресс заполнения бара (0.0 → 1.0)
    @State private var progress: Double = 0

    /// Общее количество шагов прогресс-бара
    private let totalSteps = 40
    /// Задержка между шагами прогресса (60 мс → 40 шагов = 2.4 сек)
    private let stepDelay: TimeInterval = 0.06

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()

            /// Фоновый радиальный градиент Brand.blue → прозрачный для визуального акцента
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Brand.blue.opacity(0.15), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 160
                    )
                )
                .frame(width: 320, height: 320)

            VStack(spacing: 0) {
                LogoPlaceholder()
                    .frame(width: 72, height: 72)

                Spacer().frame(height: 20)

                Text("UREMONT WHOOP")
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(Brand.text)
                    .tracking(2)

                Spacer().frame(height: 6)

                Text("OBD2 Диагностика")
                    .font(.system(size: 14))
                    .foregroundColor(Brand.subtext)

                Spacer().frame(height: 48)

                ProgressView(value: progress, total: 1)
                    .progressViewStyle(LinearProgressViewStyle(tint: Brand.blue))
                    .frame(width: 200, height: 2)
                    .clipShape(Capsule())
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .task {
            withAnimation(.easeOut(duration: 0.7)) { scale = 1.0 }
            withAnimation(.easeOut(duration: 0.6)) { opacity = 1.0 }

            for i in 1...totalSteps {
                try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
                withAnimation(.linear(duration: stepDelay)) {
                    progress = Double(i) / Double(totalSteps)
                }
            }

            try? await Task.sleep(nanoseconds: 300_000_000)
            onFinished()
        }
    }
}

// MARK: - Logo Placeholder

/// Заглушка логотипа UREMONT: синий скруглённый квадрат с изображением из Assets.
///
/// Загружает «UremontLogo» из Asset Catalog; если изображение отсутствует,
/// отображается пустой синий квадрат.
private struct LogoPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Brand.blue)
            .overlay(
                Image("UremontLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white)
                    .padding(14)
            )
    }
}
