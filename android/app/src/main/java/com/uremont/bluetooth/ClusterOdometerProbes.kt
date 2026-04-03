package com.uremont.bluetooth

/**
 * Экспериментальное чтение одометра с комбинации приборов через **UDS ReadDataByIdentifier (0x22)**
 * на CAN (команды ELM327: `ATSH` + hex payload без пробелов).
 *
 * [preludeHex]: опциональные кадры до `22` (напр. `1003` — DiagnosticSessionControl extended);
 * часть ЭБУ (BMW, PSA, …) чаще отвечает на `22` только после расширенной сессии.
 *
 * **Не реализовано здесь:** SecurityAccess (0x27) и WriteDataByIdentifier (0x2E) — 27 требует OEM seed/key,
 * 2E — запись в ЭБУ, только с явным согласием пользователя вне этого сценария.
 *
 * DID и адреса — ориентиры из открытых источников; сверять с щитком.
 */
object ClusterOdometerProbes {

    data class Probe(
        /** Метка для лога / UI. */
        val groupLabel: String,
        val txHeader: String,
        /** Hex без пробелов, например `222010` = 22 20 10. */
        val requestHex: String,
        /** Ожидаемый префикс положительного ответа `62` + DID, в верхнем регистре. */
        val positiveMarker: String,
        /** UDS-кадры до основного запроса (например `1003`). */
        val preludeHex: List<String> = emptyList(),
    )

