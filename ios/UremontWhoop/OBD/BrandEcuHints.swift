import Foundation

/// Дополнительные CAN-заголовки (ATSH) для Mode 03 на конкретных марках.
/// Базовый набор 7B0/7D0/7E1/7E2/7E3/7E4 совпадает с Android `BrandEcuHints`.
///
/// `VehicleBrandGroup` и `classify` — для UDS-проб одометра щитка и др. марочных функций.
/// `rawValue` совпадает с именем enum на Android (`HYUNDAI_KIA`, …) для логов и PDF.
///
/// **Порядок `classify` критически важен**: Renault (VF1/VF2/VF6) проверяется ДО PSA (VF3/VF7),
/// иначе французские VIN Renault ошибочно попадают в группу PSA из-за общего префикса `VF`.
enum BrandEcuHints {
    /// Покрывает топ-15 марок РФ (по автопарку) + быстрорастущие китайские бренды.
    enum VehicleBrandGroup: String, Sendable {
        case OTHER, VAG, TOYOTA, HONDA, FORD, MERCEDES
        case RENAULT, PSA, GM, HYUNDAI_KIA, MAZDA, NISSAN
        case MITSUBISHI, SUBARU, BMW_MINI, JAGUAR, LADA
        case CHANGAN, CHERY, HAVAL_GWM, GEELY
    }

    /// Порядок проверок: Renault ДО PSA (общий VF-префикс), Mitsubishi ДО Nissan.
    static func classify(detectedMake: String?, vin: String?) -> VehicleBrandGroup {
        let m = detectedMake?.lowercased() ?? ""
        let wmi = vin.map { String($0.prefix(3)).uppercased() } ?? ""
        if isLikelyVag(makeLower: m, wmi: wmi) { return .VAG }
        if isLikelyToyota(makeLower: m, wmi: wmi) { return .TOYOTA }
        if isLikelyHonda(makeLower: m, wmi: wmi) { return .HONDA }
        if isLikelyFord(makeLower: m, wmi: wmi) { return .FORD }
        if isLikelyMercedes(makeLower: m, wmi: wmi) { return .MERCEDES }
        if isLikelyBmwMini(makeLower: m, wmi: wmi) { return .BMW_MINI }
        if isLikelyJaguarLandRover(makeLower: m, wmi: wmi) { return .JAGUAR }
        if isLikelyRenault(makeLower: m, wmi: wmi) { return .RENAULT }     // ДО PSA!
        if isLikelyPsa(makeLower: m, wmi: wmi) { return .PSA }
        if isLikelyGm(makeLower: m, wmi: wmi) { return .GM }
        if isLikelyHyundaiKia(makeLower: m, wmi: wmi) { return .HYUNDAI_KIA }
        if isLikelyMazda(makeLower: m, wmi: wmi) { return .MAZDA }
        if isLikelyMitsubishi(makeLower: m, wmi: wmi) { return .MITSUBISHI }
        if isLikelyNissan(makeLower: m, wmi: wmi) { return .NISSAN }
        if isLikelySubaru(makeLower: m, wmi: wmi) { return .SUBARU }
        if isLikelyHavalGwm(makeLower: m, wmi: wmi) { return .HAVAL_GWM }
        if isLikelyGeely(makeLower: m, wmi: wmi) { return .GEELY }
        if isLikelyLada(makeLower: m, wmi: wmi) { return .LADA }
        if isLikelyChangan(makeLower: m, wmi: wmi) { return .CHANGAN }
        if isLikelyChery(makeLower: m, wmi: wmi) { return .CHERY }
        return .OTHER
    }

    struct Spec: Sendable {
        let name: String
        let txHeader: String
    }

    private static let universal: [Spec] = [
        Spec(name: "ABS / Тормоза", txHeader: "7B0"),
        Spec(name: "SRS / Подушки безопасности", txHeader: "7D0"),
        Spec(name: "Коробка передач (TCM)", txHeader: "7E1"),
        Spec(name: "Доп. силовой (гибрид / дизель / 2-й ECM)", txHeader: "7E2"),
        Spec(name: "Раздаточная коробка / 4WD", txHeader: "7E3"),
        Spec(name: "Кузов (BCM)", txHeader: "7E4"),
    ]

    private static let vagWmi: Set<String> = [
        "TRU", "XW8", "TMB", "TMA", "TMP", "VSS", "1VW", "3VW", "9BW", "8AW",
    ]

