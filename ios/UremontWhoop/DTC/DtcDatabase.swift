/// База описаний DTC-ошибок (универсальные + BMW/VAG/Mercedes), CarProfile, ALL_MAKES, URL-builder.
///
/// Этот файл объединяет всё, что связано с расшифровкой диагностических кодов (DTC):
/// - `DtcInfo` — структура с описанием одной ошибки (заголовок, причины, ремонт, серьёзность).
/// - `CarProfile` — sealed-тип профиля автомобиля (авто-определение по VIN или ручной выбор).
/// - `ALL_MAKES` — справочник из 34 марок автомобилей для ручного выбора.
/// - `DtcLookup` — namespace (enum без кейсов) с таблицами DTC и URL-билдером для UREMONT.
///
/// Аналог на Android: `object DtcLookup` в `MainActivity.kt` (Kotlin object = Swift enum без кейсов).
import Foundation

// MARK: - DtcInfo

/// Описание одного диагностического кода неисправности (DTC).
///
/// Используется в UI (карточка ошибки), PDF-отчёте и при формировании запроса к UREMONT AI.
///
/// - `title`: краткое название ошибки на русском (например, «Смесь бедная (Bank 1)»).
/// - `causes`: типичные причины возникновения — помогает пользователю понять проблему.
/// - `repair`: рекомендуемые действия по устранению.
/// - `severity`: уровень серьёзности (1 = низкий, 2 = средний, 3 = высокий).
///   Влияет на цвет индикатора в UI и порядок сортировки.
struct DtcInfo {
    let title: String
    var causes: String = ""
    var repair: String = ""
    var severity: Int = 2
}

// MARK: - CarProfile

/// Профиль автомобиля — определяет, как приложение идентифицирует машину.
///
/// Sealed-тип (аналог Kotlin `sealed class`):
/// - `.auto` — марка/модель/год определяются автоматически из VIN (Mode 09, PID 02).
/// - `.manual(make, model, year)` — пользователь выбирает вручную из `ALL_MAKES`.
///
/// Влияет на выбор OEM-базы DTC: для `.manual(make: "BMW", …)` будет использована
/// `bmwDtcInfo`, для VAG-марок — `vagDtcInfo` и т.д.
enum CarProfile: Equatable {
    /// Автоматическое определение по VIN из ЭБУ.
    case auto
    /// Ручной выбор марки, модели и года выпуска.
    case manual(make: String, model: String = "", year: String = "")