    @Suppress("CyclomaticComplexMethod")
    fun probesFor(group: BrandEcuHints.VehicleBrandGroup): List<Probe> = when (group) {
        BrandEcuHints.VehicleBrandGroup.VAG -> listOf(
            Probe("VAG", "714", "222010", "622010"),
            Probe("VAG", "714", "22291A", "62291A"),
            Probe("VAG", "714", "222014", "622014"),
            Probe("VAG", "714", "222003", "622003"),
            Probe("VAG", "710", "222010", "622010"),
            Probe("VAG", "710", "22291A", "62291A"),
            Probe("VAG", "710", "222003", "622003"),
        )
        BrandEcuHints.VehicleBrandGroup.TOYOTA -> listOf(
            Probe("Toyota", "750", "222182", "622182"),
            Probe("Toyota", "750", "222101", "622101"),
            Probe("Toyota", "750", "222100", "622100"),
            Probe("Toyota", "7C0", "222182", "622182"),
            Probe("Toyota", "7C0", "222101", "622101"),
            Probe("Toyota", "7C0", "222100", "622100"),
            Probe("Toyota", "7C0", "222903", "622903"),
            Probe("Toyota", "7B5", "222182", "622182"),
            Probe("Toyota", "710", "222182", "622182"),
            Probe("Toyota", "750", "222903", "622903"),
        )
        BrandEcuHints.VehicleBrandGroup.HONDA -> listOf(
            Probe("Honda", "760", "223101", "623101"),
            Probe("Honda", "760", "223102", "623102"),
            Probe("Honda", "760", "2200B4", "6200B4"),
            Probe("Honda", "760", "222001", "622001"),
            Probe("Honda", "7C0", "223101", "623101"),
            Probe("Honda", "7C0", "2200B4", "6200B4"),
            Probe("Honda", "714", "223101", "623101"),
            Probe("Honda", "714", "223102", "623102"),
            Probe("Honda", "718", "223101", "623101"),
            Probe("Honda", "771", "223101", "623101"),
            Probe("Honda", "714", "22B002", "62B002"),
        )
        BrandEcuHints.VehicleBrandGroup.FORD -> listOf(
            Probe("Ford", "720", "22D111", "62D111"),
            Probe("Ford", "720", "22DD01", "62DD01"),
            Probe("Ford", "720", "22D028", "62D028"),
            Probe("Ford", "720", "224040", "624040"),
            Probe("Ford", "720", "22DE00", "62DE00"),
            Probe("Ford", "720", "22D108", "62D108"),
            Probe("Ford", "720", "221704", "621704"),
            Probe("Ford", "726", "22D111", "62D111"),
            Probe("Ford", "726", "22DD01", "62DD01"),
            Probe("Ford", "732", "22D111", "62D111"),
            Probe("Ford", "732", "22DD01", "62DD01"),
            Probe("Ford", "736", "22D111", "62D111"),
            Probe("Ford", "764", "22D111", "62D111"),
        )
        BrandEcuHints.VehicleBrandGroup.PSA -> listOf(
            Probe("PSA", "752", "222010", "622010", preludeHex = listOf("1003")),
            Probe("PSA", "752", "222101", "622101", preludeHex = listOf("1003")),
            Probe("PSA", "752", "222014", "622014", preludeHex = listOf("1003")),
            Probe("PSA", "753", "222010", "622010", preludeHex = listOf("1003")),
            Probe("PSA", "740", "222010", "622010"),
            Probe("PSA", "742", "222010", "622010"),
        )
        BrandEcuHints.VehicleBrandGroup.GM -> listOf(
            Probe("GM", "724", "22D111", "62D111"),
            Probe("GM", "724", "22D109", "62D109"),
            Probe("GM", "724", "22D028", "62D028"),
            Probe("GM", "728", "22D111", "62D111"),
            Probe("GM", "244", "22D111", "62D111"),
        )
        BrandEcuHints.VehicleBrandGroup.HYUNDAI_KIA -> listOf(
            Probe("HyundaiKia", "7A0", "22B002", "62B002", preludeHex = listOf("1003")),
            Probe("HyundaiKia", "770", "22B958", "62B958", preludeHex = listOf("1003")),
            Probe("HyundaiKia", "770", "22B002", "62B002", preludeHex = listOf("1003")),
            Probe("HyundaiKia", "771", "22B958", "62B958"),
            Probe("HyundaiKia", "7A2", "22B002", "62B002"),
            Probe("HyundaiKia", "7C6", "22B002", "62B002"),
        )
        BrandEcuHints.VehicleBrandGroup.MAZDA -> listOf(
            Probe("Mazda", "720", "222101", "622101"),
            Probe("Mazda", "720", "222100", "622100"),
            Probe("Mazda", "730", "222101", "622101"),
            Probe("Mazda", "731", "222101", "622101"),
        )
        BrandEcuHints.VehicleBrandGroup.NISSAN -> listOf(
            Probe("Nissan", "743", "22D106", "62D106"),
            Probe("Nissan", "743", "22D111", "62D111"),
            Probe("Nissan", "743", "222003", "622003"),
            Probe("Nissan", "743", "222010", "622010"),
            Probe("Nissan", "744", "22D106", "62D106"),
            Probe("Nissan", "744", "22D111", "62D111"),
            Probe("Nissan", "740", "22D111", "62D111"),
            Probe("Nissan", "740", "22D106", "62D106"),
            Probe("Nissan", "760", "22D111", "62D111"),
            Probe("Nissan", "793", "22D111", "62D111"),
        )
        BrandEcuHints.VehicleBrandGroup.BMW_MINI -> listOf(
            Probe("BMW", "600", "22D010", "62D010", preludeHex = listOf("1003")),
            Probe("BMW", "600", "222002", "622002", preludeHex = listOf("1003")),
            Probe("BMW", "600", "222003", "622003", preludeHex = listOf("1003")),
            Probe("BMW", "601", "22D010", "62D010", preludeHex = listOf("1003")),
            Probe("Mini", "600", "22D010", "62D010", preludeHex = listOf("1003")),
        )
        BrandEcuHints.VehicleBrandGroup.JAGUAR -> listOf(
            Probe("JLR", "7C4", "22D111", "62D111"),
            Probe("JLR", "7C4", "22DD01", "62DD01"),
            Probe("JLR", "720", "22D111", "62D111"),
            Probe("JLR", "736", "22D111", "62D111"),
        )
        BrandEcuHints.VehicleBrandGroup.LADA -> listOf(
            Probe("Lada", "712", "222010", "622010"),
            Probe("Lada", "712", "222003", "622003"),
            Probe("Lada", "712", "222101", "622101"),
            Probe("Lada", "714", "222010", "622010"),
            Probe("Lada", "714", "222003", "622003"),
            Probe("Lada", "714", "222101", "622101"),
            Probe("Lada", "715", "222010", "622010"),
            Probe("Lada", "715", "222003", "622003"),
            Probe("Lada", "720", "222010", "622010"),
            Probe("Lada", "720", "222101", "622101"),
            Probe("Lada", "740", "222010", "622010"),
        )
        BrandEcuHints.VehicleBrandGroup.MERCEDES -> listOf(
            Probe("Mercedes", "720", "222003", "622003"),
            Probe("Mercedes", "720", "222010", "622010"),
            Probe("Mercedes", "720", "222014", "622014"),
            Probe("Mercedes", "720", "22291A", "62291A"),
            Probe("Mercedes", "743", "222003", "622003"),
            Probe("Mercedes", "743", "222010", "622010"),
        )
        BrandEcuHints.VehicleBrandGroup.CHANGAN -> listOf(
            Probe("Changan", "720", "222010", "622010"),
            Probe("Changan", "720", "222003", "622003"),
            Probe("Changan", "714", "222010", "622010"),
            Probe("Changan", "714", "222003", "622003"),
            Probe("Changan", "740", "222010", "622010"),
        )
        // Renault: щиток на 770, UCH на 742; DID 22F200 — Renault-специфичный
        BrandEcuHints.VehicleBrandGroup.RENAULT -> listOf(
            Probe("Renault", "770", "222003", "622003"),
            Probe("Renault", "770", "222010", "622010"),
            Probe("Renault", "770", "22F200", "62F200"),
            Probe("Renault", "770", "222101", "622101"),
            Probe("Renault", "742", "222003", "622003"),
            Probe("Renault", "742", "222010", "622010"),
        )
        // Mitsubishi: комбинация 7C0, gateway 750 — архитектура ближе к Toyota
        BrandEcuHints.VehicleBrandGroup.MITSUBISHI -> listOf(
            Probe("Mitsubishi", "7C0", "222182", "622182"),
            Probe("Mitsubishi", "7C0", "222101", "622101"),
            Probe("Mitsubishi", "7C0", "222003", "622003"),
            Probe("Mitsubishi", "750", "222182", "622182"),
            Probe("Mitsubishi", "750", "222101", "622101"),
            Probe("Mitsubishi", "750", "222003", "622003"),
            Probe("Mitsubishi", "750", "222010", "622010"),
        )
        // Haval/GWM: китайская платформа, типовые адреса 720/714/740
        BrandEcuHints.VehicleBrandGroup.HAVAL_GWM -> listOf(
            Probe("Haval", "720", "222010", "622010"),
            Probe("Haval", "720", "222003", "622003"),
            Probe("Haval", "714", "222010", "622010"),
            Probe("Haval", "714", "222003", "622003"),
            Probe("Haval", "740", "222010", "622010"),
        )
        // Geely: китайская платформа, аналогичные Haval/Changan адреса
        BrandEcuHints.VehicleBrandGroup.GEELY -> listOf(
            Probe("Geely", "720", "222010", "622010"),
            Probe("Geely", "720", "222003", "622003"),
            Probe("Geely", "714", "222010", "622010"),
            Probe("Geely", "714", "222003", "622003"),
            Probe("Geely", "740", "222010", "622010"),
        )
        BrandEcuHints.VehicleBrandGroup.CHERY -> listOf(
            Probe("Chery", "720", "222010", "622010"),
            Probe("Chery", "720", "222003", "622003"),
            Probe("Chery", "714", "222010", "622010"),
            Probe("Chery", "714", "222003", "622003"),
            Probe("Chery", "740", "222010", "622010"),
        )
        // Subaru: щиток 7C0 / BIU 744 — ориентиры UDS 0x22 (SSM/CAN)
        BrandEcuHints.VehicleBrandGroup.SUBARU -> listOf(
            Probe("Subaru", "7C0", "222010", "622010"),
            Probe("Subaru", "7C0", "222003", "622003"),
            Probe("Subaru", "7C0", "222101", "622101"),
            Probe("Subaru", "744", "222010", "622010"),
            Probe("Subaru", "744", "222003", "622003"),
            Probe("Subaru", "740", "222010", "622010"),
            Probe("Subaru", "750", "222010", "622010"),
        )
        BrandEcuHints.VehicleBrandGroup.OTHER -> emptyList()
    }

