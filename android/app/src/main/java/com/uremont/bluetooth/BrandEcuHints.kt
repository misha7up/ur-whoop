package com.uremont.bluetooth

/**
 * Дополнительные CAN-заголовки (ATSH) для опроса Mode 03 на конкретных марках.
 * Универсальные адреса (7B0/7D0/7E1/7E2/7E3/7E4) задаются здесь же как база — порядок фиксирован.
 *
 * [VehicleBrandGroup] + [classify] — для UDS-проб одометра, выбора веток и др. марочных функций.
 * Классификация эвристическая (WMI + строка марки из [VinWmiTable]); пересечения сведены к порядку проверок.
 *
 * **Порядок [classify] критически важен**: Renault (VF1/VF2/VF6) должен проверяться ДО PSA (VF3/VF7),
 * иначе французские VIN Renault ошибочно попадают в группу PSA из-за общего префикса `VF`.
 */
object BrandEcuHints {

    /**
     * Грубая группа марки / региональной платформы.
     * Покрывает топ-15 марок РФ (по автопарку) + быстрорастущие китайские бренды.
     */
    enum class VehicleBrandGroup {
        OTHER,
        VAG, TOYOTA, HONDA, FORD, MERCEDES,
        RENAULT, PSA, GM, HYUNDAI_KIA, MAZDA, NISSAN,
        MITSUBISHI, SUBARU, BMW_MINI, JAGUAR, LADA,
        CHANGAN, CHERY, HAVAL_GWM, GEELY,
    }

    /**
     * Классификация для марочных расширений (одометр щитка, доп. CAN и т.д.).
     * **Порядок проверок**: Renault ДО PSA (общий VF-префикс), Mitsubishi ДО Nissan (MMC vs Nissan Alliance).
     */
    fun classify(detectedMake: String?, vin: String?): VehicleBrandGroup {
        val m = detectedMake?.lowercase().orEmpty()
        val wmi = vin?.take(3)?.uppercase().orEmpty()
        if (isLikelyVag(m, wmi)) return VehicleBrandGroup.VAG
        if (isLikelyToyota(m, wmi)) return VehicleBrandGroup.TOYOTA
        if (isLikelyHonda(m, wmi)) return VehicleBrandGroup.HONDA
        if (isLikelyFord(m, wmi)) return VehicleBrandGroup.FORD
        if (isLikelyMercedes(m, wmi)) return VehicleBrandGroup.MERCEDES
        if (isLikelyBmwMini(m, wmi)) return VehicleBrandGroup.BMW_MINI
        if (isLikelyJaguarLandRover(m, wmi)) return VehicleBrandGroup.JAGUAR
        if (isLikelyRenault(m, wmi)) return VehicleBrandGroup.RENAULT      // ДО PSA!
        if (isLikelyPsa(m, wmi)) return VehicleBrandGroup.PSA
        if (isLikelyGm(m, wmi)) return VehicleBrandGroup.GM
        if (isLikelyHyundaiKia(m, wmi)) return VehicleBrandGroup.HYUNDAI_KIA
        if (isLikelyMazda(m, wmi)) return VehicleBrandGroup.MAZDA
        if (isLikelyMitsubishi(m, wmi)) return VehicleBrandGroup.MITSUBISHI
        if (isLikelyNissan(m, wmi)) return VehicleBrandGroup.NISSAN
        if (isLikelySubaru(m, wmi)) return VehicleBrandGroup.SUBARU
        if (isLikelyHavalGwm(m, wmi)) return VehicleBrandGroup.HAVAL_GWM
        if (isLikelyGeely(m, wmi)) return VehicleBrandGroup.GEELY
        if (isLikelyLada(m, wmi)) return VehicleBrandGroup.LADA
        if (isLikelyChangan(m, wmi)) return VehicleBrandGroup.CHANGAN
        if (isLikelyChery(m, wmi)) return VehicleBrandGroup.CHERY
        return VehicleBrandGroup.OTHER
    }

    data class Spec(val name: String, val txHeader: String)

    private val universal = listOf(
        Spec("ABS / Тормоза", "7B0"),
        Spec("SRS / Подушки безопасности", "7D0"),
        Spec("Коробка передач (TCM)", "7E1"),
        Spec("Доп. силовой (гибрид / дизель / 2-й ECM)", "7E2"),
        Spec("Раздаточная коробка / 4WD", "7E3"),
        Spec("Кузов (BCM)", "7E4"),
    )

