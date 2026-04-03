package com.uremont.bluetooth

import android.content.Context
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.FileNotFoundException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

// ─────────────────────────── SESSION RECORD ──────────────────────────────────

/**
 * Одна запись в истории диагностики.
 * Создаётся автоматически после каждого сканирования ошибок.
 *
 * [timestamp] — **миллисекунды** Unix-эпохи (как `System.currentTimeMillis()`), в JSON — то же (ключ `timestamp`).
 */
data class SessionRecord(
    val id: String = UUID.randomUUID().toString(),
    val timestamp: Long = System.currentTimeMillis(),
    /** Отображаемое имя авто: "BMW 2012" или "Автомобиль" если не удалось определить. */
    val vehicleName: String,
    val vin: String? = null,
    val mainDtcs: List<String> = emptyList(),
    val pendingDtcs: List<String> = emptyList(),
    /** Постоянные эмиссионные PDTC (Mode 0A); на EU часто пусто. */
    val permanentDtcs: List<String> = emptyList(),
    /** true — для этой сессии был сделан Freeze Frame снимок параметров. */
    val hasFreezeFrame: Boolean = false,
    /** Ключ = название блока (ABS, SRS...), значение = список кодов. */
    val otherEcuErrors: Map<String, List<String>> = emptyMap(),
) {
    /** Суммарное количество кодов включая ожидающие и другие блоки. */
    val totalErrors: Int
        get() = mainDtcs.size + pendingDtcs.size + permanentDtcs.size + otherEcuErrors.values.sumOf { it.size }

    val formattedDate: String
        get() = SimpleDateFormat("d MMM yyyy, HH:mm", Locale("ru")).format(Date(timestamp))
}

// ─────────────────────────── LOAD OUTCOME ────────────────────────────────────

enum class SessionHistoryIssue {
    IO_FAILED,
    PARSE_FAILED,
    PARTIAL_ENTRIES,
}

data class SessionLoadOutcome(
    val sessions: List<SessionRecord>,
    val issue: SessionHistoryIssue? = null,
    val corruptEntryCount: Int = 0,
)

// ─────────────────────────── SESSION REPOSITORY ──────────────────────────────

/**
 * Сохраняет и загружает историю сессий из JSON-файла в filesDir приложения.
 * Канонический JSON совпадает с iOS ([SessionRecord] Codable): длинные ключи, `timestamp` в мс.
 * Читает также legacy-короткие ключи Android (`ts`, `vn`, `md`…).
 */
object SessionRepository {

    fun save(context: Context, record: SessionRecord) {
        val outcome = loadAllDetailed(context)
        if (outcome.issue == SessionHistoryIssue.IO_FAILED) {
            DebugLogger.e("SessionRepo", "save aborted: cannot read existing file")
            return
        }
        val all = outcome.sessions.toMutableList()
        all.add(0, record)
        if (all.size > AppConfig.MAX_SESSION_RECORDS) {
            all.subList(AppConfig.MAX_SESSION_RECORDS, all.size).clear()
        }
        val arr = JSONArray()
        all.forEach { arr.put(it.toJson()) }
        runCatching {
            context.openFileOutput(AppConfig.SESSIONS_FILE_NAME, Context.MODE_PRIVATE)
                .bufferedWriter().use { it.write(arr.toString()) }
        }.onFailure { e ->
            DebugLogger.e("SessionRepo", "save write failed: ${e.message}", e)
        }
    }

    /** Обратная совместимость: только список (без диагностики). */
    fun loadAll(context: Context): List<SessionRecord> = loadAllDetailed(context).sessions