    /** Данные после маркера `62 xx xx` в уже очищенной hex-строке. */
    fun extractPayloadAfterMarker(cleanUpper: String, marker: String): ByteArray? {
        val m = marker.uppercase()
        val i = cleanUpper.indexOf(m)
        if (i < 0) return null
        var p = i + m.length
        val out = ArrayList<Int>()
        while (out.size < 16 && p + 2 <= cleanUpper.length) {
            if (cleanUpper[p] == '7' && p + 1 < cleanUpper.length && cleanUpper[p + 1] == 'F') break
            val a = cleanUpper[p].digitToIntOrNull(16) ?: break
            val b = cleanUpper[p + 1].digitToIntOrNull(16) ?: break
            out.add((a shl 4) or b)
            p += 2
        }
        if (out.isEmpty()) return null
        return ByteArray(out.size) { out[it].toByte() }
    }

    fun parseOdometerKm(data: ByteArray): Int? {
        if (data.isEmpty()) return null
        fun u8(i: Int) = data[i].toInt() and 0xFF

        if (data.size >= 3) {
            val be = (u8(0) shl 16) or (u8(1) shl 8) or u8(2)
            if (be in 1..2_000_000) return be
            val le = (u8(2) shl 16) or (u8(1) shl 8) or u8(0)
            if (le in 1..2_000_000) return le
        }
        if (data.size >= 4) {
            val be32 = (u8(0).toLong() shl 24) or (u8(1).toLong() shl 16) or (u8(2).toLong() shl 8) or u8(3).toLong()
            if (be32 in 1..2_000_000L) return be32.toInt()
            if (be32 in 1L..200_000_000L) {
                val div100 = (be32 / 100L).toInt()
                if (div100 in 1..2_000_000) return div100
            }
        }
        if (data.size >= 2) {
            val u16be = (u8(0) shl 8) or u8(1)
            if (u16be in 100..500_000) return u16be
            val u16le = (u8(1) shl 8) or u8(0)
            if (u16le in 100..500_000) return u16le
        }
        if (data.size >= 3) {
            parseBcdSixDigits(u8(0), u8(1), u8(2))?.let { if (it in 1..999_999) return it }
        }
        return null
    }

    private fun parseBcdSixDigits(b0: Int, b1: Int, b2: Int): Int? {
        fun pair(byte: Int): Int? {
            val h = (byte shr 4) and 0xF
            val l = byte and 0xF
            if (h > 9 || l > 9) return null
            return h * 10 + l
        }
        val p0 = pair(b0) ?: return null
        val p1 = pair(b1) ?: return null
        val p2 = pair(b2) ?: return null
        return p0 * 10_000 + p1 * 100 + p2
    }
}