    /**
     * Склеивает марку из VIN ([detectedMake]) и строку из ручного профиля ([manualMakeHint]),
     * чтобы при «Toyota» вручную без WMI всё равно подключались марочные CAN-ID (EPS 7A0 и т.д.).
     */
    fun mergeMakeHints(detectedMake: String?, manualMakeHint: String?): String {
        val parts = listOfNotNull(
            detectedMake?.trim()?.takeIf { it.isNotBlank() },
            manualMakeHint?.trim()?.takeIf { it.isNotBlank() },
        )
        return parts.joinToString(" ").lowercase()
    }

    /**
     * Полный список опроса: базовые ЭБУ (6 шт.) + марочные (без дубликатов `txHeader`).
     * Порядок: сначала универсальные блоки, затем марочные дополнения.
     *
     * @param manualMakeHint поле «марка» из [CarProfile.Manual] (например `Toyota`), если VIN не дал [detectedMake].
     */
    fun ecuProbeList(detectedMake: String?, vin: String?, manualMakeHint: String? = null): List<Spec> {
        val seen = mutableSetOf<String>()
        return buildList {
            for (e in universal + additionalSpecs(detectedMake, vin, manualMakeHint)) {
                val h = e.txHeader.uppercase()
                if (seen.add(h)) add(e)
            }
        }
    }

