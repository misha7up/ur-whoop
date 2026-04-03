package com.uremont.bluetooth

import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// ─────────────────────────────────────────────────────────────────────────────
//  DebugLogger — in-memory кольцевой буфер диагностических логов
//
//  Используется двойным образом:
//    1. Вместо android.util.Log.* — все вызовы перенаправляются и в LogCat, и сюда.
//    2. UI «Консоль отладки» в настройках читает [entries] и отображает логи.
//
//  Записи хранятся в памяти (не на диске), сбрасываются при выходе из процесса.
//  При переполнении буфера (MAX_ENTRIES) самые старые записи вытесняются.
// ─────────────────────────────────────────────────────────────────────────────

/** Уровень важности лог-записи. */
enum class LogLevel(
    /** Однобуквенный тег, как в LogCat. */
    val letter: String,
) {
    DEBUG("D"),
    INFO("I"),
    WARN("W"),
    ERROR("E"),
}

/** Одна запись в буфере отладочных логов. */
data class LogEntry(
    val timeMs:  Long     = System.currentTimeMillis(),
    val level:   LogLevel,
    val tag:     String,
    val message: String,
)

/**
 * Singleton-буфер диагностических логов приложения.
 *
 * Все методы потокобезопасны (синхронизированы через `lock`).
 * Буфер начинает заполняться с момента первого вызова любого log-метода —
 * то есть фактически с запуска приложения.
 *
 * ### Использование
 * ```kotlin
 * DebugLogger.d("MyTag", "Подключение начато")
 * DebugLogger.e("MyTag", "Ошибка", exception)
 * val allLogs = DebugLogger.entries   // snapshot для отображения в UI
 * ```
 */
object DebugLogger {

    private const val MAX_ENTRIES = 800
    private val _entries = ArrayDeque<LogEntry>(MAX_ENTRIES + 1)
    private val lock     = Any()
    private val fmt      = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    /** Snapshot текущего содержимого буфера (новые записи в конце). */
    val entries: List<LogEntry>
        get() = synchronized(lock) { _entries.toList() }

    /** Количество записей в буфере. */
    val size: Int
        get() = synchronized(lock) { _entries.size }

    // ── Методы логирования ────────────────────────────────────────────────────

    fun d(tag: String, msg: String) {
        add(LogLevel.DEBUG, tag, msg)
        Log.d(tag, msg)
    }

    fun i(tag: String, msg: String) {
        add(LogLevel.INFO, tag, msg)
        Log.i(tag, msg)
    }

    fun w(tag: String, msg: String) {
        add(LogLevel.WARN, tag, msg)
        Log.w(tag, msg)
    }

    fun e(tag: String, msg: String, throwable: Throwable? = null) {
        val full = if (throwable != null) "$msg — ${throwable.javaClass.simpleName}: ${throwable.message}" else msg
        add(LogLevel.ERROR, tag, full)
        if (throwable != null) Log.e(tag, msg, throwable) else Log.e(tag, msg)
    }

    // ── Управление буфером ────────────────────────────────────────────────────

    /** Очищает все записи в буфере. */
    fun clear() = synchronized(lock) { _entries.clear() }

    /**
     * Форматирует все записи в одну строку (для копирования в буфер обмена).
     * Формат: `HH:mm:ss.SSS L/TAG: message`
     */
    fun formatAll(): String = entries.joinToString("\n") { e ->
        "${fmt.format(Date(e.timeMs))} ${e.level.letter}/${e.tag}: ${e.message}"
    }

    // ── Внутреннее добавление ─────────────────────────────────────────────────

    private fun add(level: LogLevel, tag: String, message: String) {
        synchronized(lock) {
            if (_entries.size >= MAX_ENTRIES) _entries.removeFirst()
            _entries.addLast(LogEntry(System.currentTimeMillis(), level, tag, message))
        }
    }
}
