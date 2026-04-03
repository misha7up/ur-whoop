package com.uremont.bluetooth

/**
 * Человекочитаемые подписи для стандартных PID Mode 01 (SAE J1979 / ISO 15031).
 */
object ObdStandardLabels {

    /** PID 0x1C — тип требований OBD / регион. */
    fun obdStandard1c(code: Int): String? = when (code) {
        1 -> "OBD-II (CARB)"
        2 -> "OBD (EPA)"
        3 -> "OBD + OBD-II"
        4 -> "OBD-I"
        5 -> "Без OBD"
        6 -> "EOBD (Европа)"
        7 -> "EOBD + OBD-II"
        8 -> "EOBD + OBD"
        9 -> "EOBD + OBD + OBD-II"
        10 -> "JOBD (Япония)"
        11 -> "JOBD + OBD-II"
        12 -> "JOBD + EOBD"
        13 -> "JOBD + EOBD + OBD-II"
        14 -> "Индия (Bharat)"
        15 -> "Индия + OBD-II"
        16 -> "HD OBD (тягачи)"
        17 -> "HD OBD + OBD-II-C"
        18 -> "HD EOBD-I"
        19 -> "HD EOBD-I N"
        20 -> "HD EOBD-I + HD EOBD-II N"
        21 -> "HD EOBD-II N"
        22 -> "HD EOBD-II + HD EOBD-II N"
        23 -> "WOBD-I"
        else -> if (code in 24..255) "OBD (код $code)" else null
    }

    /** PID 0x51 — тип топлива двигателя. */
    fun fuelType51(code: Int): String? = when (code) {
        0 -> null
        1 -> "Бензин"
        2 -> "Метанол"
        3 -> "Этанол"
        4 -> "Дизель"
        5 -> "LPG"
        6 -> "CNG"
        7 -> "Пропан"
        8 -> "Электричество"
        9 -> "Бензин + газ (би-fuel)"
        10 -> "Бензин + метанол"
        11 -> "Бензин + этанол"
        12 -> "Бензин + электричество"
        13 -> "Дизель + электричество"
        14 -> "Гибрид (бензин/электро)"
        15 -> "Гибрид (дизель/электро)"
        16 -> "Гибрид (смешанный)"
        17 -> "Гибрид (регенеративный)"
        18 -> "Бензин + CNG"
        19 -> "Бензин + LPG"
        20 -> "Бензин + CNG + LPG"
        21 -> "Гибрид (бензин + электро, внешняя зарядка)"
        22 -> "Гибрид (дизель + электро, внешняя зарядка)"
        23 -> "Гибрид (смешанный, внешняя зарядка)"
        else -> if (code in 1..255) "Топливо (код $code)" else null
    }
}