    /** Адреса вне универсального набора по марке / WMI. */
    fun additionalSpecs(detectedMake: String?, vin: String?, manualMakeHint: String? = null): List<Spec> {
        val m = mergeMakeHints(detectedMake, manualMakeHint)
        val wmi = vin?.take(3)?.uppercase().orEmpty()
        val out = mutableListOf<Spec>()
        if (isLikelyVag(m, wmi)) {
            out += Spec("Шлюз / Gateway (VAG)", "710")
            out += Spec("Комбинация приборов (VAG)", "714")
            out += Spec("ABS / ESP доп. (VAG)", "7B6")
            out += Spec("Рулевое управление (VAG)", "712")
            out += Spec("Тормоза / ESP (VAG)", "713")
            out += Spec("Подушки безопасности (VAG)", "715")
            out += Spec("Рулевая колонка / SWM (VAG)", "716")
            out += Spec("Стояночный тормоз / EPB (VAG)", "752")
            out += Spec("Park Assist (VAG)", "70A")
            out += Spec("Lane Assist / камера (VAG)", "750")
            out += Spec("ACC / адаптив. круиз (VAG)", "757")
            out += Spec("TPMS / давление шин (VAG)", "765")
            out += Spec("HVAC / Климатроник (VAG)", "770")
        }
        if (isLikelyToyota(m, wmi)) {
            out += Spec("Body / Gateway (Toyota)", "750")
            out += Spec("Комбинация приборов (Toyota)", "7C0")
            out += Spec("EPS / Рулевое (Toyota)", "7A0")
            out += Spec("Auto-Leveling фар (Toyota)", "740")
            out += Spec("SRS / Ремни (Toyota)", "780")
            out += Spec("Smart Key / иммобилайзер (Toyota)", "788")
            out += Spec("TPMS (Toyota)", "790")
            out += Spec("Parking Assist / Sonar (Toyota)", "792")
            out += Spec("HVAC / кондиционер (Toyota)", "744")
            out += Spec("Pre-Collision / ACC (Toyota)", "7A8")
        }
        if (isLikelyHonda(m, wmi)) {
            out += Spec("Комбинация приборов (Honda)", "760")
            out += Spec("EPS / Рулевое (Honda)", "7A0")
            out += Spec("Body / MICU (Honda)", "7C0")
            out += Spec("HVAC / Климат (Honda)", "770")
            out += Spec("VSA / стабилизация (Honda)", "730")
            out += Spec("Honda Sensing / ADAS (Honda)", "750")
            out += Spec("TPMS / давление шин (Honda)", "780")
        }
        if (isLikelyFord(m, wmi)) {
            out += Spec("Комбинация приборов IPC (Ford/Lincoln)", "720")
            out += Spec("КПП / TCM (Ford, запасной 743)", "743")
            out += Spec("Доп. модуль APIM (Ford)", "726")
            out += Spec("Доп. модуль (Ford)", "732")
            out += Spec("BCM доп. (Ford)", "724")
            out += Spec("RCM / SRS доп. (Ford)", "736")
            out += Spec("Parking Aid / PDC (Ford)", "760")
            out += Spec("ABS / ESP доп. (Ford)", "764")
            out += Spec("HVAC / климат (Ford)", "770")
            out += Spec("EPS / Рулевое (Ford)", "7A0")
            out += Spec("ACC / адаптив. круиз (Ford)", "7A4")
        }
        if (isLikelyMercedes(m, wmi)) {
            out += Spec("Комбинация приборов IC (Mercedes)", "720")
            out += Spec("SAM передний (Mercedes)", "740")
            out += Spec("SAM задний (Mercedes)", "741")
            out += Spec("EZS / замок зажигания (Mercedes)", "743")
            out += Spec("EPS / Рулевое (Mercedes)", "7A0")
            out += Spec("ESP доп. (Mercedes)", "7D2")
            out += Spec("Parktronic / PDC (Mercedes)", "760")
            out += Spec("HVAC / климат (Mercedes)", "770")
            out += Spec("Рулевая колонка (Mercedes)", "716")
            out += Spec("Distronic / ACC (Mercedes)", "74A")
        }
        // Renault: щиток 770, кузовной UCH 742, доп. модули — адреса не пересекаются с PSA
        if (isLikelyRenault(m, wmi)) {
            out += Spec("Щиток / TDB (Renault)", "770")
            out += Spec("UCH / кузовной (Renault)", "742")
            out += Spec("EPS / Рулевое (Renault)", "760")
            out += Spec("HVAC / Климат (Renault)", "771")
            out += Spec("Parking доп. (Renault)", "762")
            out += Spec("ABS / ESP доп. (Renault)", "764")
            out += Spec("Body / Gateway (Renault)", "750")
        }
        if (isLikelyPsa(m, wmi)) {
            out += Spec("Комбинация / BSI (PSA)", "752")
            out += Spec("Доп. блок (PSA)", "753")
            out += Spec("Кузов / BSI (PSA)", "740")
            out += Spec("Доп. (PSA)", "742")
            out += Spec("ABS / ESP (PSA)", "764")
            out += Spec("EPS / Рулевое (PSA)", "760")
            out += Spec("HVAC / климат (PSA)", "770")
            out += Spec("Body / BSM (PSA)", "750")
        }
        if (isLikelyGm(m, wmi)) {
            out += Spec("IPC / приборка (GM)", "724")
            out += Spec("Доп. модуль (GM)", "728")
            out += Spec("Доп. модуль (GM)", "244")
            out += Spec("SDM / SRS доп. (GM)", "7D2")
            out += Spec("Park Assist / PDC (GM)", "7A6")
            out += Spec("Комбинация вторичная (GM)", "7C0")
            out += Spec("HVAC / климат (GM)", "744")
        }
        if (isLikelyHyundaiKia(m, wmi)) {
            out += Spec("Комбинация (Hyundai/Kia)", "7A0")
            out += Spec("Доп. блок (Hyundai/Kia)", "7A2")
            out += Spec("TPMS / давление шин (Hyundai/Kia)", "7A6")
            out += Spec("Кластер / BCM (Hyundai/Kia)", "770")
            out += Spec("Доп. (Hyundai/Kia)", "771")
            out += Spec("Smart Key (Hyundai/Kia)", "794")
            out += Spec("Доп. (Hyundai/Kia)", "7C6")
            out += Spec("EPB / стояночный тормоз (Hyundai/Kia)", "7D4")
            out += Spec("ADAS / камера (Hyundai/Kia)", "7C0")
        }
        if (isLikelyMazda(m, wmi)) {
            out += Spec("Комбинация (Mazda)", "720")
            out += Spec("Доп. (Mazda)", "730")
            out += Spec("Доп. (Mazda)", "731")
            out += Spec("EPS / Рулевое (Mazda)", "7A0")
            out += Spec("DSC / ABS доп. (Mazda)", "764")
            out += Spec("BCM доп. (Mazda)", "742")
            out += Spec("PDC / парковка (Mazda)", "760")
            out += Spec("HVAC / климат (Mazda)", "770")
        }
        // Mitsubishi: gateway 750, комбинация 7C0, EPS 760 — ближе к Toyota по архитектуре CAN
        if (isLikelyMitsubishi(m, wmi)) {
            out += Spec("Body / Gateway (Mitsubishi)", "750")
            out += Spec("Комбинация приборов (Mitsubishi)", "7C0")
            out += Spec("EPS / Рулевое (Mitsubishi)", "760")
            out += Spec("HVAC / климат (Mitsubishi)", "770")
            out += Spec("TPMS (Mitsubishi)", "790")
            out += Spec("BCM / головной свет (Mitsubishi)", "740")
            out += Spec("EPS / Рулевое (Mitsubishi)", "7A0")
        }
        if (isLikelyNissan(m, wmi)) {
            out += Spec("Комбинация приборов (Nissan/Infiniti)", "743")
            out += Spec("Доп. комбинация (Nissan)", "744")
            out += Spec("BCM / IPDM (Nissan)", "740")
            out += Spec("EPS / Рулевое (Nissan)", "746")
            out += Spec("ABS / VDC доп. (Nissan)", "747")
            out += Spec("Body / IPDM доп. (Nissan)", "760")
            out += Spec("HVAC / Климат (Nissan)", "765")
            out += Spec("TPMS (Nissan)", "772")
            out += Spec("ACC / радар (Nissan)", "7B2")
            out += Spec("Доп. (Nissan)", "793")
            out += Spec("Body / BCM доп. (Nissan)", "750")
            out += Spec("Smart Key (Nissan)", "788")
        }
        if (isLikelyBmwMini(m, wmi)) {
            out += Spec("KOMBI / приборка (BMW)", "600")
            out += Spec("Доп. KOMBI (BMW)", "601")
            out += Spec("EGS / АКПП (BMW)", "602")
            out += Spec("DME/DDE доп. (BMW дизель)", "612")
            out += Spec("Шлюз (BMW)", "630")
            out += Spec("CAS / иммобилайзер (BMW)", "640")
            out += Spec("DSC / стабилизация (BMW)", "6B0")
            out += Spec("FRM / свет, дворники (BMW)", "6C0")
            out += Spec("SZL / рулевая колонка (BMW)", "610")
        }
        if (isLikelyJaguarLandRover(m, wmi)) {
            out += Spec("Приборка (JLR)", "7C4")
            out += Spec("Доп. (JLR)", "736")
            out += Spec("Доп. (JLR)", "737")
            out += Spec("BCM (JLR)", "740")
            out += Spec("ABS доп. (JLR)", "764")
            out += Spec("HVAC / климат (JLR)", "770")
            out += Spec("EPS / Рулевое (JLR)", "7A0")
            out += Spec("Комбинация приборов (JLR)", "720")
        }
        if (isLikelyLada(m, wmi)) {
            out += Spec("Комбинация приборов (Lada)", "712")
            out += Spec("Комбинация альт. (Lada)", "714")
            out += Spec("Комбинация альт. (Lada)", "715")
            out += Spec("Комбинация альт. IPC (Lada)", "720")
            out += Spec("BCM / кузовной (Lada)", "740")
            out += Spec("EPS / электроусилитель (Lada)", "760")
            out += Spec("HVAC / климат (Lada)", "770")
            out += Spec("ABS доп. (Lada Bosch)", "7B2")
            out += Spec("EPS доп. / Mando (Lada)", "746")
        }
        if (isLikelyChangan(m, wmi)) {
            out += Spec("Комбинация приборов IPC (Changan)", "720")
            out += Spec("BCM / кузовной (Changan)", "740")
            out += Spec("HVAC / климат (Changan)", "770")
            out += Spec("EPS / Рулевое (Changan)", "760")
            out += Spec("Доп. блок (Changan)", "714")
            out += Spec("Body / Gateway (Changan)", "750")
            out += Spec("TPMS (Changan)", "790")
        }
        if (isLikelyChery(m, wmi)) {
            out += Spec("Комбинация приборов IPC (Chery)", "720")
            out += Spec("BCM / кузовной (Chery)", "740")
            out += Spec("HVAC / климат (Chery)", "770")
            out += Spec("EPS / Рулевое (Chery)", "760")
            out += Spec("Доп. блок (Chery)", "714")
            out += Spec("Body / Gateway (Chery)", "750")
            out += Spec("TPMS (Chery)", "790")
        }
        // Китайские платформы Haval/GWM и Geely: типовые адреса 720/740/770/760/714
        if (isLikelyHavalGwm(m, wmi)) {
            out += Spec("Комбинация приборов IPC (Haval/GWM)", "720")
            out += Spec("BCM / кузовной (Haval/GWM)", "740")
            out += Spec("HVAC / климат (Haval/GWM)", "770")
            out += Spec("EPS / Рулевое (Haval/GWM)", "760")
            out += Spec("Доп. блок (Haval/GWM)", "714")
            out += Spec("Body / Gateway (Haval/GWM)", "750")
            out += Spec("TPMS (Haval/GWM)", "790")
        }
        if (isLikelyGeely(m, wmi)) {
            out += Spec("Комбинация приборов IPC (Geely)", "720")
            out += Spec("BCM / кузовной (Geely)", "740")
            out += Spec("HVAC / климат (Geely)", "770")
            out += Spec("EPS / Рулевое (Geely)", "760")
            out += Spec("Доп. блок (Geely)", "714")
            out += Spec("Body / Gateway (Geely)", "750")
            out += Spec("TPMS (Geely)", "790")
        }
        // Subaru: BIU 744, EPS 746, ABS/VDC доп. 747, щиток 7C0 — типовые адреса SSM/CAN (ISO 15765)
        if (isLikelySubaru(m, wmi)) {
            out += Spec("BIU / кузовной модуль (Subaru)", "744")
            out += Spec("EPS / электроусилитель (Subaru)", "746")
            out += Spec("ABS / VDC доп. (Subaru)", "747")
            out += Spec("Комбинация приборов (Subaru)", "7C0")
            out += Spec("BCM / мультиплекс (Subaru)", "740")
            out += Spec("Body / Gateway (Subaru)", "750")
            out += Spec("EPS запасной (Subaru)", "7A0")
            out += Spec("Автосвет / BCM доп. (Subaru)", "760")
            out += Spec("HVAC / климат (Subaru)", "770")
            out += Spec("TPMS (Subaru)", "780")
            out += Spec("EyeSight / ADAS (Subaru)", "787")
            out += Spec("Иммобилайзер / Smart Key (Subaru)", "788")
            out += Spec("Parking Assist (Subaru)", "792")
            out += Spec("ABS / ESP доп. (Subaru)", "7B6")
        }
        return out
    }

