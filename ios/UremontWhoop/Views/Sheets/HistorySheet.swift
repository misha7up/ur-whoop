/// История диагностик: список SessionCard с датой, VIN, DTC-кодами.
///
/// Файл содержит модальный sheet истории проведённых диагностик.
/// Каждая сессия представлена карточкой `SessionCard` с информацией:
/// - Дата проведения
/// - Название автомобиля и последние 8 символов VIN
/// - Бейджи: количество найденных ошибок, наличие Freeze Frame
/// - Ряд DTC-кодов (до 6 видимых, остальные как «+N»)
///
/// Компоненты:
/// - `HistorySheet` — основной лист со списком сессий и кнопкой «Очистить»
/// - `SessionCard` — карточка одной сессии диагностики
/// - `FreezeFrameBadge` — бейдж «📷 Снимок» (наличие Freeze Frame данных)
/// - `ErrorCountBadge` — бейдж с количеством ошибок или «✓ Чисто»
/// - `DtcCodesRow` — горизонтальный ряд DTC-кодов с цветовой маркировкой
import SwiftUI

// MARK: - HistorySheet

/// Модальный лист со списком всех проведённых диагностических сессий.
///
/// Если сессий нет — показывается заглушка с текстом «Историй пока нет».
/// Если есть — прокручиваемый список `SessionCard` с кнопкой «Очистить»
/// в правом верхнем углу. Очистка вызывает `onClear` и удаляет все записи
/// из `SessionManager`.
struct HistorySheet: View {
    /// Массив записей диагностических сессий (из `SessionManager`).
    let sessions: [SessionRecord]
    /// Замыкание для очистки всей истории (вызывает `SessionManager.clearAll()`).
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)

            // Header
            HStack {
                Text("История диагностики")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Brand.text)

                Spacer()

                if !sessions.isEmpty {
                    Button(action: onClear) {
                        Text("Очистить")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Brand.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Brand.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Brand.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            if sessions.isEmpty {
                // Empty state
                Spacer()
                VStack(spacing: 8) {
                    Text("📋")
                        .font(.system(size: 40))
                    Text("Историй пока нет")
                        .font(.system(size: 15))
                        .foregroundColor(Brand.subtext)
                    Text("Записи появятся после сканирования")
                        .font(.system(size: 12))
                        .foregroundColor(Brand.border)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(sessions) { session in
                            SessionCard(session: session)
                        }
                        Spacer().frame(height: 24)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

// MARK: - SessionCard

/// Карточка одной диагностической сессии в списке истории.
///
/// Содержит:
/// - Дату сессии (форматируется через `SessionRecord.formattedDate`)
/// - Бейджи: `FreezeFrameBadge` (если есть снимки) и `ErrorCountBadge` (кол-во ошибок)
/// - Название авто + последние 8 символов VIN
/// - Горизонтальный ряд найденных DTC-кодов (main + pending + otherEcu)
private struct SessionCard: View {
    /// Запись сессии с данными: дата, авто, VIN, DTC-коды, Freeze Frame.
    let session: SessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Date + badges row
            HStack {
                Text(session.formattedDate)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Brand.text)

                Spacer()

                HStack(spacing: 6) {
                    if session.hasFreezeFrame {
                        FreezeFrameBadge()
                    }
                    ErrorCountBadge(count: session.totalErrors)
                }
            }

            // Vehicle + VIN
            let vinSuffix = session.vin.map { " · \(String($0.suffix(8)))" } ?? ""
            Text(session.vehicleName + vinSuffix)
                .font(.system(size: 12))
                .foregroundColor(Brand.subtext)

            /// Объединение всех DTC-кодов (main + pending + otherEcu) для отображения в ряду.
            let allCodes = session.mainDtcs + session.pendingDtcs +
                session.otherEcuErrors.values.flatMap { $0 }

            if !allCodes.isEmpty {
                DtcCodesRow(
                    allCodes: allCodes,
                    pendingDtcs: Set(session.pendingDtcs)
                )
            }
        }
        .padding(14)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Brand.border, lineWidth: 1)
        )
    }
}

// MARK: - Freeze Frame Badge

/// Бейдж «📷 Снимок», отображаемый на карточке сессии при наличии Freeze Frame данных.
///
/// Freeze Frame (Mode 02) — это снимок показателей датчиков, зафиксированный ECU
/// в момент возникновения ошибки. Зелёный цвет сигнализирует о наличии доп. данных.
private struct FreezeFrameBadge: View {
    var body: some View {
        Text("📷 Снимок")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Brand.green)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(red: 28/255, green: 42/255, blue: 30/255))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Brand.green.opacity(0.4), lineWidth: 1)
            )
    }
}

// MARK: - Error Count Badge

/// Бейдж с количеством найденных ошибок или индикатором «✓ Чисто».
///
/// - Если `count > 0` — оранжевый бейдж «⚠ N ошибок»
/// - Если `count == 0` — зелёный бейдж «✓ Чисто»
private struct ErrorCountBadge: View {
    /// Общее количество найденных DTC-ошибок в данной сессии.
    let count: Int

    private var hasErrors: Bool { count > 0 }
    private var badgeColor: Color { hasErrors ? Brand.orange : Brand.green }

    var body: some View {
        Text(hasErrors ? "⚠ \(count) ошибок" : "✓ Чисто")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(badgeColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(badgeColor.opacity(0.4), lineWidth: 1)
            )
    }
}

// MARK: - DTC Codes Row

/// Горизонтальный ряд DTC-кодов на карточке сессии.
///
/// Показывает до 6 кодов в виде цветных бейджей:
/// - Синий — подтверждённая ошибка (main DTC)
/// - Оранжевый — ожидающая ошибка (pending DTC)
///
/// Если кодов больше 6, показывается текст «+N» для оставшихся.
private struct DtcCodesRow: View {
    /// Все DTC-коды сессии (main + pending + otherEcu).
    let allCodes: [String]
    /// Множество pending-кодов для цветовой маркировки.
    let pendingDtcs: Set<String>

    var body: some View {
        HStack(spacing: 5) {
            let visible = Array(allCodes.prefix(6))
            let rest = allCodes.count - visible.count

            ForEach(visible, id: \.self) { code in
                let isPending = pendingDtcs.contains(code)
                let color = isPending ? Brand.orange : Brand.blue

                Text(code)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(color.opacity(0.3), lineWidth: 1)
                    )
            }

            if rest > 0 {
                Text("+\(rest)")
                    .font(.system(size: 10))
                    .foregroundColor(Brand.subtext)
            }
        }
    }
}
