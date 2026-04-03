package com.uremont.bluetooth

/**
 * Разбор ответов Mode 09 / Mode 01 для расширенного [VehicleInfo].
 */
object ObdVehicleInfoParse {

    /** 4 байта битовой маски после маркера `4900` (PID 0x00 в Mode 09). */
    fun mode09SupportMask(clean: String): ByteArray? {
        val i = clean.indexOf("4900")
        if (i < 0) return null
        var p = i + 4
        val out = ByteArray(4)
        for (j in 0 until 4) {
            if (p + 2 > clean.length) return null
            val v = clean.substring(p, p + 2).toIntOrNull(16) ?: return null
            out[j] = v.toByte()
            p += 2
        }
        return out
    }

    /**
     * Поддерживается ли PID `pid` (1…32) в Mode 09 по маске.
     * Если `mask == null`, для оптимистичного чтения считаем поддержанными только 3 и 4.
     */
    fun isMode09PidSupported(mask: ByteArray?, pid: Int): Boolean {
        if (pid !in 1..32) return false
        if (mask == null || mask.size < 4) return pid == 3 || pid == 4
        val bitIndex = pid - 1
        val byteIx = bitIndex / 8
        val bitInByte = 7 - (bitIndex % 8)
        return (mask[byteIx].toInt() shr bitInByte) and 1 != 0
    }

    /** Самая длинная ASCII-строка после `4903` / `490A` и т.п. */
    fun bestAsciiAfterMarker(clean: String, marker: String, maxChars: Int): String? {
        var best: String? = null
        var from = 0
        while (from < clean.length) {
            val idx = clean.indexOf(marker, from)
            if (idx < 0) break
            val s = asciiFromMode09Index(clean, idx + marker.length, maxChars)
            if (s != null && (best == null || s.length > best.length)) best = s
            from = idx + marker.length
        }
        return best
    }

    private fun asciiFromMode09Index(clean: String, start: Int, maxChars: Int): String? {
        var p = start
        if (clean.length >= p + 2 && clean.substring(p, p + 2) == "01") p += 2
        val sb = StringBuilder()
        while (p + 1 < clean.length && sb.length < maxChars) {
            val byte = clean.substring(p, p + 2).toIntOrNull(16) ?: break
            if (byte == 0) break
            val ch = byte.toChar()
            if (ch.code !in 32..126) break
            sb.append(ch)
            p += 2
        }
        return sb.toString().trim().takeIf { it.length >= 2 }
    }

    /** CVN: после `4904` группы по 4 байта (8 hex), через пробел. */
    fun cvnHexLine(clean: String): String? {
        val idx = clean.indexOf("4904")
        if (idx < 0) return null
        var p = idx + 4
        if (clean.length >= p + 2 && clean.substring(p, p + 2) == "01") p += 2
        val groups = mutableListOf<String>()
        while (p + 8 <= clean.length && groups.size < 16) {
            val chunk = clean.substring(p, p + 8)
            if (!chunk.all { it in '0'..'9' || it in 'A'..'F' }) break
            groups.add(chunk)
            p += 8
        }
        return groups.joinToString(" ").takeIf { it.isNotEmpty() }
    }

    /** Сырые hex-данные после маркера (например `4901`), макс. [maxDataBytes] байт. */
    fun hexPayloadAfterMarker(clean: String, marker: String, maxDataBytes: Int): String? {
        val idx = clean.indexOf(marker)
        if (idx < 0) return null
        var p = idx + marker.length
        if (clean.length >= p + 2 && clean.substring(p, p + 2) == "01") p += 2
        val sb = StringBuilder()
        var bytes = 0
        while (bytes < maxDataBytes && p + 1 < clean.length) {
            val a = clean[p]
            val b = clean[p + 1]
            if (a !in '0'..'9' && a !in 'A'..'F') break
            if (b !in '0'..'9' && b !in 'A'..'F') break
            sb.append(a).append(b)
            bytes++
            p += 2
        }
        return sb.toString().takeIf { it.length >= 4 }
    }

    /** Один байт данных Mode 01 после `41` + `pidHex2` (например `1C` → `411C`). */
    fun singleByteMode01(clean: String, pidHex2: String): Int? {
        val marker = "41${pidHex2.uppercase()}"
        val idx = clean.indexOf(marker)
        if (idx < 0 || clean.length < idx + marker.length + 2) return null
        val p = idx + marker.length
        return clean.substring(p, p + 2).toIntOrNull(16)
    }
}