    private fun isLikelyVag(makeLower: String, wmi: String): Boolean {
        if (
            makeLower.contains("volkswagen") || makeLower.contains("audi") ||
            makeLower.contains("skoda") || makeLower.contains("škoda") ||
            makeLower.contains("seat") || makeLower.contains("cupra") ||
            makeLower.contains("porsche")
        ) {
            return true
        }
        if (wmi.length < 3) return false
        if (wmi.startsWith("WV") || wmi.startsWith("WA")) return true
        return wmi in VAG_WMI
    }

    private fun isLikelyToyota(makeLower: String, wmi: String): Boolean {
        if (makeLower.contains("toyota") || makeLower.contains("lexus")) return true
        if (wmi.length < 3) return false
        return wmi.startsWith("JT") || wmi.startsWith("4T") || wmi.startsWith("5T") ||
            wmi.startsWith("2T") || wmi.startsWith("MR") || wmi.startsWith("SB1")
    }

    private fun isLikelyHonda(makeLower: String, wmi: String): Boolean {
        if (makeLower.contains("honda") || makeLower.contains("acura")) return true
        if (wmi.length < 3) return false
        return wmi.startsWith("JHM") || wmi.startsWith("1HG") || wmi.startsWith("2HG") ||
            wmi.startsWith("3HG") || wmi.startsWith("SHH") || wmi.startsWith("9C6") ||
            wmi.startsWith("LHG") || wmi.startsWith("19U") || wmi.startsWith("5J6") ||
            wmi.startsWith("5FN") || wmi.startsWith("MLH")
    }

