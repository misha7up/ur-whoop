package com.uremont.bluetooth

/**
 * Единая точка конфигурации бренда и таймингов (white-label, сопоставление с iOS [BrandConfig]).
 * URL и лимиты не разбросаны по классам.
 */
object AppConfig {
    const val MAP_SCHEME = "https"
    const val MAP_HOST = "map.uremont.com"
    const val MAP_QUERY_AI = "ai"

    const val SESSIONS_FILE_NAME = "sessions.json"
    const val MAX_SESSION_RECORDS = 100

    const val DEFAULT_WIFI_HOST = "192.168.0.10"
    const val DEFAULT_WIFI_PORT = 35000

    /**
     * Значения [timestamp] в JSON ниже этой границы трактуются как **секунды** Unix (legacy iOS),
     * иначе — миллисекунды (канонический формат и legacy Android `ts`).
     */
    const val TIMESTAMP_UNIX_SECONDS_CEILING = 100_000_000_000L

    const val LIVE_POLL_MIN_CYCLE_MS = 300L
    const val LIVE_POLL_BACKGROUND_DELAY_MS = 2_000L
    const val POST_CONNECT_DELAY_MS = 500L

    const val OBD_READ_TIMEOUT_MS = 12_000L
    const val OBD_SENSOR_TIMEOUT_BT_MS = 1_500L
    const val OBD_SENSOR_TIMEOUT_WIFI_MS = 800L
    const val OBD_POLL_INTERVAL_MS = 30L
}
