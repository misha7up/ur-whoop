/// Ручной выбор автомобиля: марка из ALL_MAKES, модель, год.
///
/// Файл содержит модальный sheet для ручного выбора профиля автомобиля.
/// Используется, когда пользователь выбирает режим «Ручной» вместо «Авто» (VIN).
///
/// Трёхшаговый flow:
/// 1. **Выбор марки** (`MakeSelectionView`) — прокручиваемый список из 34 марок
///    (`ALL_MAKES`) с поисковым полем. Нажатие на марку переходит к шагу 2.
/// 2. **Ввод модели и года** (`ModelYearView`) — текстовые поля (необязательные)
///    с возможностью вернуться к выбору марки кнопкой «Изменить».
/// 3. **Применение** — кнопка «Применить профиль» вызывает `onApply(.manual(...))`
///    и закрывает sheet.
///
/// Компоненты:
/// - `ManualCarPickerSheet` — корневой View с логикой переключения шагов
/// - `MakeSelectionView` — список марок с поиском
/// - `ModelYearView` — ввод модели, года и кнопка «Применить профиль»
import SwiftUI

// MARK: - ManualCarPickerSheet

/// Модальный лист ручного выбора автомобиля.
///
/// Логика навигации: если `selectedMake` пустой — показывается `MakeSelectionView`
/// (шаг 1), иначе — `ModelYearView` (шаг 2). Кнопка «Изменить» сбрасывает
/// `selectedMake` и возвращает на шаг 1.
///
/// Если лист открывается с уже существующим профилем `.manual(make, model, year)`,
/// поля предзаполняются текущими значениями.
struct ManualCarPickerSheet: View {
    /// Текущий профиль автомобиля (может быть `nil` или `.manual`).
    /// Используется для предзаполнения полей при повторном открытии.
    let current: CarProfile?
    /// Замыкание, вызываемое при нажатии «Применить профиль» с новым `CarProfile.manual`.
    let onApply: (CarProfile) -> Void

    /// Выбранная марка автомобиля. Пустая строка означает шаг 1 (выбор марки).
    @State private var selectedMake: String
    /// Введённое название модели (необязательное поле).
    @State private var model: String
    /// Введённый год выпуска (необязательное поле, только цифры, макс. 4 символа).
    @State private var year: String
    /// Текст поискового запроса для фильтрации списка марок.
    @State private var search = ""

    init(current: CarProfile?, onApply: @escaping (CarProfile) -> Void) {
        self.current = current
        self.onApply = onApply
        if case let .manual(make, m, y) = current {
            _selectedMake = State(initialValue: make)
            _model = State(initialValue: m)
            _year = State(initialValue: y)
        } else {
            _selectedMake = State(initialValue: "")
            _model = State(initialValue: "")
            _year = State(initialValue: "")
        }
    }

    /// Отфильтрованный список марок по поисковому запросу.
    /// При пустом запросе возвращает полный `ALL_MAKES`.
    private var filteredMakes: [String] {
        if search.trimmingCharacters(in: .whitespaces).isEmpty {
            return ALL_MAKES
        }
        return ALL_MAKES.filter {
            $0.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Выбор автомобиля")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Brand.text)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if selectedMake.isEmpty {
                MakeSelectionView(
                    search: $search,
                    filteredMakes: filteredMakes,
                    onSelect: { selectedMake = $0 }
                )
            } else {
                ModelYearView(
                    selectedMake: selectedMake,
                    model: $model,
                    year: $year,
                    onChangeMake: {
                        selectedMake = ""
                        search = ""
                    },
                    onApply: {
                        onApply(.manual(make: selectedMake, model: model, year: year))
                    }
                )
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Make Selection

/// Шаг 1: выбор марки автомобиля из списка `ALL_MAKES`.
///
/// Содержит поисковое поле сверху и прокручиваемый `LazyVStack` с кнопками марок.
/// Фильтрация выполняется case-insensitive через `localizedCaseInsensitiveContains`.
/// При нажатии на марку вызывается `onSelect`, что переключает на шаг 2.
private struct MakeSelectionView: View {
    /// Привязка к поисковому запросу (текст из TextField фильтрует список марок).
    @Binding var search: String
    /// Отфильтрованный массив марок для отображения.
    let filteredMakes: [String]
    /// Замыкание, вызываемое при выборе марки с её названием.
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            TextField("Поиск марки…", text: $search)
                .font(.system(size: 14))
                .foregroundColor(Brand.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Brand.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Brand.border, lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .tint(Brand.blue)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredMakes, id: \.self) { make in
                        Button {
                            onSelect(make)
                        } label: {
                            Text(make)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Brand.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .background(Brand.card)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Brand.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Model & Year Entry

/// Шаг 2: ввод модели и года выпуска после выбора марки.
///
/// Показывает:
/// - Выбранную марку в виде синего чипа с кнопкой «Изменить» (возврат на шаг 1)
/// - Поле ввода модели (необязательное, текстовое)
/// - Поле ввода года выпуска (необязательное, цифровая клавиатура, макс. 4 цифры)
/// - Кнопку «✓ Применить профиль» для подтверждения выбора
///
/// Валидация года: `onChange(of: year)` фильтрует нецифровые символы
/// и ограничивает длину до 4 знаков.
private struct ModelYearView: View {
    /// Название выбранной марки (отображается в синем чипе).
    let selectedMake: String
    /// Привязка к полю ввода модели.
    @Binding var model: String
    /// Привязка к полю ввода года выпуска.
    @Binding var year: String
    /// Замыкание для возврата к выбору марки (шаг 1).
    let onChangeMake: () -> Void
    /// Замыкание для применения профиля.
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Selected make chip + change button
            HStack(spacing: 10) {
                Text(selectedMake)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Brand.blue)
                    .clipShape(Capsule())

                Button(action: onChangeMake) {
                    Text("Изменить")
                        .font(.system(size: 12))
                        .foregroundColor(Brand.subtext)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Brand.card)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Brand.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            // Model field
            VStack(alignment: .leading, spacing: 4) {
                Text("Модель (необязательно)")
                    .font(.system(size: 12))
                    .foregroundColor(Brand.subtext)
                TextField("например: 3 Series, Camry, Creta…", text: $model)
                    .font(.system(size: 14))
                    .foregroundColor(Brand.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Brand.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Brand.border, lineWidth: 1)
                    )
                    .tint(Brand.blue)
            }

            // Year field
            VStack(alignment: .leading, spacing: 4) {
                Text("Год выпуска (необязательно)")
                    .font(.system(size: 12))
                    .foregroundColor(Brand.subtext)
                TextField("например: 2019", text: $year)
                    .font(.system(size: 14))
                    .foregroundColor(Brand.text)
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Brand.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Brand.border, lineWidth: 1)
                    )
                    .tint(Brand.blue)
                    .onChange(of: year) { newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(4))
                        if filtered != newValue { year = filtered }
                    }
            }

            Spacer().frame(height: 4)

            // Apply profile button
            Button(action: onApply) {
                HStack(spacing: 8) {
                    Text("✓")
                        .font(.system(size: 14, weight: .bold))
                    Text("Применить профиль")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Brand.blue)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Spacer().frame(height: 16)
        }
        .padding(.horizontal, 20)
    }
}