    private fun isLikelyMercedes(makeLower: String, wmi: String): Boolean {
        if (
            makeLower.contains("mercedes") || makeLower.contains("amg") ||
            makeLower.contains("maybach")
        ) {
            return true
        }
        if (wmi.length < 3) return false
        if (wmi.startsWith("WDB") || wmi.startsWith("WDD") || wmi.startsWith("WDC") ||
            wmi.startsWith("WDF") || wmi.startsWith("WMX") || wmi.startsWith("W1K") ||
            wmi.startsWith("W1N") || wmi.startsWith("W1V") || wmi.startsWith("W1W")
        ) return true
        return wmi in MERCEDES_WMI
    }

    private fun isLikelyFord(makeLower: String, wmi: String): Boolean {
        if (
            makeLower.contains("ford") || makeLower.contains("lincoln") ||
            makeLower.contains("mercury")
        ) {
            return true
        }
        if (wmi.length < 3) return false
        if (wmi.startsWith("1F") || wmi.startsWith("2F") || wmi.startsWith("3F")) return true
        if (wmi.startsWith("NM0") || wmi.startsWith("WF0") || wmi.startsWith("WF1")) return true
        return wmi in FORD_WMI
    }

    private fun isLikelyBmwMini(makeLower: String, wmi: String): Boolean {
        if (makeLower.contains("bmw") || makeLower.contains("mini")) return true
        if (wmi.length < 3) return false
        return wmi.startsWith("WBA") || wmi.startsWith("WBS") || wmi.startsWith("WBY") ||
            wmi.startsWith("WBX") || wmi.startsWith("WMW")
    }