    /**
     * Полная загрузка с классификацией проблем: не глотает ошибки молча.
     * Отсутствие файла — норма (`issue == null`, пустой список).
     */
    fun loadAllDetailed(context: Context): SessionLoadOutcome {
        return try {
            val text = context.openFileInput(AppConfig.SESSIONS_FILE_NAME).bufferedReader().readText()
            val arr = JSONArray(text)
            val out = ArrayList<SessionRecord>(arr.length())
            var bad = 0
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i)
                if (obj == null) {
                    bad++
                    continue
                }
                val rec = obj.toRecordOrNull()
                if (rec != null) out.add(rec) else bad++
            }
            val issue = when {
                bad > 0 -> SessionHistoryIssue.PARTIAL_ENTRIES
                else -> null
            }
            SessionLoadOutcome(out, issue, corruptEntryCount = bad)
        } catch (_: FileNotFoundException) {
            SessionLoadOutcome(emptyList(), null, 0)
        } catch (e: JSONException) {
            DebugLogger.e("SessionRepo", "JSON parse failed: ${e.message}", e)
            SessionLoadOutcome(emptyList(), SessionHistoryIssue.PARSE_FAILED, 0)
        } catch (e: Exception) {
            DebugLogger.e("SessionRepo", "load failed: ${e.message}", e)
            SessionLoadOutcome(emptyList(), SessionHistoryIssue.IO_FAILED, 0)
        }
    }

    fun clear(context: Context) {
        runCatching { context.deleteFile(AppConfig.SESSIONS_FILE_NAME) }
    }

    // ── JSON (canonical + legacy Android short keys) ─────────────────────────

    private fun SessionRecord.toJson() = JSONObject().apply {
        put("id", id)
        put("timestamp", timestamp)
        put("vehicleName", vehicleName)
        vin?.let { put("vin", it) }
        put("mainDtcs", JSONArray(mainDtcs))
        put("pendingDtcs", JSONArray(pendingDtcs))
        put("permanentDtcs", JSONArray(permanentDtcs))
        put("hasFreezeFrame", hasFreezeFrame)
        val map = JSONObject()
        otherEcuErrors.forEach { (k, v) -> map.put(k, JSONArray(v)) }
        put("otherEcuErrors", map)
    }

    private fun JSONObject.toRecordOrNull(): SessionRecord? = runCatching {
        val idStr = optString("id").takeIf { it.isNotBlank() } ?: UUID.randomUUID().toString()
        val tsMs = optTimestampMs() ?: throw JSONException("missing timestamp")
        val vName = optString("vehicleName").ifBlank { optString("vn") }.ifBlank { "Автомобиль" }
        val vinOpt = optString("vin").takeIf { it.isNotBlank() && it != "null" }
        SessionRecord(
            id = idStr,
            timestamp = tsMs,
            vehicleName = vName,
            vin = vinOpt,
            mainDtcs = optJSONArray("mainDtcs")?.toStringList()
                ?: optJSONArray("md")?.toStringList()
                ?: emptyList(),
            pendingDtcs = optJSONArray("pendingDtcs")?.toStringList()
                ?: optJSONArray("pd")?.toStringList()
                ?: emptyList(),
            permanentDtcs = optJSONArray("permanentDtcs")?.toStringList()
                ?: optJSONArray("pm")?.toStringList()
                ?: emptyList(),
            hasFreezeFrame = if (has("hasFreezeFrame")) optBoolean("hasFreezeFrame") else optBoolean("ff"),
            otherEcuErrors = optJSONObject("otherEcuErrors")?.toStringListMap()
                ?: optJSONObject("ecu")?.toStringListMap()
                ?: emptyMap(),
        )
    }.getOrNull()

    private fun JSONObject.optTimestampMs(): Long? {
        if (has("timestamp")) {
            val raw = get("timestamp")
            val num = (raw as? Number)?.toDouble() ?: return null
            return if (num < AppConfig.TIMESTAMP_UNIX_SECONDS_CEILING) {
                (num * 1000.0).toLong()
            } else {
                num.toLong()
            }
        }
        if (has("ts")) return getLong("ts")
        return null
    }

    private fun JSONObject.toStringListMap(): Map<String, List<String>> =
        keys().asSequence().associateWith { k -> getJSONArray(k).toStringList() }

    private fun JSONArray.toStringList() = (0 until length()).map { getString(it) }
}