    private static let fordWmi: Set<String> = [
        "WF0", "WF1", "WFO", "XLC", "MNA", "MPB", "LVS", "LVR",
        "5LM", "1LN", "2LM", "X9F",
        "NM0", "PEF", "MAJ", "6FP", "94D", "TW2",
    ]

    // UU1 = Dacia (Renault Group), перенесён в renaultWmi
    private static let psaWmi: Set<String> = [
        "W0L", "W0V", "UU2", "U5Y", "U6Y", "VR2", "VR3", "VR7",
    ]

    private static let gmWmi: Set<String> = ["LGX", "LGB", "LGC", "LGH", "LGR"]

    private static let hyundaiKiaWmi: Set<String> = ["MAL", "MXK", "NLH"]

    // KNM = Renault Korea (бывш. Samsung Motors), перенесён в renaultWmi
    private static let nissanWmi: Set<String> = ["MDH", "MNB", "MNT", "SJN", "VSK", "JNK", "RN8"]

    private static let ladaWmi: Set<String> = ["XTF", "XTK", "X1L", "XTT", "XTD", "XCL"]

    private static let renaultWmi: Set<String> = [
        "UU1", "KNM", "8A1", "8G1", "93Y", "ADR", "MEE", "SDG",
        "VS5", "VSY", "Y9Z", "VG6", "VG7", "NM1",
    ]

    private static let mitsubishiWmi: Set<String> = [
        "Z8T", "6MM", "4A3", "4A4", "XMC", "XMD", "XNB", "ML3", "KPH",
    ]

    private static let havalGwmWmi: Set<String> = ["8L4", "MNU", "X9X", "XZG"]

    private static let geelyWmi: Set<String> = ["L10", "LLV", "LMP", "Y4K", "Y7W"]

    private static let changanWmi: Set<String> = ["LPA"]

    private static let cheryWmi: Set<String> = ["98R", "9UJ", "PRH", "HJR"]

    private static let mercedesWmi: Set<String> = [
        "4JG", "55S", "WD3", "WD4", "WDA", "WDZ",
        "VSA", "9BM", "ADB", "MBR", "NMB", "RLM",
    ]