    private fun isLikelyJaguarLandRover(makeLower: String, wmi: String): Boolean {
        if (
            makeLower.contains("jaguar") || makeLower.contains("land rover") ||
            makeLower.contains("range rover") || makeLower.contains("defender")
        ) {
            return true
        }
        if (wmi.length < 3) return false
        return wmi.startsWith("SAJ") || wmi.startsWith("SAL") || wmi.startsWith("SAD") ||
            wmi.startsWith("SAR")
    }

    private fun isLikelyPsa(makeLower: String, wmi: String): Boolean {
        if (
            makeLower.contains("peugeot") || makeLower.contains("citroen") ||
            makeLower.contains("citroën") || makeLower.contains("ds ") ||
            makeLower.contains("ds automobiles") || makeLower.contains("opel") ||
            makeLower.contains("vauxhall")
        ) {
            return true
        }
        if (wmi.length < 3) return false
        if (wmi.startsWith("VF") || wmi.startsWith("VR")) return true
        return wmi in PSA_WMI
    }

    private fun isLikelyGm(makeLower: String, wmi: String): Boolean {
        if (
            makeLower.contains("chevrolet") || makeLower.contains("gmc") ||
            makeLower.contains("buick") || makeLower.contains("cadillac") ||
            makeLower.contains("hummer") || makeLower.contains("pontiac") ||
            makeLower.contains("saturn") || makeLower.contains("oldsmobile") ||
            makeLower.contains("holden")
        ) {
            return true
        }
        if (wmi.length < 3) return false
        if (wmi.startsWith("1G") || wmi.startsWith("2G") || wmi.startsWith("3G")) return true
        if (wmi.startsWith("KL") || wmi.startsWith("LSG")) return true
        return wmi in GM_WMI
    }

    private fun isLikelyHyundaiKia(makeLower: String, wmi: String): Boolean {
        if (
            makeLower.contains("hyundai") || makeLower.contains("kia") ||
            makeLower.contains("genesis")
        ) {
            return true
        }
        if (wmi.length < 3) return false
        if (wmi.startsWith("KMH") || wmi.startsWith("KN") || wmi.startsWith("KNA") ||
            wmi.startsWith("KNC") || wmi.startsWith("KM8") || wmi.startsWith("KM9")
        ) {
            return true
        }
        return wmi in HYUNDAI_KIA_WMI
    }

    /** Mazda: JM1 (Japan), JM3 (Japan SUV), JMZ (export), JY (moto/minivan).
     *  NB: двухсимвольный `JM` нельзя — конфликтует с Mitsubishi (`JMB`, `JMY`). */
    private fun isLikelyMazda(makeLower: String, wmi: String): Boolean {
        if (makeLower.contains("mazda")) return true
        if (wmi.length < 3) return false
        return wmi.startsWith("JM1") || wmi.startsWith("JM3") || wmi.startsWith("JMZ") ||
            wmi.startsWith("JY")
    }

    private fun isLikelyNissan(makeLower: String, wmi: String): Boolean {
        if (
            makeLower.contains("nissan") || makeLower.contains("infiniti") ||
            makeLower.contains("datsun")
        ) {
            return true
        }
        if (wmi.length < 3) return false
        if (wmi.startsWith("JN")) return true
        if (
            wmi.startsWith("1N") || wmi.startsWith("3N") || wmi.startsWith("4N") ||
            wmi.startsWith("5N") || wmi.startsWith("6N") || wmi.startsWith("7N") ||
            wmi.startsWith("8N")
        ) {
            return true
        }
        return wmi in NISSAN_WMI
    }