    /// Человекочитаемое имя профиля для отображения в UI.
    /// Для `.auto` возвращает «Авто», для `.manual` — конкатенацию непустых полей.
    var displayName: String {
        switch self {
        case .auto:
            return "Авто"
        case let .manual(make, model, year):
            return [make, model, year]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    /// Удобная проверка: профиль в режиме авто-определения.
    var isAuto: Bool {
        if case .auto = self { return true }
        return false
    }
}

// MARK: - Car Database

/// Справочник марок автомобилей для ручного выбора в UI (Picker).
///
/// Содержит 34 популярные марки, включая российские (LADA, ГАЗ, УАЗ).
/// Последний элемент «Другое / Иное» — для марок, отсутствующих в списке.
/// Список отсортирован по латинскому алфавиту.
let ALL_MAKES: [String] = [
    "Audi", "BMW", "Chevrolet", "Citroën", "Dacia", "Fiat", "Ford",
    "GAZ (ГАЗ)", "Honda", "Hyundai", "Infiniti", "Jaguar", "Jeep",
    "Kia", "LADA (ВАЗ)", "Land Rover", "Lexus", "Mazda", "Mercedes-Benz",
    "Mitsubishi", "Nissan", "Opel", "Peugeot", "Porsche", "Renault",
    "Seat", "Škoda", "Subaru", "Suzuki", "Toyota", "UAZ (УАЗ)",
    "Volkswagen", "Volvo", "Другое / Иное",
]

// MARK: - DTC Lookup Namespace

/// Пространство имён для всех операций с DTC-кодами.
///
/// Реализован как `enum` без кейсов (caseless enum) — аналог Kotlin `object`.
/// Экземпляры создать невозможно; все методы статические.
///
/// Содержит:
/// - Таблицы расшифровки DTC: OEM-специфичные (BMW, VAG, Mercedes) и универсальную (SAE J2012).
/// - Словарь `problemDescriptions` — человекочитаемые описания для AI-агента UREMONT.
/// - `buildUremontUrl` — формирование URL для перехода на сайт UREMONT.
enum DtcLookup {

/// Код DTC без суффикса FTB из UDS (`P0420-17` → `P0420`).
private static func baseDtcCode(_ code: String) -> String {
    if let i = code.firstIndex(of: "-") {
        return String(code[..<i]).uppercased()
    }
    return code.uppercased()
}

/// Возвращает `DtcInfo` для указанного кода.
///
/// Приоритет описаний:
///   1. Manufacturer-specific (BMW, VAG, Mercedes) — если в профиле выбрана марка.
///   2. Toyota / Lexus — марка из ручного профиля или `detectedMake` из VIN (в т.ч. JDM `JT*`…).
///   3. Универсальная таблица `universalDtcInfo` — SAE J2012 стандарт.
///
/// Суффикс `-XX` после UDS 0x19 (Failure Type Byte) отбрасывается при поиске в таблицах.
///
/// - Parameter detectedMake: подпись из WMI (`Toyota car` …) — `VehicleInfo.detectedMake`.
static func dtcInfo(code: String, profile: CarProfile, detectedMake: String? = nil) -> DtcInfo {
    let base = baseDtcCode(code)
    if case let .manual(make, _, _) = profile {
        let m = make.lowercased()
        let specific: DtcInfo?
        if m.contains("bmw") {
            specific = bmwDtcInfo(code: base)
        } else if m.contains("volkswagen") || m.contains("vw") || m.contains("audi") || m.contains("skoda") || m.contains("seat") {
            specific = vagDtcInfo(code: base)
        } else if m.contains("mercedes") {
            specific = mercedesDtcInfo(code: base)
        } else {
            specific = nil
        }
        if let s = specific { return s }
    }
    if isToyotaLexusContext(profile: profile, detectedMake: detectedMake) {
        if let t = toyotaLexusDtcInfo(code: base) { return t }
    }
    return universalDtcInfo(code: base)
}

private static func isToyotaLexusByMake(_ text: String?) -> Bool {
    guard let s = text?.lowercased() else { return false }
    return s.contains("toyota") || s.contains("lexus") || s.contains("тойота") || s.contains("лексус")
}

private static func isToyotaLexusContext(profile: CarProfile, detectedMake: String?) -> Bool {
    if case let .manual(make, _, _) = profile {
        let m = make.lowercased()
        if m.contains("toyota") || m.contains("lexus") || m.contains("тойота") || m.contains("лексус") { return true }
    }
    return isToyotaLexusByMake(detectedMake)
}

/// Коды с трактовкой по сервис-мануалам Toyota/Lexus (JDM / VVT-i / A/F банк 2).
private static func toyotaLexusDtcInfo(code: String) -> DtcInfo? {
    switch code {
    case "P1150":
        return DtcInfo(title: "Датчик A/F банк 2 сенсор 1 — диапазон/характеристика (Toyota)", causes: "Износ или загрязнение датчика A/F, подсос воздуха, форсунки", repair: "Проверка утечек впуска, тест датчика A/F (B2S1), при необходимости замена", severity: 2)
    case "P1153":
        return DtcInfo(title: "Датчик A/F банк 2 сенсор 1 — медленный отклик (Toyota)", causes: "Стареющий датчик A/F, отложения на чувствительном элементе", repair: "Замена датчика A/F банк 2 до катализатора", severity: 2)
    case "P1155":
        return DtcInfo(title: "Датчик A/F банк 2 сенсор 1 — цепь нагревателя (Toyota)", causes: "Обрыв или КЗ нагревателя A/F, предохранитель", repair: "Проверка проводки и предохранителей, замена датчика A/F B2S1", severity: 2)
    case "P1349":
        return DtcInfo(title: "Система VVT-i — неисправность (Toyota)", causes: "Заклинивание клапана OCV, грязное/низкое масло, износ шестерни VVT", repair: "Проверка уровня масла, промывка/замена клапана VVT (OCV), при необходимости ремонт узла VVT", severity: 3)
    case "P1354":
        return DtcInfo(title: "Система VVT банк 2 — неисправность (Toyota)", causes: "Аналогично P1349 для второй банки (V6/V8)", repair: "Диагностика OCV и гидравлики VVT второй банки, качество масла", severity: 3)
    case "P1604":
        return DtcInfo(title: "Ошибка процедуры запуска (Toyota)", causes: "Слабый АКБ, износ стартера, плохой контакт массы, просадка питания ЭБУ при кренкинге", repair: "Проверить напряжение и клеммы АКБ, стартер и проводку; сброс кода после устранения причины", severity: 2)
    case "P1663":
        return DtcInfo(title: "Клапан управления маслом VVT (OCV) — неисправность цепи (Toyota)", causes: "Обрыв/КЗ проводки OCV, неисправный электромагнитный клапан", repair: "Проверка разъёма OCV, сопротивление клапана, замена OCV", severity: 3)
    default:
        return nil
    }
}

// MARK: - BMW-specific

/// Таблица DTC, специфичных для автомобилей BMW.
///
/// Возвращает `nil`, если код не найден в BMW-базе — тогда `dtcInfo` переходит
/// к универсальной таблице. Содержит ошибки, связанные с VANOS, цепью ГРМ,
/// катализаторами и MAF — наиболее частые для BMW.
///
/// - Parameter code: OBD-II код ошибки (например, "P0011").
/// - Returns: `DtcInfo` с BMW-специфичным описанием или `nil`.
static func bmwDtcInfo(code: String) -> DtcInfo? {
    switch code {
    case "P0011": return DtcInfo(title: "Перестановка фаз ГРМ — впускной распредвал (B1)", causes: "Грязное масло, неисправный VANOS, растянутая цепь ГРМ", repair: "Замена масла и фильтра, проверка/замена VANOS", severity: 3)
    case "P0012": return DtcInfo(title: "Опережение фаз ГРМ — впускной распредвал (B1)", causes: "Загрязнённый клапан VVT, неисправный VANOS", repair: "Промывка системы, замена клапана фаз ГРМ", severity: 3)
    case "P0171": return DtcInfo(title: "Смесь бедная (Bank 1)", causes: "Засорённый MAF, утечки впуска, загрязнённые форсунки", repair: "Чистка MAF, дымовой тест впуска", severity: 2)
    case "P0174": return DtcInfo(title: "Смесь бедная (Bank 2)", causes: "Утечки впуска со стороны B2, неисправный MAF", repair: "Дымовой тест, проверка давления топлива", severity: 2)
    case "P0300": return DtcInfo(title: "Случайный пропуск воспламенения", causes: "Изношенные катушки, свечи, форсунки, низкая компрессия", repair: "Диагностика катушек и свечей по каждому цилиндру", severity: 3)
    case "P0420": return DtcInfo(title: "КПД катализатора ниже порога (Bank 1)", causes: "Износ нейтрализатора, утечка выхлопа, O2-датчик", repair: "Замена каталитического нейтрализатора", severity: 2)
    case "P0430": return DtcInfo(title: "КПД катализатора ниже порога (Bank 2)", causes: "Аналогично P0420 для второй банки", repair: "Замена каталитического нейтрализатора (B2)", severity: 2)
    default: return nil
    }
}

// MARK: - VAG-specific (Volkswagen / Audi / Škoda / Seat)

/// Таблица DTC, специфичных для автомобилей группы VAG (VW, Audi, Škoda, Seat).
///
/// Учитывает особенности двигателей TSI (прямой впрыск, турбонаддув).
///
/// - Parameter code: OBD-II код ошибки.
/// - Returns: `DtcInfo` с VAG-специфичным описанием или `nil`.
static func vagDtcInfo(code: String) -> DtcInfo? {
    switch code {
    case "P0299": return DtcInfo(title: "Давление турбины ниже нормы", causes: "Неисправность актуатора турбины, утечки патрубков наддува", repair: "Проверка патрубков, замена актуатора WG", severity: 3)
    case "P0171": return DtcInfo(title: "Смесь бедная (Bank 1)", causes: "Засорённый MAF, утечки впуска, загрязнённые форсунки", repair: "Чистка MAF, проверка лямбда-зондов", severity: 2)
    case "P0300": return DtcInfo(title: "Случайный пропуск воспламенения", causes: "Катушки, свечи (часто у TSI), форсунки прямого впрыска", repair: "Замена катушек и свечей зажигания", severity: 3)
    case "P0420": return DtcInfo(title: "КПД катализатора ниже порога", causes: "Износ нейтрализатора, загрязнение маслом", repair: "Замена каталитического нейтрализатора", severity: 2)
    default: return nil
    }
}

// MARK: - Mercedes-specific

/// Таблица DTC, специфичных для автомобилей Mercedes-Benz.
///
/// - Parameter code: OBD-II код ошибки.
/// - Returns: `DtcInfo` с Mercedes-специфичным описанием или `nil`.
static func mercedesDtcInfo(code: String) -> DtcInfo? {
    switch code {
    case "P0016": return DtcInfo(title: "Рассогласование коленвала и распредвала (B1)", causes: "Растянутая цепь ГРМ, неисправный датчик", repair: "Замена цепи ГРМ и натяжителя", severity: 3)
    case "P0171": return DtcInfo(title: "Смесь бедная (Bank 1)", causes: "Засорённый MAF, неисправный лямбда-зонд, утечки", repair: "Чистка или замена MAF, диагностика утечек", severity: 2)
    case "P0420": return DtcInfo(title: "КПД катализатора ниже порога (Bank 1)", causes: "Износ нейтрализатора, проблемы с лямбда-зондами", repair: "Замена каталитического нейтрализатора", severity: 2)
    default: return nil
    }
}

// MARK: - Universal DTC Database

/// Универсальная таблица DTC по стандарту SAE J2012 / ISO 15031-6.
///
/// Покрывает ~150 наиболее распространённых кодов:
/// - P00xx–P02xx: смесеобразование, VVT, датчики, форсунки
/// - P03xx: зажигание, пропуски воспламенения, датчики коленвала/распредвала
/// - P04xx: EGR, EVAP, катализаторы
/// - P05xx–P07xx: скорость, холостой ход, ЭБУ, АКПП
/// - B-коды: кузов (SRS, BCM, иммобилайзер)
/// - C-коды: шасси (ABS, датчики колёс)
/// - U-коды: CAN-шина, связь между блоками
/// - P1xxx: популярные производитель-специфичные (Toyota, Honda, BMW)
///
/// Для неизвестных кодов возвращает generic `DtcInfo` с текстом «Код неисправности <code>».
///
/// - Parameter code: OBD-II код ошибки (5 символов, например "P0420").
/// - Returns: `DtcInfo` — всегда возвращает значение (не Optional).
static func universalDtcInfo(code: String) -> DtcInfo {
    switch code {

    // ── P00xx: Состав смеси / воздух / топливо ──────────────────────────────
    case "P0001": return DtcInfo(title: "Регулятор объёма топлива — цепь (обрыв)", causes: "Неисправность соленоида FVCV", repair: "Проверка проводки и замена регулятора топлива", severity: 2)
    case "P0002": return DtcInfo(title: "Регулятор объёма топлива — диапазон/характеристика", causes: "Засор в топливном тракте", repair: "Замена топливного фильтра и проверка насоса", severity: 2)
    case "P0010": return DtcInfo(title: "Цепь клапана VVT впускного распредвала (B1)", causes: "Обрыв в цепи клапана OCV, грязное масло", repair: "Замена масла, проверка клапана VVT", severity: 2)
    case "P0011": return DtcInfo(title: "Смещение фаз ГРМ — впускной (B1), опережение", causes: "Грязное масло, клапан OCV, цепь ГРМ", repair: "Замена масла, чистка/замена клапана VVT", severity: 3)
    case "P0012": return DtcInfo(title: "Смещение фаз ГРМ — впускной (B1), запаздывание", causes: "Загрязнённый клапан OCV", repair: "Чистка/замена клапана регулятора фаз ГРМ", severity: 2)
    case "P0013": return DtcInfo(title: "Цепь клапана VVT выпускного распредвала (B1)", causes: "Неисправность клапана или проводки OCV", repair: "Проверка и замена клапана VVT", severity: 2)
    case "P0014": return DtcInfo(title: "Смещение фаз — выпускной (B1), опережение", causes: "Масло, клапан OCV, цепь ГРМ", repair: "Замена масла, проверка VVT", severity: 2)
    case "P0016": return DtcInfo(title: "Рассогласование коленвала и распредвала (B1)", causes: "Растянутая цепь ГРМ, изношенный натяжитель", repair: "Замена цепи ГРМ и натяжителя", severity: 3)
    case "P0017": return DtcInfo(title: "Рассогласование коленвала и выпускного распредвала (B1)", causes: "Цепь ГРМ, натяжитель, клапан VVT", repair: "Диагностика ГРМ, замена цепи", severity: 3)
    case "P0020": return DtcInfo(title: "Цепь клапана VVT впускного распредвала (B2)", causes: "Неисправность OCV второй банки", repair: "Проверка клапана VVT B2", severity: 2)
    case "P0021": return DtcInfo(title: "Смещение фаз — впускной (B2), опережение", causes: "Грязное масло, клапан OCV B2", repair: "Замена масла, замена клапана VVT B2", severity: 3)
    case "P0022": return DtcInfo(title: "Смещение фаз — впускной (B2), запаздывание", causes: "Загрязнённый клапан OCV B2", repair: "Чистка/замена OCV B2", severity: 2)

    // ── P01xx: Топливная / воздушная система ────────────────────────────────
    case "P0100": return DtcInfo(title: "Цепь MAF-датчика — неисправность", causes: "Разрыв цепи, неисправный датчик MAF", repair: "Замена датчика массового расхода воздуха", severity: 2)
    case "P0101": return DtcInfo(title: "Сигнал MAF-датчика вне диапазона", causes: "Загрязнённый или неисправный MAF", repair: "Чистка или замена MAF-датчика", severity: 2)
    case "P0102": return DtcInfo(title: "Слабый сигнал MAF-датчика", causes: "КЗ в цепи, загрязнённый MAF", repair: "Замена MAF-датчика, проверка проводки", severity: 2)
    case "P0103": return DtcInfo(title: "Сильный сигнал MAF-датчика", causes: "Обрыв цепи, нарушение экранирования", repair: "Замена MAF-датчика", severity: 2)
    case "P0106": return DtcInfo(title: "Сигнал MAP-датчика вне диапазона", causes: "Утечки в впускном тракте, неисправный MAP", repair: "Проверка шлангов вакуума, замена MAP", severity: 2)
    case "P0107": return DtcInfo(title: "Слабый сигнал MAP-датчика", causes: "КЗ, обрыв трубки вакуума", repair: "Замена MAP-датчика", severity: 2)
    case "P0108": return DtcInfo(title: "Высокий сигнал MAP-датчика", causes: "Обрыв цепи MAP", repair: "Проверка и замена MAP-датчика", severity: 2)
    case "P0111": return DtcInfo(title: "Диапазон сигнала IAT-датчика", causes: "Неисправный датчик IAT", repair: "Замена датчика температуры воздуха", severity: 1)
    case "P0112": return DtcInfo(title: "Слабый сигнал IAT-датчика", causes: "КЗ цепи IAT", repair: "Замена датчика IAT", severity: 1)
    case "P0113": return DtcInfo(title: "Сигнал IAT-датчика высокий", causes: "Обрыв цепи, неисправный датчик IAT", repair: "Проверка проводки и замена IAT-датчика", severity: 1)
    case "P0115": return DtcInfo(title: "Цепь датчика ECT — неисправность", causes: "Повреждение проводки датчика охлаждающей жидкости", repair: "Проверка проводки, замена датчика ECT", severity: 2)
    case "P0116": return DtcInfo(title: "Диапазон датчика ECT", causes: "Неисправность датчика охлаждающей жидкости", repair: "Замена датчика ECT", severity: 2)
    case "P0117": return DtcInfo(title: "Слабый сигнал ECT-датчика", causes: "КЗ цепи ECT, датчик показывает перегрев", repair: "Замена датчика температуры охлаждающей жидкости", severity: 2)
    case "P0118": return DtcInfo(title: "Высокий сигнал ECT-датчика", causes: "Обрыв цепи ECT, датчик показывает холод", repair: "Замена датчика ECT, проверка соединений", severity: 2)
    case "P0120": return DtcInfo(title: "Цепь датчика TPS (A) — неисправность", causes: "Повреждение датчика дроссельной заслонки", repair: "Замена датчика TPS или модуля дросселя", severity: 2)
    case "P0121": return DtcInfo(title: "Диапазон сигнала TPS (A)", causes: "Неисправный датчик TPS, износ", repair: "Замена датчика положения дросселя", severity: 2)
    case "P0122": return DtcInfo(title: "Слабый сигнал TPS (A)", causes: "КЗ цепи TPS", repair: "Замена датчика TPS", severity: 2)
    case "P0123": return DtcInfo(title: "Высокий сигнал TPS (A)", causes: "Обрыв цепи TPS", repair: "Замена датчика TPS", severity: 2)
    case "P0125": return DtcInfo(title: "Двигатель не выходит на рабочую температуру", causes: "Термостат застрял в открытом положении", repair: "Замена термостата", severity: 2)
    case "P0128": return DtcInfo(title: "Температура охлаждающей ниже нормы", causes: "Термостат открыт, медленный прогрев", repair: "Замена термостата", severity: 2)
    case "P0130": return DtcInfo(title: "Цепь O2-датчика (B1S1) — неисправность", causes: "Обрыв, повреждение проводки датчика кислорода", repair: "Замена O2-датчика (банк 1, сенсор 1)", severity: 2)
    case "P0131": return DtcInfo(title: "Низкое напряжение O2-датчика (B1S1)", causes: "Бедная смесь, повреждён датчик", repair: "Диагностика смесеобразования, замена датчика", severity: 2)
    case "P0132": return DtcInfo(title: "Высокое напряжение O2-датчика (B1S1)", causes: "Богатая смесь, загрязнён датчик", repair: "Диагностика богатой смеси, замена датчика", severity: 2)
    case "P0133": return DtcInfo(title: "Медленный отклик O2-датчика (B1S1)", causes: "Загрязнение датчика, утечка выхлопа", repair: "Замена O2-датчика банк 1", severity: 2)
    case "P0134": return DtcInfo(title: "Нет активности O2-датчика (B1S1)", causes: "Датчик не выдаёт сигнал", repair: "Замена O2-датчика (B1S1)", severity: 2)
    case "P0135": return DtcInfo(title: "Отказ нагревателя O2-датчика (B1S1)", causes: "Оборванная нить нагревателя в датчике", repair: "Замена O2-датчика (банк 1, сенсор 1)", severity: 2)
    case "P0136": return DtcInfo(title: "Цепь O2-датчика (B1S2) — неисправность", causes: "Повреждение заднего датчика кислорода", repair: "Замена O2-датчика (банк 1, сенсор 2)", severity: 2)
    case "P0137": return DtcInfo(title: "Низкое напряжение O2-датчика (B1S2)", causes: "Проблемы с катализатором", repair: "Диагностика катализатора, замена датчика", severity: 2)
    case "P0138": return DtcInfo(title: "Высокое напряжение O2-датчика (B1S2)", causes: "Богатая смесь, неисправный катализатор", repair: "Диагностика, замена катализатора или датчика", severity: 2)
    case "P0139": return DtcInfo(title: "Медленный отклик O2-датчика (B1S2)", causes: "Износ заднего датчика", repair: "Замена O2-датчика (B1S2)", severity: 2)
    case "P0141": return DtcInfo(title: "Отказ нагревателя O2-датчика (B1S2)", causes: "Неисправен нагреватель заднего датчика", repair: "Замена O2-датчика (банк 1, сенсор 2)", severity: 2)
    case "P0150": return DtcInfo(title: "Цепь O2-датчика (B2S1) — неисправность", causes: "Повреждение датчика второй банки", repair: "Замена O2-датчика (банк 2, сенсор 1)", severity: 2)
    case "P0153": return DtcInfo(title: "Медленный отклик O2-датчика (B2S1)", causes: "Износ датчика банка 2", repair: "Замена O2-датчика (B2S1)", severity: 2)
    case "P0155": return DtcInfo(title: "Отказ нагревателя O2-датчика (B2S1)", causes: "Нить нагревателя сенсора B2S1 перегорела", repair: "Замена O2-датчика (банк 2, сенсор 1)", severity: 2)
    case "P0171": return DtcInfo(title: "Смесь бедная (Bank 1)", causes: "Засорённые форсунки, MAF, утечки впуска, насос топлива", repair: "Промывка форсунок, чистка MAF, поиск утечек", severity: 2)
    case "P0172": return DtcInfo(title: "Смесь богатая (Bank 1)", causes: "Протечки форсунок, высокое давление, O2-датчик", repair: "Проверка форсунок и регулятора давления", severity: 2)
    case "P0174": return DtcInfo(title: "Смесь бедная (Bank 2)", causes: "Утечки впуска, MAF, форсунки B2", repair: "Дымовой тест, проверка форсунок B2", severity: 2)
    case "P0175": return DtcInfo(title: "Смесь богатая (Bank 2)", causes: "Протечки форсунок B2, давление топлива", repair: "Проверка форсунок второй банки", severity: 2)

    // ── P02xx: Форсунки ─────────────────────────────────────────────────────
    case "P0200": return DtcInfo(title: "Цепь форсунок — общая неисправность", causes: "Повреждение проводки форсунок", repair: "Диагностика проводки форсунок", severity: 2)
    case "P0201": return DtcInfo(title: "Цепь форсунки — цилиндр 1", causes: "Обрыв/КЗ форсунки цилиндра 1", repair: "Замена форсунки №1", severity: 2)
    case "P0202": return DtcInfo(title: "Цепь форсунки — цилиндр 2", causes: "Обрыв/КЗ форсунки цилиндра 2", repair: "Замена форсунки №2", severity: 2)
    case "P0203": return DtcInfo(title: "Цепь форсунки — цилиндр 3", causes: "Обрыв/КЗ форсунки цилиндра 3", repair: "Замена форсунки №3", severity: 2)
    case "P0204": return DtcInfo(title: "Цепь форсунки — цилиндр 4", causes: "Обрыв/КЗ форсунки цилиндра 4", repair: "Замена форсунки №4", severity: 2)
    case "P0205": return DtcInfo(title: "Цепь форсунки — цилиндр 5", causes: "Обрыв/КЗ форсунки цилиндра 5", repair: "Замена форсунки №5", severity: 2)
    case "P0206": return DtcInfo(title: "Цепь форсунки — цилиндр 6", causes: "Обрыв/КЗ форсунки цилиндра 6", repair: "Замена форсунки №6", severity: 2)
    case "P0230": return DtcInfo(title: "Первичная цепь насоса топлива", causes: "Реле насоса, предохранитель, проводка", repair: "Проверка реле и предохранителя топливного насоса", severity: 3)
    case "P0234": return DtcInfo(title: "Избыточное давление наддува", causes: "Неисправный вастегейт, утечки патрубков", repair: "Диагностика клапана WG, замена актуатора", severity: 3)

    // ── P03xx: Зажигание / пропуски ─────────────────────────────────────────
    case "P0299": return DtcInfo(title: "Давление турбины ниже нормы", causes: "Утечки патрубков, актуатор WG, турбина", repair: "Проверка патрубков и клапана WG", severity: 3)
    case "P0300": return DtcInfo(title: "Случайный пропуск воспламенения", causes: "Свечи, катушки, форсунки, компрессия", repair: "Диагностика системы зажигания всех цилиндров", severity: 3)
    case "P0301": return DtcInfo(title: "Пропуск воспламенения — цилиндр 1", causes: "Свеча, катушка, форсунка цилиндра 1", repair: "Замена свечи и катушки цилиндра 1", severity: 3)
    case "P0302": return DtcInfo(title: "Пропуск воспламенения — цилиндр 2", causes: "Свеча, катушка, форсунка цилиндра 2", repair: "Замена свечи и катушки цилиндра 2", severity: 3)
    case "P0303": return DtcInfo(title: "Пропуск воспламенения — цилиндр 3", causes: "Свеча, катушка, форсунка цилиндра 3", repair: "Замена свечи и катушки цилиндра 3", severity: 3)
    case "P0304": return DtcInfo(title: "Пропуск воспламенения — цилиндр 4", causes: "Свеча, катушка, форсунка цилиндра 4", repair: "Замена свечи и катушки цилиндра 4", severity: 3)
    case "P0305": return DtcInfo(title: "Пропуск воспламенения — цилиндр 5", causes: "Свеча, катушка, форсунка цилиндра 5", repair: "Замена свечи и катушки цилиндра 5", severity: 3)
    case "P0306": return DtcInfo(title: "Пропуск воспламенения — цилиндр 6", causes: "Свеча, катушка, форсунка цилиндра 6", repair: "Замена свечи и катушки цилиндра 6", severity: 3)
    case "P0307": return DtcInfo(title: "Пропуск воспламенения — цилиндр 7", causes: "Свеча, катушка, форсунка цилиндра 7", repair: "Замена свечи и катушки цилиндра 7", severity: 3)
    case "P0308": return DtcInfo(title: "Пропуск воспламенения — цилиндр 8", causes: "Свеча, катушка, форсунка цилиндра 8", repair: "Замена свечи и катушки цилиндра 8", severity: 3)
    case "P0320": return DtcInfo(title: "Неисправность сигнала зажигания", causes: "Датчик CKP, проводка", repair: "Проверка цепи зажигания", severity: 3)
    case "P0325": return DtcInfo(title: "Неисправность датчика детонации (B1)", causes: "Обрыв или КЗ датчика детонации", repair: "Замена датчика детонации", severity: 2)
    case "P0326": return DtcInfo(title: "Диапазон сигнала датчика детонации (B1)", causes: "Неисправность датчика детонации", repair: "Замена датчика детонации (B1)", severity: 2)
    case "P0327": return DtcInfo(title: "Низкий сигнал датчика детонации (B1)", causes: "КЗ цепи датчика детонации", repair: "Проверка проводки и замена датчика", severity: 2)
    case "P0328": return DtcInfo(title: "Высокий сигнал датчика детонации (B1)", causes: "Обрыв цепи датчика детонации", repair: "Замена датчика детонации (B1)", severity: 2)
    case "P0335": return DtcInfo(title: "Нет сигнала датчика коленвала", causes: "Неисправный датчик, повреждён венец маховика", repair: "Замена датчика положения коленвала (CKP)", severity: 3)
    case "P0336": return DtcInfo(title: "Диапазон сигнала датчика CKP", causes: "Повреждён венец маховика, датчик CKP", repair: "Проверка зазора и замена датчика CKP", severity: 3)
    case "P0340": return DtcInfo(title: "Нет сигнала датчика распредвала (B1)", causes: "Неисправный датчик CMP, повреждение ротора", repair: "Замена датчика положения распредвала", severity: 3)
    case "P0341": return DtcInfo(title: "Диапазон сигнала датчика CMP (B1)", causes: "Датчик CMP, провода, ротор", repair: "Проверка и замена датчика CMP B1", severity: 2)
    case "P0345": return DtcInfo(title: "Нет сигнала датчика распредвала (B2)", causes: "Неисправный датчик CMP B2", repair: "Замена датчика CMP второй банки", severity: 3)
    case "P0365": return DtcInfo(title: "Нет сигнала датчика фазы распредвала (B2)", causes: "Неисправность датчика выпускного распредвала", repair: "Замена датчика фаз B2", severity: 2)

    // ── P04xx: Вспомогательные системы / выхлоп ─────────────────────────────
    case "P0400": return DtcInfo(title: "Поток EGR — неисправность", causes: "Неисправность клапана рециркуляции", repair: "Чистка или замена клапана EGR", severity: 2)
    case "P0401": return DtcInfo(title: "Недостаточный поток EGR", causes: "Засорённый EGR-клапан или каналы", repair: "Чистка или замена EGR-клапана", severity: 2)
    case "P0402": return DtcInfo(title: "Избыточный поток EGR", causes: "Клапан EGR не закрывается", repair: "Замена клапана EGR", severity: 2)
    case "P0403": return DtcInfo(title: "Цепь EGR-клапана — неисправность", causes: "Обрыв в соленоиде клапана EGR", repair: "Проверка проводки, замена EGR", severity: 2)
    case "P0410": return DtcInfo(title: "Система вторичного воздуха — неисправность", causes: "Насос, клапан вторичного воздуха", repair: "Диагностика системы вторичного воздуха", severity: 2)
    case "P0411": return DtcInfo(title: "Система вторичного воздуха — неправильный поток", causes: "Забит шланг или клапан", repair: "Замена клапана вторичного воздуха", severity: 2)
    case "P0420": return DtcInfo(title: "КПД катализатора ниже порога (Bank 1)", causes: "Износ нейтрализатора, утечка выхлопа, O2-датчик", repair: "Замена каталитического нейтрализатора", severity: 2)
    case "P0421": return DtcInfo(title: "КПД прогрева катализатора низкий (B1)", causes: "Износ нейтрализатора B1", repair: "Замена катализатора или проверка O2-датчика", severity: 2)
    case "P0430": return DtcInfo(title: "КПД катализатора ниже порога (Bank 2)", causes: "Износ нейтрализатора B2", repair: "Замена каталитического нейтрализатора (B2)", severity: 2)
    case "P0440": return DtcInfo(title: "Система EVAP — общая неисправность", causes: "Утечка паров топлива, крышка бака", repair: "Дымовой тест EVAP, проверка крышки бака", severity: 1)
    case "P0441": return DtcInfo(title: "Продувка EVAP — неправильный поток", causes: "Клапан продувки угольного фильтра", repair: "Замена клапана продувки EVAP", severity: 1)
    case "P0442": return DtcInfo(title: "Малая утечка системы EVAP", causes: "Неплотная крышка бака, трещина в трубке EVAP", repair: "Проверка крышки, дымовой тест EVAP", severity: 1)
    case "P0443": return DtcInfo(title: "Цепь клапана продувки EVAP", causes: "Обрыв/КЗ соленоида продувки", repair: "Замена клапана продувки угольного фильтра", severity: 1)
    case "P0446": return DtcInfo(title: "Вентиляция EVAP — неисправность цепи", causes: "Клапан вентиляции EVAP", repair: "Замена клапана вентиляции EVAP", severity: 1)
    case "P0455": return DtcInfo(title: "Большая утечка системы EVAP", causes: "Отсутствует или неплотная крышка бака", repair: "Замена крышки топливного бака, тест EVAP", severity: 1)
    case "P0456": return DtcInfo(title: "Очень малая утечка EVAP", causes: "Микротрещина в шланге или баке", repair: "Точный дымовой тест системы EVAP", severity: 1)

    // ── P05xx: Скорость / холостой ход / педаль ─────────────────────────────
    case "P0500": return DtcInfo(title: "Неисправность датчика скорости (VSS)", causes: "Обрыв датчика VSS, проблема с ABS", repair: "Замена датчика скорости", severity: 2)
    case "P0501": return DtcInfo(title: "Диапазон датчика VSS", causes: "Неисправность датчика скорости", repair: "Проверка и замена датчика VSS", severity: 2)
    case "P0505": return DtcInfo(title: "Нестабильный холостой ход", causes: "Загрязнённые IACV или дроссель", repair: "Чистка регулятора ХХ и дроссельной заслонки", severity: 2)
    case "P0506": return DtcInfo(title: "Обороты холостого хода ниже нормы", causes: "Загрязнённый IACV, утечки воздуха", repair: "Чистка регулятора холостого хода", severity: 2)
    case "P0507": return DtcInfo(title: "Обороты холостого хода выше нормы", causes: "Подсос воздуха мимо дросселя", repair: "Поиск утечек воздуха, чистка IAC", severity: 2)
    case "P0562": return DtcInfo(title: "Напряжение системы низкое", causes: "Слабый аккумулятор, неисправный генератор", repair: "Проверка генератора и аккумулятора", severity: 2)
    case "P0563": return DtcInfo(title: "Напряжение системы высокое", causes: "Перезаряд аккумулятора, неисправный регулятор генератора", repair: "Проверка регулятора напряжения генератора", severity: 2)

    // ── P06xx: Компьютер / электроника ───────────────────────────────────────
    case "P0600": return DtcInfo(title: "Ошибка CAN-шины", causes: "Неисправность CAN-шины, обрыв проводки", repair: "Диагностика CAN-шины", severity: 3)
    case "P0604": return DtcInfo(title: "Ошибка RAM ЭБУ", causes: "Внутренняя неисправность ЭБУ", repair: "Замена или перепрошивка ЭБУ", severity: 3)
    case "P0605": return DtcInfo(title: "Ошибка ROM ЭБУ", causes: "Неисправность флэш-памяти ЭБУ", repair: "Перепрошивка или замена ЭБУ", severity: 3)
    case "P0606": return DtcInfo(title: "Ошибка процессора ЭБУ", causes: "Внутренняя ошибка ЭБУ", repair: "Замена ЭБУ", severity: 3)
    case "P0607": return DtcInfo(title: "Производительность ЭБУ", causes: "Неисправность ЭБУ", repair: "Диагностика ЭБУ", severity: 3)

    // ── P07xx: АКПП ─────────────────────────────────────────────────────────
    case "P0700": return DtcInfo(title: "Неисправность управления АКПП (TCM)", causes: "Ошибка в ЭБУ АКПП", repair: "Диагностика АКПП отдельным сканером", severity: 3)
    case "P0705": return DtcInfo(title: "Датчик диапазона трансмиссии — неисправность", causes: "Неисправность датчика или рычага АКПП", repair: "Регулировка или замена датчика положения КПП", severity: 2)
    case "P0715": return DtcInfo(title: "Датчик частоты входного вала — неисправность", causes: "Неисправность датчика скорости АКПП", repair: "Замена датчика входного вала АКПП", severity: 2)
    case "P0720": return DtcInfo(title: "Датчик скорости выходного вала АКПП", causes: "Обрыв датчика, загрязнение масла", repair: "Замена датчика выходного вала АКПП", severity: 2)
    case "P0730": return DtcInfo(title: "Неправильное передаточное число", causes: "Неисправность соленоидов, загрязнённое масло", repair: "Замена масла АКПП, диагностика соленоидов", severity: 3)
    case "P0740": return DtcInfo(title: "Цепь блокировки гидротрансформатора (TCC)", causes: "Неисправность соленоида TCC", repair: "Замена соленоида блокировки ГТ", severity: 2)
    case "P0741": return DtcInfo(title: "TCC в режиме проскальзывания", causes: "Износ фрикциона ГТ, неисправность соленоида", repair: "Диагностика АКПП, замена масла", severity: 2)
    case "P0750": return DtcInfo(title: "Соленоид сдвига 1 (A) — неисправность", causes: "Обрыв/КЗ соленоида 1", repair: "Замена соленоида переключения передач №1", severity: 2)
    case "P0755": return DtcInfo(title: "Соленоид сдвига 2 (B) — неисправность", causes: "Обрыв/КЗ соленоида 2", repair: "Замена соленоида переключения передач №2", severity: 2)
    case "P0760": return DtcInfo(title: "Соленоид сдвига 3 (C) — неисправность", causes: "Обрыв/КЗ соленоида 3", repair: "Замена соленоида переключения передач №3", severity: 2)
    case "P0771": return DtcInfo(title: "Соленоид 3 в положении 'выкл' — застрял", causes: "Загрязнение масла АКПП", repair: "Замена масла и фильтра АКПП", severity: 2)

    // ── B — кузов / безопасность ─────────────────────────────────────────────
    case "B0001": return DtcInfo(title: "Неисправность воспламенителя подушки безопасности водителя", causes: "Обрыв цепи пиропатрона", repair: "Диагностика в сервисе SRS, замена пиропатрона", severity: 3)
    case "B0002": return DtcInfo(title: "Подушка безопасности пассажира — неисправность", causes: "Обрыв цепи пиропатрона пассажира", repair: "Диагностика SRS", severity: 3)
    case "B0051": return DtcInfo(title: "Ошибка блока SRS / Airbag", causes: "Внутренняя ошибка модуля подушек безопасности", repair: "Замена модуля SRS", severity: 3)
    case "B0081": return DtcInfo(title: "Неисправность бокового пиропатрона (левый)", causes: "Обрыв цепи боковой подушки", repair: "Диагностика боковой SRS", severity: 3)
    case "B0082": return DtcInfo(title: "Неисправность бокового пиропатрона (правый)", causes: "Обрыв цепи боковой подушки", repair: "Диагностика боковой SRS", severity: 3)
    case "B1000": return DtcInfo(title: "Ошибка блока управления кузовом (BCM)", causes: "Внутренняя ошибка BCM", repair: "Диагностика BCM", severity: 2)
    case "B1004": return DtcInfo(title: "Ошибка центрального замка", causes: "Привод, проводка, BCM", repair: "Диагностика центрального замка", severity: 1)
    case "B1190": return DtcInfo(title: "Ошибка иммобилайзера", causes: "Чип ключа, антенна иммобилайзера", repair: "Диагностика и перепрограммирование ключа", severity: 2)
    case "B2000": return DtcInfo(title: "Ошибка модуля кондиционирования", causes: "Неисправность блока климата", repair: "Диагностика системы кондиционирования", severity: 1)

    // ── C — шасси / ABS ──────────────────────────────────────────────────────
    case "C0031": return DtcInfo(title: "Датчик скорости переднего левого колеса — неисправность", causes: "Обрыв датчика ABS, тонговое кольцо", repair: "Замена датчика ABS передний левый", severity: 2)
    case "C0034": return DtcInfo(title: "Датчик скорости переднего правого колеса — неисправность", causes: "Обрыв датчика ABS", repair: "Замена датчика ABS передний правый", severity: 2)
    case "C0037": return DtcInfo(title: "Датчик скорости заднего левого колеса — неисправность", causes: "Обрыв датчика ABS", repair: "Замена датчика ABS задний левый", severity: 2)
    case "C0040": return DtcInfo(title: "Датчик скорости заднего правого колеса — неисправность", causes: "Обрыв датчика ABS", repair: "Замена датчика ABS задний правый", severity: 2)
    case "C0051": return DtcInfo(title: "Клапан ABS переднего левого — неисправность", causes: "Неисправность гидроблока ABS", repair: "Замена гидроблока ABS", severity: 3)
    case "C0110": return DtcInfo(title: "Двигатель насоса ABS — неисправность", causes: "Неисправность мотора гидробока", repair: "Замена гидроблока ABS", severity: 3)
    case "C0121": return DtcInfo(title: "Клапан ABS — неисправность цепи", causes: "Неисправность соленоидов ABS", repair: "Диагностика и замена гидроблока ABS", severity: 3)
    case "C0265": return DtcInfo(title: "Реле мотора гидроблока ABS — неисправность", causes: "Неисправность реле насоса ABS", repair: "Замена реле или гидроблока ABS", severity: 3)
    case "C1201": return DtcInfo(title: "Неисправность системы ABS (Toyota)", causes: "Внутренняя ошибка блока ABS", repair: "Диагностика ABS, замена блока", severity: 3)

    // ── U — сеть / CAN-шина ─────────────────────────────────────────────────
    case "U0001": return DtcInfo(title: "Потеря связи CAN-шины", causes: "Обрыв CAN H или CAN L, плохой контакт", repair: "Проверка проводки CAN-шины", severity: 3)
    case "U0073": return DtcInfo(title: "Потеря связи шины управления", causes: "Обрыв или КЗ CAN-шины", repair: "Диагностика CAN-шины всех блоков", severity: 3)
    case "U0100": return DtcInfo(title: "Потеря связи с ЭБУ двигателя (ECM/PCM)", causes: "Обрыв CAN, питание ЭБУ", repair: "Диагностика CAN-шины, проверка питания ЭБУ", severity: 3)
    case "U0101": return DtcInfo(title: "Потеря связи с блоком TCM", causes: "Неисправность CAN-шины АКПП", repair: "Диагностика CAN-шины, проверка блока АКПП", severity: 3)
    case "U0121": return DtcInfo(title: "Потеря связи с блоком ABS", causes: "Обрыв CAN до блока ABS", repair: "Диагностика CAN-шины, проверка блока ABS", severity: 3)
    case "U0140": return DtcInfo(title: "Потеря связи с блоком кузова (BCM)", causes: "Неисправность CAN-шины BCM", repair: "Диагностика CAN-шины, проверка BCM", severity: 2)
    case "U0155": return DtcInfo(title: "Потеря связи с панелью приборов (IPC)", causes: "CAN-шина до панели приборов", repair: "Диагностика CAN-шины", severity: 2)

    // ── P1xxx: Производитель-специфичные (общие популярные) ──────────────────
    case "P1135": return DtcInfo(title: "Датчик A/F (Toyota) — нагреватель", causes: "Неисправность нагревателя датчика соотношения воздух/топливо", repair: "Замена датчика A/F Toyota", severity: 2)
    case "P1300": return DtcInfo(title: "Первичная цепь катушки зажигания (Toyota)", causes: "Неисправность катушки или проводки", repair: "Замена катушки зажигания", severity: 2)
    case "P1397": return DtcInfo(title: "Датчик положения распредвала (BMW VANOS)", causes: "Неисправность системы VANOS BMW", repair: "Диагностика VANOS, замена датчика", severity: 2)
    case "P1456": return DtcInfo(title: "Утечка EVAP — топливный бак (Honda)", causes: "Неплотная крышка бака, повреждённая трубка EVAP", repair: "Проверка крышки, дымовой тест EVAP", severity: 1)
    case "P1457": return DtcInfo(title: "Утечка EVAP — клапан продувки (Honda)", causes: "Неисправный продувочный клапан EVAP", repair: "Замена клапана продувки", severity: 1)
    case "P1500": return DtcInfo(title: "Цепь генератора — неисправность", causes: "Неисправность генератора или регулятора напряжения", repair: "Диагностика генератора", severity: 2)
    case "P1507": return DtcInfo(title: "Холостой ход ниже нормы при холодном пуске", causes: "Загрязнён IAC, утечки воздуха", repair: "Чистка клапана IAC, поиск утечек", severity: 2)
    case "P1523": return DtcInfo(title: "Неисправность Valvetronic (BMW)", causes: "Неисправность исполнительного мотора Valvetronic", repair: "Диагностика Valvetronic, замена мотора", severity: 3)
    case "P1570": return DtcInfo(title: "Иммобилайзер — нет разрешения на запуск", causes: "Неисправность чипа ключа или антенны иммобилайзера", repair: "Диагностика и программирование ключа", severity: 3)
    case "P1572": return DtcInfo(title: "Иммобилайзер — ошибка связи", causes: "Потеря связи с модулем иммобилайзера", repair: "Диагностика иммобилайзера", severity: 2)

    default:
        return DtcInfo(
            title: "Код неисправности \(code)",
            causes: "Обратитесь к документации ЭБУ для данной марки и модели",
            repair: "Диагностика в сервисе профессиональным сканером",
            severity: 2
        )
    }
}

// MARK: - Problem Description Builder

/// Человекочитаемые описания проблем для AI-агента UREMONT.
/// Точные совпадения — словарь; regex-паттерны (P030x) — отдельная ветка.
///
/// Используется в `buildProblemDescription` для формирования текста запроса
/// к AI-сервису UREMONT. Описания написаны на русском в свободной форме,
/// чтобы AI-агент мог понять контекст и подобрать ближайший автосервис.
private static let problemDescriptions: [String: String] = [
    "P0011": "смещение фаз на опережение впускного распредвала, стук цепи ГРМ, нужна диагностика системы VVT и замена масла",
    "P0012": "смещение фаз на запаздывание впускного распредвала, нужна чистка клапана VVT и замена масла",
    "P0014": "смещение фаз на опережение выпускного распредвала, нужна диагностика VVT",
    "P0016": "рассогласование коленвала и распредвала, стук цепи ГРМ, нужна замена цепи и натяжителя",
    "P0017": "рассогласование коленвала и выпускного распредвала, нужна диагностика ГРМ",
    "P0100": "некорректная работа датчика массового расхода воздуха MAF, нестабильный холостой ход, нужна чистка или замена MAF",
    "P0101": "некорректная работа датчика массового расхода воздуха MAF, нестабильный холостой ход, нужна чистка или замена MAF",
    "P0102": "слабый сигнал MAF датчика, нужна замена датчика массового расхода воздуха",
    "P0113": "обрыв датчика температуры воздуха на впуске, нужна замена датчика IAT",
    "P0115": "неисправность датчика температуры охлаждающей жидкости, нужна замена датчика ECT",
    "P0116": "неисправность датчика температуры охлаждающей жидкости, нужна замена датчика ECT",
    "P0117": "датчик температуры охлаждающей жидкости даёт заниженный сигнал, нужна замена датчика",
    "P0120": "неисправность датчика положения дроссельной заслонки TPS, нужна замена датчика TPS",
    "P0128": "двигатель плохо прогревается до рабочей температуры, нужна замена термостата",
    "P0130": "нет сигнала датчика кислорода банка 1, нужна замена лямбда-зонда до катализатора",
    "P0133": "медленный отклик датчика кислорода банка 1 датчик 1, нужна замена лямбда-зонда",
    "P0135": "неисправен нагреватель лямбда-зонда банка 1 датчик 1, нужна замена датчика кислорода",
    "P0136": "сигнал датчика кислорода после катализатора вне нормы, нужна замена лямбда-зонда банка 1 датчик 2",
    "P0141": "неисправен нагреватель заднего лямбда-зонда, нужна замена датчика кислорода банка 1 датчик 2",
    "P0150": "неисправность датчика кислорода банка 2, нужна замена лямбда-зонда",
    "P0153": "неисправность датчика кислорода банка 2, нужна замена лямбда-зонда",
    "P0171": "двигатель работает на бедной смеси банк 1, плохой холостой ход, нужна диагностика утечек воздуха и промывка MAF датчика",
    "P0172": "двигатель работает на богатой смеси банк 1, запах бензина, нужна диагностика форсунок и давления топлива",
    "P0174": "бедная смесь на банке 2, нужна диагностика системы питания правой банки",
    "P0175": "богатая смесь на банке 2, нужна диагностика форсунок правой банки",
    "P0234": "избыточное давление наддува, нужна диагностика турбины и клапана wastegate",
    "P0299": "давление турбонаддува ниже нормы, машина не тянет, нужна диагностика турбины и патрубков наддува",
    "P0300": "пропуски зажигания во всех цилиндрах, вибрация двигателя, нужна диагностика и замена свечей зажигания и катушек",
    "P0325": "неисправность датчика детонации, риск повреждения поршней, нужна замена датчика детонации",
    "P0326": "неисправность датчика детонации, риск повреждения поршней, нужна замена датчика детонации",
    "P0335": "потеря сигнала датчика коленчатого вала, двигатель не запускается, нужна замена датчика CKP",
    "P0340": "потеря сигнала датчика распределительного вала, нестабильная работа, нужна замена датчика CMP",
    "P0365": "нет сигнала датчика фазы распредвала банка 2, нужна замена датчика",
    "P0401": "недостаточная рециркуляция выхлопных газов, нестабильный холостой ход, нужна чистка или замена клапана EGR",
    "P0402": "избыточный поток EGR, нужна диагностика и замена клапана рециркуляции",
    "P0420": "снизилась эффективность каталитического нейтрализатора банка 1, повышенный расход топлива, нужна замена катализатора",
    "P0430": "снизилась эффективность каталитического нейтрализатора банка 2, нужна замена катализатора",
    "P0442": "небольшая утечка в системе паров топлива, нужна проверка крышки бака и шлангов EVAP",
    "P0455": "большая утечка в системе паров топлива, нужна замена крышки топливного бака или шлангов",
    "P0500": "нет сигнала датчика скорости, спидометр не работает, нужна замена датчика VSS",
    "P0505": "нестабильный холостой ход, плавают обороты, нужна чистка дроссельной заслонки и регулятора холостого хода",
    "P0700": "неисправность в автоматической коробке передач, толчки при переключении, нужна компьютерная диагностика АКПП",
    "P0730": "неправильное передаточное число АКПП, нужна диагностика гидроблока и соленоидов",
    "P1397": "неисправность системы VANOS BMW, нужна диагностика и ремонт VANOS",
    "P1456": "утечка в системе испарения топлива Honda, нужна диагностика системы EVAP и замена продувочного клапана",
    "P1457": "утечка в системе испарения топлива Honda, нужна диагностика системы EVAP и замена продувочного клапана",
    "P1523": "неисправность Valvetronic BMW, нужна диагностика системы изменения подъёма клапанов",
    "P1349": "неисправность системы VVT-i Toyota, часто клапан OCV или качество масла, нужна диагностика VVT",
    "P1354": "неисправность VVT второй банки Toyota, нужна проверка OCV и масла",
    "P1150": "датчик соотношения воздух/топливо банк 2 Toyota вне диапазона, нужна замена A/F B2S1",
    "P1153": "медленный отклик датчика A/F банк 2 Toyota, нужна замена датчика",
    "P1155": "неисправен нагреватель датчика A/F банк 2 Toyota, нужна замена датчика",
    "P1604": "ошибка стартовой процедуры Toyota, нужна проверка АКБ и стартера",
    "P1663": "неисправность цепи клапана масла VVT (OCV) Toyota, нужна замена клапана или проводки",
]

/// Формирует человекочитаемое описание проблемы для AI-агента UREMONT.
///
/// Алгоритм:
/// 1. Точное совпадение в словаре `problemDescriptions` → возвращает готовое описание.
/// 2. Regex-паттерн P030[1-9] → генерирует описание пропуска зажигания с номером цилиндра.
/// 3. Fallback → конкатенация `title` + `repair` из `DtcInfo` в нижнем регистре.
///
/// - Parameters:
///   - code: OBD-II код ошибки (например, "P0420").
///   - info: Расшифровка кода из `dtcInfo(code:profile:)`.
/// - Returns: Описание проблемы на русском для передачи в параметр `ai` URL.
static func buildProblemDescription(code: String, info: DtcInfo) -> String {
    let base = baseDtcCode(code)
    if let desc = problemDescriptions[base] { return desc }

    // P030[1-9] — пропуск воспламенения в конкретном цилиндре
    if base.count == 5, base.hasPrefix("P030"), let last = base.last, last >= "1" && last <= "9" {
        return "пропуск зажигания в цилиндре №\(last), двигатель трясётся, нужна замена свечи зажигания и катушки цилиндра №\(last)"
    }

    let titleLower = info.title.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    let repairLower = info.repair.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return "\(titleLower). рекомендуется: \(repairLower)"
}

// MARK: - UREMONT URL Builder

/// Формирует URL для сайта UREMONT с описанием проблемы.
///
/// Структура URL: `https://map.uremont.com/?ai=[запрос]`
/// Запрос = "[марка] [год] [описание проблемы]"
///
/// Использует `URLComponents` для безопасного percent-encoding кириллицы и спецсимволов
/// (аналог `Uri.Builder` на Android, но через Foundation `URLComponents`).
///
/// Приоритет данных об автомобиле:
/// 1. `vehicleInfo.detectedMake` / `detectedYear` — из VIN через ЭБУ.
/// 2. `carProfile.manual` — ручной выбор пользователя (дополняет, если VIN не дал марку).
/// 3. Fallback: «автомобиль» — если ни VIN, ни профиль не содержат данных.
///
/// - Parameters:
///   - profile: Профиль автомобиля (`.auto` или `.manual`).
///   - vehicleInfo: Информация из ЭБУ (может быть `nil`).
///   - code: OBD-II код ошибки.
///   - info: Расшифровка кода.
/// - Returns: Полный URL-строка вида `https://map.uremont.com/?ai=BMW+2019+...`.
static func buildUremontUrl(
    profile: CarProfile,
    vehicleInfo: VehicleInfo?,
    code: String,
    info: DtcInfo
) -> String {
    var carParts: [String] = []

    if let make = vehicleInfo?.detectedMake { carParts.append(make) }
    if let year = vehicleInfo?.detectedYear { carParts.append(year) }

    if case let .manual(make, model, year) = profile {
        if carParts.isEmpty { carParts.append(make) }
        if !model.isEmpty { carParts.append(model) }
        if vehicleInfo?.detectedYear == nil && !year.isEmpty { carParts.append(year) }
    }

    if carParts.isEmpty { carParts.append("автомобиль") }

    let problem = buildProblemDescription(code: code, info: info)
    let raw = "\(carParts.joined(separator: " ")) \(problem)"
    var components = URLComponents()
    components.scheme = BrandConfig.mapScheme
    components.host = BrandConfig.mapHost
    components.path = "/"
    components.queryItems = [URLQueryItem(name: BrandConfig.mapQueryAi, value: raw)]
    let fallback = "\(BrandConfig.mapScheme)://\(BrandConfig.mapHost)/?\(BrandConfig.mapQueryAi)=\(raw)"
    return components.url?.absoluteString ?? fallback
}

} // end enum DtcLookup