    /// Склеивает WMI-марку и строку из ручного профиля, чтобы без VIN всё равно подмешивались марочные CAN-ID (EPS Toyota `7A0` и т.д.).
    static func mergeMakeHints(detectedMake: String?, manualMakeHint: String?) -> String {
        let parts = [detectedMake, manualMakeHint]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " ").lowercased()
    }

    /// - Parameter manualMakeHint: поле «марка» из `CarProfile.manual`, если VIN не дал `detectedMake`.
    static func ecuProbeList(detectedMake: String?, vin: String?, manualMakeHint: String? = nil) -> [Spec] {
        var seen = Set<String>()
        var out: [Spec] = []
        for e in universal + additionalSpecs(detectedMake: detectedMake, vin: vin, manualMakeHint: manualMakeHint) {
            let h = e.txHeader.uppercased()
            if seen.insert(h).inserted { out.append(e) }
        }
        return out
    }

    static func additionalSpecs(detectedMake: String?, vin: String?, manualMakeHint: String? = nil) -> [Spec] {
        let m = mergeMakeHints(detectedMake: detectedMake, manualMakeHint: manualMakeHint)
        let wmi = vin.map { String($0.prefix(3)).uppercased() } ?? ""
        var out: [Spec] = []
        if isLikelyVag(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Шлюз / Gateway (VAG)", txHeader: "710"))
            out.append(Spec(name: "Комбинация приборов (VAG)", txHeader: "714"))
            out.append(Spec(name: "ABS / ESP доп. (VAG)", txHeader: "7B6"))
            out.append(Spec(name: "Рулевое управление (VAG)", txHeader: "712"))
            out.append(Spec(name: "Тормоза / ESP (VAG)", txHeader: "713"))
            out.append(Spec(name: "Подушки безопасности (VAG)", txHeader: "715"))
            out.append(Spec(name: "Рулевая колонка / SWM (VAG)", txHeader: "716"))
            out.append(Spec(name: "Стояночный тормоз / EPB (VAG)", txHeader: "752"))
            out.append(Spec(name: "Park Assist (VAG)", txHeader: "70A"))
            out.append(Spec(name: "Lane Assist / камера (VAG)", txHeader: "750"))
            out.append(Spec(name: "ACC / адаптив. круиз (VAG)", txHeader: "757"))
            out.append(Spec(name: "TPMS / давление шин (VAG)", txHeader: "765"))
            out.append(Spec(name: "HVAC / Климатроник (VAG)", txHeader: "770"))
        }
        if isLikelyToyota(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Body / Gateway (Toyota)", txHeader: "750"))
            out.append(Spec(name: "Комбинация приборов (Toyota)", txHeader: "7C0"))
            out.append(Spec(name: "EPS / Рулевое (Toyota)", txHeader: "7A0"))
            out.append(Spec(name: "Auto-Leveling фар (Toyota)", txHeader: "740"))
            out.append(Spec(name: "SRS / Ремни (Toyota)", txHeader: "780"))
            out.append(Spec(name: "Smart Key / иммобилайзер (Toyota)", txHeader: "788"))
            out.append(Spec(name: "TPMS (Toyota)", txHeader: "790"))
            out.append(Spec(name: "Parking Assist / Sonar (Toyota)", txHeader: "792"))
            out.append(Spec(name: "HVAC / кондиционер (Toyota)", txHeader: "744"))
            out.append(Spec(name: "Pre-Collision / ACC (Toyota)", txHeader: "7A8"))
        }
        if isLikelyHonda(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Комбинация приборов (Honda)", txHeader: "760"))
            out.append(Spec(name: "EPS / Рулевое (Honda)", txHeader: "7A0"))
            out.append(Spec(name: "Body / MICU (Honda)", txHeader: "7C0"))
            out.append(Spec(name: "HVAC / Климат (Honda)", txHeader: "770"))
            out.append(Spec(name: "VSA / стабилизация (Honda)", txHeader: "730"))
            out.append(Spec(name: "Honda Sensing / ADAS (Honda)", txHeader: "750"))
            out.append(Spec(name: "TPMS / давление шин (Honda)", txHeader: "780"))
        }
        if isLikelyFord(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Комбинация приборов IPC (Ford/Lincoln)", txHeader: "720"))
            out.append(Spec(name: "КПП / TCM (Ford, запасной 743)", txHeader: "743"))
            out.append(Spec(name: "Доп. модуль APIM (Ford)", txHeader: "726"))
            out.append(Spec(name: "Доп. модуль (Ford)", txHeader: "732"))
            out.append(Spec(name: "BCM доп. (Ford)", txHeader: "724"))
            out.append(Spec(name: "RCM / SRS доп. (Ford)", txHeader: "736"))
            out.append(Spec(name: "Parking Aid / PDC (Ford)", txHeader: "760"))
            out.append(Spec(name: "ABS / ESP доп. (Ford)", txHeader: "764"))
            out.append(Spec(name: "HVAC / климат (Ford)", txHeader: "770"))
            out.append(Spec(name: "EPS / Рулевое (Ford)", txHeader: "7A0"))
            out.append(Spec(name: "ACC / адаптив. круиз (Ford)", txHeader: "7A4"))
        }
        if isLikelyMercedes(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Комбинация приборов IC (Mercedes)", txHeader: "720"))
            out.append(Spec(name: "SAM передний (Mercedes)", txHeader: "740"))
            out.append(Spec(name: "SAM задний (Mercedes)", txHeader: "741"))
            out.append(Spec(name: "EZS / замок зажигания (Mercedes)", txHeader: "743"))
            out.append(Spec(name: "EPS / Рулевое (Mercedes)", txHeader: "7A0"))
            out.append(Spec(name: "ESP доп. (Mercedes)", txHeader: "7D2"))
            out.append(Spec(name: "Parktronic / PDC (Mercedes)", txHeader: "760"))
            out.append(Spec(name: "HVAC / климат (Mercedes)", txHeader: "770"))
            out.append(Spec(name: "Рулевая колонка (Mercedes)", txHeader: "716"))
            out.append(Spec(name: "Distronic / ACC (Mercedes)", txHeader: "74A"))
        }
        // Renault: щиток 770, кузовной UCH 742, доп. модули
        if isLikelyRenault(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Щиток / TDB (Renault)", txHeader: "770"))
            out.append(Spec(name: "UCH / кузовной (Renault)", txHeader: "742"))
            out.append(Spec(name: "EPS / Рулевое (Renault)", txHeader: "760"))
            out.append(Spec(name: "HVAC / Климат (Renault)", txHeader: "771"))
            out.append(Spec(name: "Parking доп. (Renault)", txHeader: "762"))
            out.append(Spec(name: "ABS / ESP доп. (Renault)", txHeader: "764"))
            out.append(Spec(name: "Body / Gateway (Renault)", txHeader: "750"))
        }
        if isLikelyPsa(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Комбинация / BSI (PSA)", txHeader: "752"))
            out.append(Spec(name: "Доп. блок (PSA)", txHeader: "753"))
            out.append(Spec(name: "Кузов / BSI (PSA)", txHeader: "740"))
            out.append(Spec(name: "Доп. (PSA)", txHeader: "742"))
            out.append(Spec(name: "ABS / ESP (PSA)", txHeader: "764"))
            out.append(Spec(name: "EPS / Рулевое (PSA)", txHeader: "760"))
            out.append(Spec(name: "HVAC / климат (PSA)", txHeader: "770"))
            out.append(Spec(name: "Body / BSM (PSA)", txHeader: "750"))
        }
        if isLikelyGm(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "IPC / приборка (GM)", txHeader: "724"))
            out.append(Spec(name: "Доп. модуль (GM)", txHeader: "728"))
            out.append(Spec(name: "Доп. модуль (GM)", txHeader: "244"))
            out.append(Spec(name: "SDM / SRS доп. (GM)", txHeader: "7D2"))
            out.append(Spec(name: "Park Assist / PDC (GM)", txHeader: "7A6"))
            out.append(Spec(name: "Комбинация вторичная (GM)", txHeader: "7C0"))
            out.append(Spec(name: "HVAC / климат (GM)", txHeader: "744"))
        }
        if isLikelyHyundaiKia(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Комбинация (Hyundai/Kia)", txHeader: "7A0"))
            out.append(Spec(name: "Доп. блок (Hyundai/Kia)", txHeader: "7A2"))
            out.append(Spec(name: "TPMS / давление шин (Hyundai/Kia)", txHeader: "7A6"))
            out.append(Spec(name: "Кластер / BCM (Hyundai/Kia)", txHeader: "770"))
            out.append(Spec(name: "Доп. (Hyundai/Kia)", txHeader: "771"))
            out.append(Spec(name: "Smart Key (Hyundai/Kia)", txHeader: "794"))
            out.append(Spec(name: "Доп. (Hyundai/Kia)", txHeader: "7C6"))
            out.append(Spec(name: "EPB / стояночный тормоз (Hyundai/Kia)", txHeader: "7D4"))
            out.append(Spec(name: "ADAS / камера (Hyundai/Kia)", txHeader: "7C0"))
        }
        if isLikelyMazda(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Комбинация (Mazda)", txHeader: "720"))
            out.append(Spec(name: "Доп. (Mazda)", txHeader: "730"))
            out.append(Spec(name: "Доп. (Mazda)", txHeader: "731"))
            out.append(Spec(name: "EPS / Рулевое (Mazda)", txHeader: "7A0"))
            out.append(Spec(name: "DSC / ABS доп. (Mazda)", txHeader: "764"))
            out.append(Spec(name: "BCM доп. (Mazda)", txHeader: "742"))
            out.append(Spec(name: "PDC / парковка (Mazda)", txHeader: "760"))
            out.append(Spec(name: "HVAC / климат (Mazda)", txHeader: "770"))
        }
        // Mitsubishi: gateway 750, комбинация 7C0, EPS 760
        if isLikelyMitsubishi(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Body / Gateway (Mitsubishi)", txHeader: "750"))
            out.append(Spec(name: "Комбинация приборов (Mitsubishi)", txHeader: "7C0"))
            out.append(Spec(name: "EPS / Рулевое (Mitsubishi)", txHeader: "760"))
            out.append(Spec(name: "HVAC / климат (Mitsubishi)", txHeader: "770"))
            out.append(Spec(name: "TPMS (Mitsubishi)", txHeader: "790"))
            out.append(Spec(name: "BCM / головной свет (Mitsubishi)", txHeader: "740"))
            out.append(Spec(name: "EPS / Рулевое (Mitsubishi)", txHeader: "7A0"))
        }
        if isLikelyNissan(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Комбинация приборов (Nissan/Infiniti)", txHeader: "743"))
            out.append(Spec(name: "Доп. комбинация (Nissan)", txHeader: "744"))
            out.append(Spec(name: "BCM / IPDM (Nissan)", txHeader: "740"))
            out.append(Spec(name: "EPS / Рулевое (Nissan)", txHeader: "746"))
            out.append(Spec(name: "ABS / VDC доп. (Nissan)", txHeader: "747"))
            out.append(Spec(name: "Body / IPDM доп. (Nissan)", txHeader: "760"))
            out.append(Spec(name: "HVAC / Климат (Nissan)", txHeader: "765"))
            out.append(Spec(name: "TPMS (Nissan)", txHeader: "772"))
            out.append(Spec(name: "ACC / радар (Nissan)", txHeader: "7B2"))
            out.append(Spec(name: "Доп. (Nissan)", txHeader: "793"))
            out.append(Spec(name: "Body / BCM доп. (Nissan)", txHeader: "750"))
            out.append(Spec(name: "Smart Key (Nissan)", txHeader: "788"))
        }
        if isLikelyBmwMini(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "KOMBI / приборка (BMW)", txHeader: "600"))
            out.append(Spec(name: "Доп. KOMBI (BMW)", txHeader: "601"))
            out.append(Spec(name: "EGS / АКПП (BMW)", txHeader: "602"))
            out.append(Spec(name: "DME/DDE доп. (BMW дизель)", txHeader: "612"))
            out.append(Spec(name: "Шлюз (BMW)", txHeader: "630"))
            out.append(Spec(name: "CAS / иммобилайзер (BMW)", txHeader: "640"))
            out.append(Spec(name: "DSC / стабилизация (BMW)", txHeader: "6B0"))
            out.append(Spec(name: "FRM / свет, дворники (BMW)", txHeader: "6C0"))
            out.append(Spec(name: "SZL / рулевая колонка (BMW)", txHeader: "610"))
        }
        if isLikelyJaguarLandRover(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Приборка (JLR)", txHeader: "7C4"))
            out.append(Spec(name: "Доп. (JLR)", txHeader: "736"))
            out.append(Spec(name: "Доп. (JLR)", txHeader: "737"))
            out.append(Spec(name: "BCM (JLR)", txHeader: "740"))
            out.append(Spec(name: "ABS доп. (JLR)", txHeader: "764"))
            out.append(Spec(name: "HVAC / климат (JLR)", txHeader: "770"))
            out.append(Spec(name: "EPS / Рулевое (JLR)", txHeader: "7A0"))
            out.append(Spec(name: "Комбинация приборов (JLR)", txHeader: "720"))
        }
        if isLikelyLada(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Комбинация приборов (Lada)", txHeader: "712"))
            out.append(Spec(name: "Комбинация альт. (Lada)", txHeader: "714"))
            out.append(Spec(name: "Комбинация альт. (Lada)", txHeader: "715"))
            out.append(Spec(name: "Комбинация альт. IPC (Lada)", txHeader: "720"))
            out.append(Spec(name: "BCM / кузовной (Lada)", txHeader: "740"))
            out.append(Spec(name: "EPS / электроусилитель (Lada)", txHeader: "760"))
            out.append(Spec(name: "HVAC / климат (Lada)", txHeader: "770"))
            out.append(Spec(name: "ABS доп. (Lada Bosch)", txHeader: "7B2"))
            out.append(Spec(name: "EPS доп. / Mando (Lada)", txHeader: "746"))
        }
        if isLikelyChangan(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Комбинация приборов IPC (Changan)", txHeader: "720"))
            out.append(Spec(name: "BCM / кузовной (Changan)", txHeader: "740"))
            out.append(Spec(name: "HVAC / климат (Changan)", txHeader: "770"))
            out.append(Spec(name: "EPS / Рулевое (Changan)", txHeader: "760"))
            out.append(Spec(name: "Доп. блок (Changan)", txHeader: "714"))
            out.append(Spec(name: "Body / Gateway (Changan)", txHeader: "750"))
            out.append(Spec(name: "TPMS (Changan)", txHeader: "790"))
        }
        if isLikelyChery(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Комбинация приборов IPC (Chery)", txHeader: "720"))
            out.append(Spec(name: "BCM / кузовной (Chery)", txHeader: "740"))
            out.append(Spec(name: "HVAC / климат (Chery)", txHeader: "770"))
            out.append(Spec(name: "EPS / Рулевое (Chery)", txHeader: "760"))
            out.append(Spec(name: "Доп. блок (Chery)", txHeader: "714"))
            out.append(Spec(name: "Body / Gateway (Chery)", txHeader: "750"))
            out.append(Spec(name: "TPMS (Chery)", txHeader: "790"))
        }
        // Китайские платформы Haval/GWM и Geely: типовые адреса 720/740/770/760/714
        if isLikelyHavalGwm(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Комбинация приборов IPC (Haval/GWM)", txHeader: "720"))
            out.append(Spec(name: "BCM / кузовной (Haval/GWM)", txHeader: "740"))
            out.append(Spec(name: "HVAC / климат (Haval/GWM)", txHeader: "770"))
            out.append(Spec(name: "EPS / Рулевое (Haval/GWM)", txHeader: "760"))
            out.append(Spec(name: "Доп. блок (Haval/GWM)", txHeader: "714"))
            out.append(Spec(name: "Body / Gateway (Haval/GWM)", txHeader: "750"))
            out.append(Spec(name: "TPMS (Haval/GWM)", txHeader: "790"))
        }
        if isLikelyGeely(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "Комбинация приборов IPC (Geely)", txHeader: "720"))
            out.append(Spec(name: "BCM / кузовной (Geely)", txHeader: "740"))
            out.append(Spec(name: "HVAC / климат (Geely)", txHeader: "770"))
            out.append(Spec(name: "EPS / Рулевое (Geely)", txHeader: "760"))
            out.append(Spec(name: "Доп. блок (Geely)", txHeader: "714"))
            out.append(Spec(name: "Body / Gateway (Geely)", txHeader: "750"))
            out.append(Spec(name: "TPMS (Geely)", txHeader: "790"))
        }
        if isLikelySubaru(makeLower: m, wmi: wmi) {
            out.append(Spec(name: "BIU / кузовной модуль (Subaru)", txHeader: "744"))
            out.append(Spec(name: "EPS / электроусилитель (Subaru)", txHeader: "746"))
            out.append(Spec(name: "ABS / VDC доп. (Subaru)", txHeader: "747"))
            out.append(Spec(name: "Комбинация приборов (Subaru)", txHeader: "7C0"))
            out.append(Spec(name: "BCM / мультиплекс (Subaru)", txHeader: "740"))
            out.append(Spec(name: "Body / Gateway (Subaru)", txHeader: "750"))
            out.append(Spec(name: "EPS запасной (Subaru)", txHeader: "7A0"))
            out.append(Spec(name: "Автосвет / BCM доп. (Subaru)", txHeader: "760"))
            out.append(Spec(name: "HVAC / климат (Subaru)", txHeader: "770"))
            out.append(Spec(name: "TPMS (Subaru)", txHeader: "780"))
            out.append(Spec(name: "EyeSight / ADAS (Subaru)", txHeader: "787"))
            out.append(Spec(name: "Иммобилайзер / Smart Key (Subaru)", txHeader: "788"))
            out.append(Spec(name: "Parking Assist (Subaru)", txHeader: "792"))
            out.append(Spec(name: "ABS / ESP доп. (Subaru)", txHeader: "7B6"))
        }
        return out
    }

    private static func isLikelyVag(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("volkswagen") || makeLower.contains("audi") ||
            makeLower.contains("skoda") || makeLower.contains("škoda") ||
            makeLower.contains("seat") || makeLower.contains("cupra") ||
            makeLower.contains("porsche") {
            return true
        }
        guard wmi.count >= 3 else { return false }
        if wmi.hasPrefix("WV") || wmi.hasPrefix("WA") { return true }
        return vagWmi.contains(wmi)
    }

    private static func isLikelyToyota(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("toyota") || makeLower.contains("lexus") { return true }
        guard wmi.count >= 3 else { return false }
        return wmi.hasPrefix("JT") || wmi.hasPrefix("4T") || wmi.hasPrefix("5T") ||
            wmi.hasPrefix("2T") || wmi.hasPrefix("MR") || wmi.hasPrefix("SB1")
    }

    private static func isLikelyHonda(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("honda") || makeLower.contains("acura") { return true }
        guard wmi.count >= 3 else { return false }
        return wmi.hasPrefix("JHM") || wmi.hasPrefix("1HG") || wmi.hasPrefix("2HG") ||
            wmi.hasPrefix("3HG") || wmi.hasPrefix("SHH") || wmi.hasPrefix("9C6") ||
            wmi.hasPrefix("LHG") || wmi.hasPrefix("19U") || wmi.hasPrefix("5J6") ||
            wmi.hasPrefix("5FN") || wmi.hasPrefix("MLH")
    }

    private static func isLikelyMercedes(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("mercedes") || makeLower.contains("amg") || makeLower.contains("maybach") {
            return true
        }
        guard wmi.count >= 3 else { return false }
        if wmi.hasPrefix("WDB") || wmi.hasPrefix("WDD") || wmi.hasPrefix("WDC") ||
            wmi.hasPrefix("WDF") || wmi.hasPrefix("WMX") || wmi.hasPrefix("W1K") ||
            wmi.hasPrefix("W1N") || wmi.hasPrefix("W1V") || wmi.hasPrefix("W1W") {
            return true
        }
        return mercedesWmi.contains(wmi)
    }

    private static func isLikelyFord(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("ford") || makeLower.contains("lincoln") || makeLower.contains("mercury") {
            return true
        }
        guard wmi.count >= 3 else { return false }
        if wmi.hasPrefix("1F") || wmi.hasPrefix("2F") || wmi.hasPrefix("3F") { return true }
        if wmi.hasPrefix("NM0") || wmi.hasPrefix("WF0") || wmi.hasPrefix("WF1") { return true }
        return fordWmi.contains(wmi)
    }

    private static func isLikelyBmwMini(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("bmw") || makeLower.contains("mini") { return true }
        guard wmi.count >= 3 else { return false }
        return wmi.hasPrefix("WBA") || wmi.hasPrefix("WBS") || wmi.hasPrefix("WBY") ||
            wmi.hasPrefix("WBX") || wmi.hasPrefix("WMW")
    }

    private static func isLikelyJaguarLandRover(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("jaguar") || makeLower.contains("land rover") ||
            makeLower.contains("range rover") || makeLower.contains("defender") {
            return true
        }
        guard wmi.count >= 3 else { return false }
        return wmi.hasPrefix("SAJ") || wmi.hasPrefix("SAL") || wmi.hasPrefix("SAD") ||
            wmi.hasPrefix("SAR")
    }

    private static func isLikelyPsa(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("peugeot") || makeLower.contains("citroen") ||
            makeLower.contains("citroën") || makeLower.contains("ds ") ||
            makeLower.contains("ds automobiles") || makeLower.contains("opel") ||
            makeLower.contains("vauxhall") {
            return true
        }
        guard wmi.count >= 3 else { return false }
        if wmi.hasPrefix("VF") || wmi.hasPrefix("VR") { return true }
        return psaWmi.contains(wmi)
    }

    private static func isLikelyGm(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("chevrolet") || makeLower.contains("gmc") ||
            makeLower.contains("buick") || makeLower.contains("cadillac") ||
            makeLower.contains("hummer") || makeLower.contains("pontiac") ||
            makeLower.contains("saturn") || makeLower.contains("oldsmobile") ||
            makeLower.contains("holden") {
            return true
        }
        guard wmi.count >= 3 else { return false }
        if wmi.hasPrefix("1G") || wmi.hasPrefix("2G") || wmi.hasPrefix("3G") { return true }
        if wmi.hasPrefix("KL") || wmi.hasPrefix("LSG") { return true }
        return gmWmi.contains(wmi)
    }

    private static func isLikelyHyundaiKia(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("hyundai") || makeLower.contains("kia") || makeLower.contains("genesis") {
            return true
        }
        guard wmi.count >= 3 else { return false }
        if wmi.hasPrefix("KMH") || wmi.hasPrefix("KN") || wmi.hasPrefix("KNA") ||
            wmi.hasPrefix("KNC") || wmi.hasPrefix("KM8") || wmi.hasPrefix("KM9") {
            return true
        }
        return hyundaiKiaWmi.contains(wmi)
    }

    /// Mazda: JM1 (Japan), JM3 (Japan SUV), JMZ (export), JY (moto/minivan).
    /// NB: двухсимвольный `JM` нельзя — конфликтует с Mitsubishi (`JMB`, `JMY`).
    private static func isLikelyMazda(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("mazda") { return true }
        guard wmi.count >= 3 else { return false }
        return wmi.hasPrefix("JM1") || wmi.hasPrefix("JM3") || wmi.hasPrefix("JMZ") ||
            wmi.hasPrefix("JY")
    }

    private static func isLikelyNissan(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("nissan") || makeLower.contains("infiniti") || makeLower.contains("datsun") {
            return true
        }
        guard wmi.count >= 3 else { return false }
        if wmi.hasPrefix("JN") { return true }
        if wmi.hasPrefix("1N") || wmi.hasPrefix("3N") || wmi.hasPrefix("4N") ||
            wmi.hasPrefix("5N") || wmi.hasPrefix("6N") || wmi.hasPrefix("7N") ||
            wmi.hasPrefix("8N") {
            return true
        }
        return nissanWmi.contains(wmi)
    }

    /// JF1/JF2 — Япония; 4S3–4S6 — Subaru of Indiana и др.
    private static func isLikelySubaru(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("subaru") || makeLower.contains("субару") { return true }
        guard wmi.count >= 3 else { return false }
        if wmi.hasPrefix("JF1") || wmi.hasPrefix("JF2") { return true }
        if wmi.hasPrefix("4S3") || wmi.hasPrefix("4S4") || wmi.hasPrefix("4S5") || wmi.hasPrefix("4S6") { return true }
        return false
    }

    private static func isLikelyChangan(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("changan") || makeLower.contains("长安") { return true }
        guard wmi.count >= 3 else { return false }
        if wmi.hasPrefix("LS5") || wmi.hasPrefix("LS4") || wmi.hasPrefix("LS6") || wmi.hasPrefix("LSC") { return true }
        return changanWmi.contains(wmi)
    }

    /// Renault / Dacia / Alpine. Проверяется ДО `isLikelyPsa` — общий VF-префикс.
    private static func isLikelyRenault(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("renault") || makeLower.contains("dacia") ||
            makeLower.contains("alpine") || makeLower.contains("рено") {
            return true
        }
        guard wmi.count >= 3 else { return false }
        if wmi.hasPrefix("VF1") || wmi.hasPrefix("VF2") || wmi.hasPrefix("VF6") ||
            wmi.hasPrefix("VFA") || wmi.hasPrefix("VN1") || wmi.hasPrefix("VNV") ||
            wmi.hasPrefix("X7L") {
            return true
        }
        return renaultWmi.contains(wmi)
    }

    /// Mitsubishi Motors (MMC). JA3/JA4/JA7 (Japan), JMB/JMY (Japan export), MMA-MME (Thailand), Z8T (Russia).
    /// NB: двухсимвольный `JM` нельзя — конфликтует с Mazda (`JMZ`, `JM1`). Используем 3-символьные.
    private static func isLikelyMitsubishi(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("mitsubishi") { return true }
        guard wmi.count >= 3 else { return false }
        if wmi.hasPrefix("JA3") || wmi.hasPrefix("JA4") || wmi.hasPrefix("JA7") { return true }
        if wmi.hasPrefix("JMB") || wmi.hasPrefix("JMY") { return true }
        if wmi.hasPrefix("MMA") || wmi.hasPrefix("MMB") || wmi.hasPrefix("MMC") ||
            wmi.hasPrefix("MMD") || wmi.hasPrefix("MME") || wmi.hasPrefix("MMT") {
            return true
        }
        return mitsubishiWmi.contains(wmi)
    }

    /// Haval / Great Wall Motors (GWM) / Tank / Wey / Ora.
    private static func isLikelyHavalGwm(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("haval") || makeLower.contains("great wall") ||
            makeLower.contains("gwm") || makeLower.contains("长城") ||
            makeLower.contains("wey") || makeLower.contains("tank") || makeLower.contains("ora") {
            return true
        }
        guard wmi.count >= 3 else { return false }
        if wmi.hasPrefix("LGW") { return true }
        return havalGwmWmi.contains(wmi)
    }

    /// Geely / Lynk & Co / Zeekr. Volvo НЕ включён (отдельная архитектура).
    private static func isLikelyGeely(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("geely") || makeLower.contains("吉利") ||
            makeLower.contains("lynk") || makeLower.contains("zeekr") ||
            makeLower.contains("coolray") || makeLower.contains("monjaro") ||
            makeLower.contains("tugella") || makeLower.contains("atlas pro") {
            return true
        }
        guard wmi.count >= 3 else { return false }
        if wmi.hasPrefix("L6T") || wmi.hasPrefix("LB3") || wmi.hasPrefix("LB2") { return true }
        return geelyWmi.contains(wmi)
    }

    private static func isLikelyChery(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("chery") || makeLower.contains("奇瑞") ||
            makeLower.contains("omoda") || makeLower.contains("jaecoo") ||
            makeLower.contains("exeed") || makeLower.contains("jetour") {
            return true
        }
        guard wmi.count >= 3 else { return false }
        if wmi.hasPrefix("LVT") || wmi.hasPrefix("LVV") || wmi.hasPrefix("LVU") ||
            wmi.hasPrefix("LNN") || wmi.hasPrefix("LUR") || wmi.hasPrefix("LVM") {
            return true
        }
        return cheryWmi.contains(wmi)
    }

    private static func isLikelyLada(makeLower: String, wmi: String) -> Bool {
        if makeLower.contains("lada") || makeLower.contains("vaz") ||
            makeLower.contains("автоваз") || makeLower.contains("avtovaz") {
            return true
        }
        guard wmi.count >= 3 else { return false }
        return wmi.hasPrefix("XTA") || wmi.hasPrefix("XTB") || wmi.hasPrefix("XTC") ||
            wmi.hasPrefix("XTH") || ladaWmi.contains(wmi)
    }
}