    /** Subaru: JF1/JF2 (Япония), 4S3/4S4/4S5/4S6 (Subaru of Indiana и др.). */
    private fun isLikelySubaru(makeLower: String, wmi: String): Boolean {
        if (makeLower.contains("subaru") || makeLower.contains("субару")) return true
        if (wmi.length < 3) return false
        if (wmi.startsWith("JF1") || wmi.startsWith("JF2")) return true
        if (wmi.startsWith("4S3") || wmi.startsWith("4S4") || wmi.startsWith("4S5") || wmi.startsWith("4S6")) return true
        return false
    }

    private fun isLikelyChangan(makeLower: String, wmi: String): Boolean {
        if (makeLower.contains("changan") || makeLower.contains("长安")) return true
        if (wmi.length < 3) return false
        if (wmi.startsWith("LS5") || wmi.startsWith("LS4") || wmi.startsWith("LS6") || wmi.startsWith("LSC")) return true
        return wmi in CHANGAN_WMI
    }

    /**
     * Renault / Dacia / Alpine. ВАЖНО: проверяется ДО [isLikelyPsa] в [classify],
     * т.к. WMI VF1/VF2/VF6 совпадают с общим PSA-префиксом `VF`.
     * Diagnostically Renault ≠ PSA: свои адреса UCH (742), щиток (770).
     */
    private fun isLikelyRenault(makeLower: String, wmi: String): Boolean {
        if (
            makeLower.contains("renault") || makeLower.contains("dacia") ||
            makeLower.contains("alpine") || makeLower.contains("рено")
        ) {
            return true
        }
        if (wmi.length < 3) return false
        if (wmi.startsWith("VF1") || wmi.startsWith("VF2") || wmi.startsWith("VF6") ||
            wmi.startsWith("VFA") || wmi.startsWith("VN1") || wmi.startsWith("VNV") ||
            wmi.startsWith("X7L")
        ) {
            return true
        }
        return wmi in RENAULT_WMI
    }

    /** Mitsubishi Motors (MMC). WMI: JA3/JA4/JA7 (Japan), JMB/JMY/JMZ-MMC (Japan export), MMA-MME (Thailand), Z8T (Russia).
     *  NB: двухсимвольный `JM` нельзя — конфликтует с Mazda (`JMZ`, `JM1`). Используем 3-символьные. */
    private fun isLikelyMitsubishi(makeLower: String, wmi: String): Boolean {
        if (makeLower.contains("mitsubishi")) return true
        if (wmi.length < 3) return false
        if (wmi.startsWith("JA3") || wmi.startsWith("JA4") || wmi.startsWith("JA7")) return true
        if (wmi.startsWith("JMB") || wmi.startsWith("JMY")) return true
        if (wmi.startsWith("MMA") || wmi.startsWith("MMB") || wmi.startsWith("MMC") ||
            wmi.startsWith("MMD") || wmi.startsWith("MME") || wmi.startsWith("MMT")
        ) {
            return true
        }
        return wmi in MITSUBISHI_WMI
    }

    /** Haval / Great Wall Motors (GWM) / Tank / Wey / Ora / Poer. */
    private fun isLikelyHavalGwm(makeLower: String, wmi: String): Boolean {
        if (
            makeLower.contains("haval") || makeLower.contains("great wall") ||
            makeLower.contains("gwm") || makeLower.contains("长城") ||
            makeLower.contains("wey") || makeLower.contains("tank") || makeLower.contains("ora")
        ) {
            return true
        }
        if (wmi.length < 3) return false
        if (wmi.startsWith("LGW")) return true
        return wmi in HAVAL_GWM_WMI
    }

    /** Geely / Lynk & Co / Zeekr / Coolray / Atlas / Monjaro. Volvo НЕ включён (отдельная архитектура). */
    private fun isLikelyGeely(makeLower: String, wmi: String): Boolean {
        if (
            makeLower.contains("geely") || makeLower.contains("吉利") ||
            makeLower.contains("lynk") || makeLower.contains("zeekr") ||
            makeLower.contains("coolray") || makeLower.contains("monjaro") ||
            makeLower.contains("tugella") || makeLower.contains("atlas pro")
        ) {
            return true
        }
        if (wmi.length < 3) return false
        if (wmi.startsWith("L6T") || wmi.startsWith("LB3") || wmi.startsWith("LB2")) return true
        return wmi in GEELY_WMI
    }

