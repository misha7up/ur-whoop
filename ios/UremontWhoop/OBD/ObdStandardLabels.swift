import Foundation

/// Подписи стандартных PID Mode 01 (SAE J1979).
enum ObdStandardLabels {

    static func obdStandard1c(_ code: Int) -> String? {
        switch code {
        case 1: return "OBD-II (CARB)"
        case 2: return "OBD (EPA)"
        case 3: return "OBD + OBD-II"
        case 4: return "OBD-I"
        case 5: return "Без OBD"
        case 6: return "EOBD (Европа)"
        case 7: return "EOBD + OBD-II"
        case 8: return "EOBD + OBD"
        case 9: return "EOBD + OBD + OBD-II"
        case 10: return "JOBD (Япония)"
        case 11: return "JOBD + OBD-II"
        case 12: return "JOBD + EOBD"
        case 13: return "JOBD + EOBD + OBD-II"
        case 14: return "Индия (Bharat)"
        case 15: return "Индия + OBD-II"
        case 16: return "HD OBD (тягачи)"
        case 17: return "HD OBD + OBD-II-C"
        case 18: return "HD EOBD-I"
        case 19: return "HD EOBD-I N"
        case 20: return "HD EOBD-I + HD EOBD-II N"
        case 21: return "HD EOBD-II N"
        case 22: return "HD EOBD-II + HD EOBD-II N"
        case 23: return "WOBD-I"
        default: return (1...255).contains(code) ? "OBD (код \(code))" : nil
        }
    }

    static func fuelType51(_ code: Int) -> String? {
        switch code {
        case 0: return nil
        case 1: return "Бензин"
        case 2: return "Метанол"
        case 3: return "Этанол"
        case 4: return "Дизель"
        case 5: return "LPG"
        case 6: return "CNG"
        case 7: return "Пропан"
        case 8: return "Электричество"
        case 9: return "Бензин + газ (bi-fuel)"
        case 10: return "Бензин + метанол"
        case 11: return "Бензин + этанол"
        case 12: return "Бензин + электричество"
        case 13: return "Дизель + электричество"
        case 14: return "Гибрид (бензин/электро)"
        case 15: return "Гибрид (дизель/электро)"
        case 16: return "Гибрид (смешанный)"
        case 17: return "Гибрид (регенеративный)"
        case 18: return "Бензин + CNG"
        case 19: return "Бензин + LPG"
        case 20: return "Бензин + CNG + LPG"
        case 21: return "Гибрид (бензин + электро, внешняя зарядка)"
        case 22: return "Гибрид (дизель + электро, внешняя зарядка)"
        case 23: return "Гибрид (смешанный, внешняя зарядка)"
        default: return (1...255).contains(code) ? "Топливо (код \(code))" : nil
        }
    }
}