    private fun isLikelyChery(makeLower: String, wmi: String): Boolean {
        if (
            makeLower.contains("chery") || makeLower.contains("奇瑞") ||
            makeLower.contains("omoda") || makeLower.contains("jaecoo") ||
            makeLower.contains("exeed") || makeLower.contains("jetour")
        ) {
            return true
        }
        if (wmi.length < 3) return false
        if (wmi.startsWith("LVT") || wmi.startsWith("LVV") || wmi.startsWith("LVU") ||
            wmi.startsWith("LNN") || wmi.startsWith("LUR") || wmi.startsWith("LVM")
        ) {
            return true
        }
        return wmi in CHERY_WMI
    }

    private fun isLikelyLada(makeLower: String, wmi: String): Boolean {
        if (
            makeLower.contains("lada") || makeLower.contains("vaz") ||
            makeLower.contains("автоваз") || makeLower.contains("avtovaz")
        ) {
            return true
        }
        if (wmi.length < 3) return false
        return wmi.startsWith("XTA") || wmi.startsWith("XTB") || wmi.startsWith("XTC") ||
            wmi.startsWith("XTH") || wmi in LADA_WMI
    }

    private val FORD_WMI = setOf(
        "WF0", "WF1", "WFO", "XLC", "MNA", "MPB", "LVS", "LVR",
        "5LM", "1LN", "2LM", "X9F",
        "NM0", "PEF", "MAJ", "6FP", "94D", "TW2",
    )

    private val VAG_WMI = setOf(
        "TRU", "XW8", "TMB", "TMA", "TMP", "VSS", "1VW", "3VW", "9BW", "8AW",
    )

    // UU1 = Dacia (Renault Group), перенесён в RENAULT_WMI
    private val PSA_WMI = setOf(
        "W0L", "W0V", "UU2", "U5Y", "U6Y", "VR2", "VR3", "VR7",
    )

    private val GM_WMI = setOf(
        "LGX", "LGB", "LGC", "LGH", "LGR",
    )

    private val HYUNDAI_KIA_WMI = setOf(
        "MAL", "MXK", "NLH",
    )

    // KNM = Renault Korea (бывш. Samsung Motors), перенесён в RENAULT_WMI
    private val NISSAN_WMI = setOf(
        "MDH", "MNB", "MNT", "SJN", "VSK",
        "JNK", "RN8",
    )

    private val LADA_WMI = setOf(
        "XTF", "XTK", "X1L", "XTT", "XTD", "XCL",
    )

    private val CHANGAN_WMI = setOf(
        "LPA",
    )

    private val CHERY_WMI = setOf(
        "98R", "9UJ", "PRH", "HJR",
    )

    // Renault: UU1 (Dacia Romania), KNM (Renault Korea), 8A1/8G1 (Аргентина),
    // VS5/VSY (Испания), Y9Z (Украина), 93Y (Бразилия), ADR (Румыния), MEE (Индия)
    private val RENAULT_WMI = setOf(
        "UU1", "KNM", "8A1", "8G1", "93Y", "ADR", "MEE", "SDG",
        "VS5", "VSY", "Y9Z", "VG6", "VG7", "NM1",
    )

    // Mitsubishi: Z8T (Россия Калуга), 6MM (Австралия), 4A3/4A4 (USA), XMC/XMD (РФ)
    private val MITSUBISHI_WMI = setOf(
        "Z8T", "6MM", "4A3", "4A4", "XMC", "XMD", "XNB", "ML3", "KPH",
    )

    // Haval / Great Wall: 8L4 (Бразилия), MNU (Индия), X9X (Болгария), XZG (Россия Тула)
    private val HAVAL_GWM_WMI = setOf(
        "8L4", "MNU", "X9X", "XZG",
    )

    // Geely: L10, LLV, LMP (Китай), Y4K/Y7W (Беларусь)
    private val GEELY_WMI = setOf(
        "L10", "LLV", "LMP", "Y4K", "Y7W",
    )

    private val MERCEDES_WMI = setOf(
        "4JG", "55S", "WD3", "WD4", "WDA", "WDZ",
        "VSA", "9BM", "ADB", "MBR", "NMB", "RLM",
    )
}
