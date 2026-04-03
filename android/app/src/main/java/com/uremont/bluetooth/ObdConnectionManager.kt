package com.uremont.bluetooth

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

// Псевдоним для краткости: все важные события идут и в LogCat, и в DebugLogger-консоль.
private fun dbg(tag: String, msg: String)              = DebugLogger.d(tag, msg)
private fun info(tag: String, msg: String)             = DebugLogger.i(tag, msg)
private fun warn(tag: String, msg: String)             = DebugLogger.w(tag, msg)
private fun err(tag: String, msg: String, t: Throwable? = null) = DebugLogger.e(tag, msg, t)

// ─────────────────────────── SHARED HELPERS ──────────────────────────────────

/**
 * Удаляет все пробелы, переносы строк и CR из ответа ELM327 и переводит в верхний регистр.
 * Применяется повсеместно перед разбором hex-данных.
 */
private fun String.cleanObd(): String = replace(Regex("[\r\n\\s]"), "").uppercase()

/**
 * Первое вхождение `marker` (например `4121`) + 4 hex-цифры данных Mode 01 → uint16 (ст. байт первый).
 * Надёжнее, чем [String.indexOf], если в буфере есть лишние вхождения подстроки.
 */
private fun parseMode01TwoByteFromCleaned(clean: String, marker: String): Int? {
    val re = Regex(Regex.escape(marker) + "([0-9A-F]{4})")
    val m = re.find(clean) ?: return null
    val hex = m.groupValues[1]
    val a = hex.substring(0, 2).toIntOrNull(16) ?: return null
    val b = hex.substring(2, 4).toIntOrNull(16) ?: return null
    return a * 256 + b
}

// ─────────────────────────── OBD BLUETOOTH MANAGER ───────────────────────────

/**
 * Управляет Bluetooth-соединением с адаптером ELM327 и реализует
 * клиентскую часть протокола OBD2 поверх SPP (Serial Port Profile, RFCOMM).
 *
 * Поддерживаемые режимы OBD2:
 *   Mode 01 — текущие параметры (Live Data PIDs)
 *   Mode 02 — Freeze Frame — снимок параметров в момент появления ошибки
 *   Mode 03 — постоянные коды неисправностей (DTC)
 *   Mode 04 — сброс кодов и гашение Check Engine
 *   Mode 07 — ожидающие коды (Pending DTC)
 *   Mode 09 — VIN, CalID, CVN, маска PID, имя ЭБУ; на CAN — имя ЭБУ КПП (7E1)
 *
 * Совместимость: любой автомобиль с OBD2 (1996+). Протокол (CAN / K-Line / ISO)
 * определяется автоматически командой ATSP0.
 */
class ObdConnectionManager {

    companion object {
        private const val TAG = "ObdConnection"

        /** UUID стандартного Bluetooth Serial Port Profile (SPP). */
        private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805f9b34fb")

        /** См. [AppConfig.OBD_READ_TIMEOUT_MS]. */
        private val READ_TIMEOUT_MS get() = AppConfig.OBD_READ_TIMEOUT_MS
        private val SENSOR_TIMEOUT_BT_MS get() = AppConfig.OBD_SENSOR_TIMEOUT_BT_MS
        private val SENSOR_TIMEOUT_WIFI_MS get() = AppConfig.OBD_SENSOR_TIMEOUT_WIFI_MS
        private val POLL_INTERVAL_MS get() = AppConfig.OBD_POLL_INTERVAL_MS
    }

    private var socket:     BluetoothSocket?   = null
    /** TCP-сокет для Wi-Fi ELM327 адаптеров (напр. Kingbolen, OBDII Wi-Fi). */
    private var wifiSocket: java.net.Socket?   = null
    private var input:  InputStream?           = null
    private var output: OutputStream?          = null

    /**
     * Мьютекс, сериализующий все операции с сокетом.
     *
     * Проблема без мьютекса: при одновременном запуске live-мониторинга и чтения DTC
     * два корутина могут отправлять команды и читать ответы из одного сокета параллельно.
     * Для Wi-Fi (TCP) это критично — corrupted stream сложно восстановить.
     *
     * Стратегия для [pollSensor]: `tryLock()` (неблокирующий).
     *   Если DTC-скан держит мьютекс — сенсор немедленно возвращает ERROR (N/A в UI).
     *   Это приемлемо: мониторинг продолжается и восстанавливается автоматически.
     *
     * Стратегия для DTC/VehicleInfo-операций: `withLock` (ожидающий).
     *   Перед началом ждёт завершения текущего poll-цикла — не более одного PID (~800 мс Wi-Fi).
     */
    private val ioMutex = Mutex()

    /**
     * Время последней отправки OBD2-команды (не AT) в ms.
     *
     * K-Line (ISO 9141-2 / KWP2000) имеет P3_Max = 5 секунд — максимальный
     * интервал между командами клиента. Если пауза превышает P3_Max, ЭБУ
     * закрывает K-Line сессию. ELM327 не знает об этом и при следующем запросе
     * отправляет команду в "мёртвую" сессию → ЭБУ не отвечает → "NO DATA".
     * [warmupIfNeeded] использует это поле, чтобы проактивно переустановить
     * сессию перед любой OBD2-командой, если пауза >3.5 с.
     */
    private var lastEcuCommandMs = 0L

    /**
     * true = текущий авто использует CAN (ISO 15765-4).
     * false = K-Line (ISO 9141-2) или KWP2000 (ISO 14230) или J1850.
     *
     * Влияет на парсинг DTC: на CAN первый байт после маркера (43/47/4A) —
     * количество кодов; на остальных протоколах — сразу DTC-пары.
     * Определяется в [initializeElm327] по ответу ATDP.
     */
    internal var isCanProtocol = true

    /** Возвращает true, если соединение установлено (BT или Wi-Fi). */
    val isConnected: Boolean
        get() = (socket?.isConnected == true) ||
                (wifiSocket?.let { it.isConnected && !it.isClosed } == true)

    /** true — текущее соединение идёт по Wi-Fi TCP, false — Bluetooth RFCOMM. */
    val isWifi: Boolean
        get() = wifiSocket?.let { it.isConnected && !it.isClosed } == true

    /** Актуальный таймаут live PID — Wi-Fi быстрее BT SPP (см. SENSOR_TIMEOUT_*_MS). */
    private val sensorTimeout: Long
        get() = if (isWifi) SENSOR_TIMEOUT_WIFI_MS else SENSOR_TIMEOUT_BT_MS

    /**
     * Подпись последнего успешного подключения (имя BT или MAC).
     * Нужна, чтобы восстановить строку «Подключено…» после пересоздания Activity.
     */
    var connectedDeviceLabel: String? = null
        private set

    // ─────────────────────────── CONNECT ────────────────────────────────────

    /**
     * Устанавливает Bluetooth-соединение с адаптером [device].
     *
     * Перебирает три стратегии подключения по убыванию совместимости:
     *  1. **InsecureSPP** — без шифрования/аутентификации. Именно так работают
     *     CarScanner и большинство OBD-приложений с дешёвыми ELM327 mini.
     *  2. **SecureSPP** — стандартный UUID с аутентификацией. Нужен для некоторых
     *     фирменных адаптеров (OBDLink, BAFX).
     *  3. **Reflection ch1** — обходит SDP-поиск через рефлексию и принудительно
     *     открывает канал 1. Работает на адаптерах с жёстко прошитым каналом.
     *
     * [btAdapter] нужен только для отмены активного сканирования перед подключением
     * (активный скан мешает RFCOMM handshake).
     */
    suspend fun connect(
        device: BluetoothDevice,
        btAdapter: android.bluetooth.BluetoothAdapter? = null,
    ): Result<Unit> = withContext(Dispatchers.IO) {
        disconnect()
        info(TAG, "═══ BT connect → ${runCatching { device.name }.getOrDefault(device.address)} (${device.address}) ═══")
        // Активный Discovery мешает RFCOMM-соединению — останавливаем.
        try { btAdapter?.cancelDiscovery() } catch (_: Exception) {}

        data class Strategy(val name: String, val make: () -> BluetoothSocket)

        val strategies = listOf(
            Strategy("InsecureSPP")  { device.createInsecureRfcommSocketToServiceRecord(SPP_UUID) },
            Strategy("SecureSPP")    { device.createRfcommSocketToServiceRecord(SPP_UUID) },
            Strategy("Reflection-ch1") {
                @Suppress("UNCHECKED_CAST")
                device.javaClass
                    .getMethod("createRfcommSocket", Int::class.java)
                    .invoke(device, 1) as BluetoothSocket
            },
        )

        var lastError: Exception? = null
        for (strategy in strategies) {
            try {
                dbg(TAG, "Attempting connect via ${strategy.name}")
                val s = strategy.make()
                s.connect()
                socket = s; input = s.inputStream; output = s.outputStream
                dbg(TAG, "Connected via ${strategy.name}")
                initializeElm327()
                connectedDeviceLabel = runCatching {
                    device.name?.takeIf { it.isNotBlank() } ?: device.address
                }.getOrElse { device.address }
                return@withContext Result.success(Unit)
            } catch (e: Exception) {
                warn(TAG, "${strategy.name} failed: ${e.message}")
                lastError = e
                runCatching { socket?.close() }
                socket = null; input = null; output = null
            }
        }
        Result.failure(Exception(friendlyError(lastError), lastError))
    }

    /**
     * Переводит низкоуровневое исключение в понятный пользователю текст на русском.
     */
    private fun friendlyError(e: Exception?): String {
        val msg = e?.message?.lowercase() ?: return "Неизвестная ошибка"
        return when {
            e is SecurityException ->
                "Нет разрешения Bluetooth — разрешите доступ в настройках приложения"
            "connection refused" in msg ->
                "Адаптер отклонил соединение. Убедитесь: ELM327 вставлен в разъём, зажигание ON"
            "bonding" in msg || "not bonded" in msg || "bond" in msg ->
                "Устройство не сопряжено. Войдите в Настройки → Bluetooth → найдите OBDII и введите PIN 1234"
            "read failed" in msg || "socket might closed" in msg ->
                "Таймаут подключения. Проверьте: зажигание включено, адаптер не заблокирован другим приложением"
            "unable to start service discovery" in msg || "service discovery failed" in msg ->
                "Не найден SPP-сервис. Удалите адаптер из сопряжённых и выполните сопряжение заново"
            "host is down" in msg || "host unreachable" in msg ->
                "Адаптер недоступен. Включите зажигание и убедитесь, что ELM327 мигает светодиодом"
            "bluetooth is off" in msg ->
                "Bluetooth выключен. Включите Bluetooth и повторите"
            "insufficient encryption" in msg || "authentication" in msg ->
                "Ошибка аутентификации. Удалите устройство из сопряжённых и выполните повторное спаривание"
            "already connected" in msg ->
                "Уже подключено к другому устройству — нажмите «Отключить» и повторите"
            else ->
                "Ошибка подключения: ${e.javaClass.simpleName} — ${e.message}"
        }
    }

    // ─────────────────────────── CONNECT Wi-Fi ──────────────────────────────

    /**
     * Устанавливает TCP-соединение с Wi-Fi ELM327 адаптером.
     *
     * Типичные параметры:
     *   host = "192.168.0.10" (Kingbolen, большинство китайских Wi-Fi ELM327)
     *   port = 35000          (стандартный OBD Wi-Fi порт)
     *   Некоторые адаптеры используют 192.168.4.1:35000 или 192.168.1.1:23.
     *
     * Телефон должен быть уже подключён к Wi-Fi точке адаптера.
     * Специальных разрешений Android не требуется — только INTERNET (уже объявлен).
     */
    suspend fun connectWifi(host: String, port: Int): Result<Unit> = withContext(Dispatchers.IO) {
        disconnect()
        info(TAG, "═══ WiFi connect → $host:$port ═══")
        try {
            val sock = java.net.Socket()
            // TCP_NODELAY отключает алгоритм Nagle, который буферизует короткие пакеты
            // (наши AT-команды = 2-6 байт) ожидая ACK и добавляя до 200 мс задержки.
            // Без этого флага команды "03\r", "04\r" могут приходить на адаптер с задержкой,
            // что вызывает NO DATA или STOPPED при повторных запросах.
            sock.tcpNoDelay = true
            sock.connect(java.net.InetSocketAddress(host, port), 10_000)
            wifiSocket = sock
            input  = sock.getInputStream()
            output = sock.getOutputStream()
            connectedDeviceLabel = "$host:$port"
            initializeElm327()
            Result.success(Unit)
        } catch (e: Exception) {
            warn(TAG, "WiFi connect failed: ${e.message}")
            runCatching { wifiSocket?.close() }
            wifiSocket = null; input = null; output = null
            Result.failure(Exception(friendlyWifiError(e), e))
        }
    }

    private fun friendlyWifiError(e: Exception): String {
        val msg = e.message?.lowercase() ?: return "Неизвестная ошибка Wi-Fi"
        return when {
            "connect" in msg || "refused" in msg || "timed out" in msg || "timeout" in msg ->
                "Не удалось подключиться. Убедитесь: подключены к Wi-Fi сети адаптера, зажигание ON"
            "host" in msg || "network" in msg ->
                "Адрес адаптера не найден. Проверьте IP-адрес и порт"
            else -> "Ошибка Wi-Fi: ${e.javaClass.simpleName} — ${e.message}"
        }
    }

    // ─────────────────────────── INIT ELM327 ────────────────────────────────

    /**
     * Инициализирует адаптер ELM327 стандартной последовательностью AT-команд.
     *
     * Команды:
     *   ATZ   — полный сброс (Reset All). Необходим, т.к. адаптер мог
     *            остаться в неопределённом состоянии после предыдущего сеанса.
     *   ATE0  — отключить эхо (Echo Off). Без этого ответы дублируются.
     *   ATL0  — отключить переносы строк (Linefeeds Off). Упрощает парсинг.
     *   ATSP0 — автовыбор протокола (Set Protocol to 0 = auto).
     *            Охватывает CAN (ISO 15765-4), ISO 9141-2, KWP2000 и другие.
     *
     * После ATSP0 ОБЯЗАТЕЛЕН пробный запрос 0100 (поддерживаемые PIDs Mode 01).
     * Именно он запускает фактическое определение протокола:
     *   - CAN (большинство машин 2008+): ~500 мс
     *   - ISO 9141-2 / KWP2000 (Honda CRV 2004, старые авто): 5–7 с (slow init, 5 baud)
     * Без этого ELM327 будет каждый раз выводить "SEARCHING..." на первой же OBD2-команде,
     * что ломает парсинг DTC, стирание и live-данные.
     */
    private suspend fun initializeElm327() {
        // consumeAtResponse() — транспортно-осведомлённый хелпер:
        //   WiFi TCP:   readUntilPrompt() — обязательно (available() ненадёжен для TCP)
        //   BT RFCOMM:  drainInput()      — прежнее поведение, доказанно работает
        sendRaw("ATZ");   delay(2000); consumeAtResponse(3000) // Сброс → "ELM327 v...>"
        sendRaw("ATE0");  delay(300);  consumeAtResponse()     // Эхо выключено
        sendRaw("ATL0");  delay(300);  consumeAtResponse()     // Переносы строк выключены
        // ATH0/ATS0 критичны для WiFi-адаптеров: без них ответ содержит CAN-заголовки
        // и пробелы ("7E8 04 41 0C ..."), что ломает парсинг live-данных.
        sendRaw("ATH0");  delay(300);  consumeAtResponse()     // Заголовки CAN-кадра выключены
        sendRaw("ATS0");  delay(300);  consumeAtResponse()     // Пробелы в ответах выключены
        sendRaw("ATSP0"); delay(300);  consumeAtResponse()     // Автовыбор протокола

        // Принудительный прогрев: первая реальная OBD2-команда запускает определение протокола.
        // 0100 = "какие PIDs поддерживает Mode 01" — поддерживается ВСЕМИ автомобилями с OBD2.
        // Таймаут 9 секунд покрывает медленную K-Line инициализацию (до 7 с на некоторых авто).
        sendRaw("0100")
        val warmupResp = readUntilPrompt(9000).cleanObd()
        info(TAG, "Protocol warmup: '$warmupResp'")
        drainInput()

        // Определяем протокол для корректного парсинга DTC (count byte есть только на CAN)
        val proto = elmProtocolDescription().uppercase()
        isCanProtocol = proto.contains("CAN") || proto.contains("15765")
        info(TAG, "Detected protocol: '$proto', isCAN=$isCanProtocol")
        drainInput()

        info(TAG, "ELM327 initialization complete")
    }

    // ─────────────────────────── READ DTCs (MODE 03) ─────────────────────────

    /**
     * Читает постоянные коды неисправностей (Mode 03).
     *
     * Протокол: клиент отправляет "03\r", ЭБУ отвечает "43 XX XX XX..." где
     *   43 = 0x40 (positive response) | 0x03 (mode) = подтверждение Mode 03.
     *   Далее попарно идут байты кода: 2 байта = один DTC.
     *
     * Пример ответа: "43 01 43 00 00 00 00"
     *   → DTC P0143 (байты 0x01, 0x43 → nibble 0 = 'P', тип 0, код 143)
     */
    suspend fun readDtcs(): DtcResult = ioMutex.withLock { withContext(Dispatchers.IO) {
        try {
            warmupIfNeeded()
            drainInput()
            sendRaw("03")
            val raw = readUntilPrompt()
            val result = parseDtcResponse(responseMarker = "43", raw = raw)
            info(TAG, "readDtcs → $result")
            result
        } catch (e: Exception) {
            err(TAG, "readDtcs() error", e)
            DtcResult.Error(e.message ?: "Неизвестная ошибка")
        }
    } }

    /**
     * Разбирает ответ на запрос DTC.
     *
     * @param responseMarker  Hex-строка маркера ответа: "43" для Mode 03, "47" для Mode 07.
     * @param raw             Сырой ответ адаптера.
     * @param missingMarkerResult  Что вернуть, если маркер не найден.
     *                            Mode 03: RawResponse (нестандартный ответ).
     *                            Mode 07: NoDtcs (ожидающих кодов нет — норма).
     */
    internal fun parseDtcResponse(
        responseMarker: String,
        raw: String,
        missingMarkerResult: DtcResult = DtcResult.RawResponse(raw.trim()),
    ): DtcResult {
        val clean = raw.cleanObd()
        if (clean.contains("SEARCHING")) return DtcResult.Error("Адаптер ищёт протокол OBD2. Убедитесь, что зажигание включено, и повторите")
        if (!clean.contains(responseMarker)) return missingMarkerResult

        val dtcs = mutableSetOf<String>()

        // CAN: каждый ЭБУ отвечает отдельным фреймом, разделённым пробелом/переносом.
        // Разбиваем сырой ответ по whitespace и парсим каждый фрейм независимо.
        val tokens = raw.trim().split(Regex("[\\s\\r\\n]+"))
        for (token in tokens) {
            val hex = token.replace(Regex("^\\d+:"), "")
                .replace(Regex("[^0-9A-Fa-f]"), "").uppercase()
            if (!hex.startsWith(responseMarker)) continue
            val data = hex.substring(responseMarker.length)
            if (data.isEmpty() || data.startsWith("00")) continue
            parseDtcFrameData(data, dtcs)
        }

        // Fallback для ISO-TP multi-frame (0: 1: 2: …) — склеенный clean
        if (dtcs.isEmpty()) {
            val dataStart = clean.indexOf(responseMarker) + responseMarker.length
            val data = clean.substring(dataStart)
            if (data.isNotEmpty() && !data.startsWith("00")) {
                parseDtcFrameData(data, dtcs)
            }
        }
        return if (dtcs.isEmpty()) DtcResult.NoDtcs else DtcResult.DtcList(dtcs.toList())
    }

    /** Парсит DTC-данные одного ЭБУ (после маркера 43/47/4A).
     *  На CAN первый байт — количество кодов (01-FF); на K-Line / KWP / J1850 — сразу DTC-пары.
     *  [isCanProtocol] определяется при инициализации по ATDP. */
    internal fun parseDtcFrameData(data: String, out: MutableSet<String>) {
        val firstByte = data.take(2).toIntOrNull(16) ?: return
        val skipCount = isCanProtocol && firstByte in 1..255 && data.length >= 2 + firstByte * 4
        val start = if (skipCount) 2 else 0
        val maxPairs = if (skipCount) firstByte else data.length / 4
        var i = start
        var read = 0
        while (i + 4 <= data.length && read < maxPairs) {
            val block = data.substring(i, i + 4)
            if (block != "0000") out.add(decodeDtc(block))
            i += 4; read++
        }
    }

    /**
     * Декодирует 4-символьный hex-блок (2 байта) в стандартное обозначение DTC.
     *
     * Кодировка OBD2 SAE J2012:
     *   Старший полубайт первого байта определяет систему:
     *     0-3 → P (Powertrain)
     *     4-7 → C (Chassis)
     *     8-B → B (Body)
     *     C-F → U (Network/Undefined)
     *   Второй и третий полубайты дают двузначный номер типа (00-3F для P0000-P3FFF).
     *   Оставшиеся три цифры — специфический номер ошибки.
     *
     * Пример: hex "0143" → firstNibble=0 → "P", остаток="143" → "P0143"
     */
    internal fun decodeDtc(hex: String): String {
        if (hex.length < 4) return hex
        val firstNibble = hex[0].digitToIntOrNull(16) ?: return hex
        val system = when (firstNibble) {
            in 0..3  -> "P"
            in 4..7  -> "C"
            in 8..11 -> "B"
            else     -> "U"
        }
        // Тип (0-3) кодируется в двух младших битах первого nibble
        return "$system${firstNibble % 4}${hex.substring(1)}"
    }

    // ─────────────────────────── UDS 0x19 (ReadDTCInformation) ────────────────

    /**
     * UDS service 0x19, subFunction 0x02 (reportDTCByStatusMask).
     * Запрос: `19 02 FF` (все DTC с любым статусом).
     * Ответ:  `59 02 <availMask> [DTC_HI DTC_MID DTC_LO STATUS]...`
     *
     * DTC кодируется 3 байтами (J2012): первые 2 — как в OBD2 (P/C/B/U + код),
     * 3-й — Failure Type Byte (FTB, тип неисправности, напр. 11=circuit short to ground).
     * Статус-байт: bit3=confirmed, bit2=pending, bit0=testFailed.
     *
     * Используется как fallback, когда Mode 03 не поддерживается блоком (`7F 03 11` / `NO DATA`).
     * Перед запросом отправляется `10 03` (Extended Diagnostic Session) — многие блоки
     * требуют расширенной сессии для чтения DTC.
     */
    internal fun parseUdsDtcResponse(raw: String): DtcResult {
        val clean = raw.cleanObd()
        if (clean.contains("NODATA") || clean.contains("UNABLE") || clean.contains("ERROR")) {
            return DtcResult.Error("Блок не поддерживает UDS")
        }
        if (clean.contains("7F19")) return DtcResult.Error("UDS service не поддерживается")

        val dtcs = mutableSetOf<String>()

        // Собираем hex-данные после маркера 5902
        val tokens = raw.trim().split(Regex("[\\s\\r\\n]+"))
        for (token in tokens) {
            val hex = token.replace(Regex("^\\d+:"), "")
                .replace(Regex("[^0-9A-Fa-f]"), "").uppercase()
            if (!hex.contains("5902")) continue
            val idx = hex.indexOf("5902")
            // После 5902 идёт 1 байт availabilityMask, затем записи по 4 байта (DTC3 + status1)
            val payload = hex.substring(idx + 4)
            if (payload.length >= 2) {
                val data = payload.substring(2) // пропускаем availabilityMask (1 байт = 2 hex)
                parseUdsDtcRecords(data, dtcs)
            }
        }

        // Fallback: склеенный clean
        if (dtcs.isEmpty()) {
            val idx = clean.indexOf("5902")
            if (idx >= 0) {
                val payload = clean.substring(idx + 4)
                if (payload.length >= 2) {
                    parseUdsDtcRecords(payload.substring(2), dtcs)
                }
            }
        }

        return when {
            dtcs.isEmpty() && clean.contains("5902") -> DtcResult.NoDtcs
            dtcs.isEmpty() -> DtcResult.Error("Нет ответа UDS")
            else -> DtcResult.DtcList(dtcs.toList())
        }
    }

    /**
     * Парсит записи UDS DTC: каждая запись = 3 байта DTC + 1 байт статус (8 hex символов).
     * Первые 2 байта DTC кодируются как OBD2 (decodeDtc); 3-й — Failure Type Byte.
     * Если FTB != 0, к коду добавляется суффикс `-XX` (напр. `P0068-17`).
     *
     * **Эвристика:** у большинства ЭБУ так совпадает с практикой сканеров; полный 24-битный DTC
     * по ISO 15031-6 на редких блоках теоретически может отличаться — сверять по логам при сомнениях.
     */
    internal fun parseUdsDtcRecords(data: String, out: MutableSet<String>) {
        var i = 0
        while (i + 8 <= data.length) {
            val dtcHex = data.substring(i, i + 4)     // 2 байта DTC (как в OBD2)
            val ftbHex = data.substring(i + 4, i + 6)  // 1 байт FTB
            @Suppress("UNUSED_VARIABLE")
            val statusHex = data.substring(i + 6, i + 8) // 1 байт статус (зарезервирован для фильтрации)
            if (dtcHex != "0000" && (dtcHex != "FFFF")) {
                val base = decodeDtc(dtcHex)
                val ftb = ftbHex.toIntOrNull(16) ?: 0
                val code = if (ftb != 0) "$base-${ftbHex.uppercase()}" else base
                out.add(code)
            }
            i += 8
        }
    }

    // ─────────────────────────── PENDING DTCs (MODE 07) ──────────────────────

    /**
     * Читает ожидающие коды неисправностей (Mode 07, Pending DTC).
     *
     * Ожидающие коды фиксируются ЭБУ в текущем ездовом цикле, но становятся
     * постоянными (Mode 03) только после нескольких подряд подтверждений.
     * Полезно для ранней диагностики: ошибка есть, но лампа Check Engine ещё
     * не горит.
     *
     * Протокол аналогичен Mode 03, но ЭБУ отвечает маркером "47" вместо "43".
     * Отсутствие маркера = нормальная ситуация (ожидающих кодов нет).
     */
    suspend fun readPendingDtcs(): DtcResult = ioMutex.withLock { withContext(Dispatchers.IO) {
        try {
            warmupIfNeeded()
            drainInput()
            sendRaw("07")
            val raw = readUntilPrompt()
            val result = parseDtcResponse(
                responseMarker      = "47",
                raw                 = raw,
                missingMarkerResult = DtcResult.NoDtcs,
            )
            info(TAG, "readPendingDtcs → $result")
            result
        } catch (e: Exception) {
            err(TAG, "readPendingDtcs() error", e)
            DtcResult.Error(e.message ?: "Ошибка")
        }
    } }

    /**
     * Постоянные эмиссионные DTC (Mode 0A, Permanent DTC / PDTC).
     *
     * Часто поддерживается на авто под USA OBD-II (≈2010+); на многих EU-машинах — NO DATA.
     * Формат ответа как у Mode 03, маркер положительного ответа `4A`.
     */
    suspend fun readPermanentDtcs(): DtcResult = ioMutex.withLock { withContext(Dispatchers.IO) {
        try {
            warmupIfNeeded()
            drainInput()
            sendRaw("0A")
            val raw = readUntilPrompt()
            val clean = raw.cleanObd()
            val result = when {
                clean.contains("NODATA") || clean.contains("UNABLE") ||
                clean.contains("ERROR") && !clean.contains("4A") -> DtcResult.NoDtcs
                else -> parseDtcResponse(
                    responseMarker      = "4A",
                    raw                 = raw,
                    missingMarkerResult = DtcResult.NoDtcs,
                )
            }
            info(TAG, "readPermanentDtcs → $result")
            result
        } catch (e: Exception) {
            err(TAG, "readPermanentDtcs() error", e)
            DtcResult.Error(e.message ?: "Ошибка")
        }
    } }

    // ─────────────────────────── FREEZE FRAME (MODE 02) ──────────────────────

    /**
     * Читает снимок параметров в момент появления первой/приоритетной ошибки (Mode 02).
     *
     * ЭБУ хранит один freeze frame — состояние датчиков в момент, когда была
     * зафиксирована наиболее приоритетная неисправность (обычно первая).
     *
     * Формат запроса: "02 [PID]\r"
     *   Ответ: "42 [PID] [байты данных]..."
     *   Декодирование байт данных идентично Mode 01 (те же PIDs).
     *
     * Каждый параметр запрашивается отдельно, т.к. ELM327 не поддерживает
     * мульти-PID в Mode 02. Параметр, который ЭБУ не поддерживает, вернёт
     * "NO DATA" — он просто остаётся null.
     */
    suspend fun readFreezeFrame(): FreezeFrameData = ioMutex.withLock { withContext(Dispatchers.IO) {
        var dtcCode:      String? = null
        var rpm:          Int?   = null
        var speed:        Int?   = null
        var coolantTemp:  Int?   = null
        var engineLoad:   Float? = null
        var throttle:     Float? = null
        var shortFuelTrim:Float? = null
        var longFuelTrim: Float? = null
        var map:          Int?   = null
        var iat:          Int?   = null
        var voltage:      Float? = null
        var fuelStatus:   String? = null

        suspend fun query(cmd: String, marker: String, timeoutMs: Long = sensorTimeout): List<Int>? {
            drainInput()
            sendRaw(cmd); delay(100)
            val clean = readUntilPrompt(timeoutMs).cleanObd()
            val idx = clean.indexOf(marker)
            if (idx < 0) return null
            return clean.substring(idx).chunked(2).mapNotNull { it.toIntOrNull(16) }
        }

        warmupIfNeeded()

        // PID 02: DTC, вызвавший freeze frame — 2 байта = стандартный DTC
        query("0202", "4202", timeoutMs = 2000L)?.let { b ->
            if (b.size >= 4) {
                val block = "%02X%02X".format(b[2], b[3])
                if (block != "0000") dtcCode = decodeDtc(block)
            }
        }

        // PID 03: Fuel System Status — 2 байта (статус 1-й и 2-й системы)
        query("0203", "4203")?.let { b ->
            if (b.size >= 3) fuelStatus = decodeFuelSystemStatus(b[2], if (b.size >= 4) b[3] else 0)
        }

        query("020C", "420C")?.let { b -> if (b.size >= 4) rpm = ((b[2] * 256) + b[3]) / 4 }
        query("020D", "420D")?.let { b -> if (b.size >= 3) speed = b[2] }
        query("0205", "4205")?.let { b -> if (b.size >= 3) coolantTemp = b[2] - 40 }
        query("0204", "4204")?.let { b -> if (b.size >= 3) engineLoad = b[2] * 100.0f / 255.0f }
        query("0211", "4211")?.let { b -> if (b.size >= 3) throttle = b[2] * 100.0f / 255.0f }
        query("0206", "4206")?.let { b -> if (b.size >= 3) shortFuelTrim = (b[2] - 128) * 100.0f / 128.0f }
        query("0207", "4207")?.let { b -> if (b.size >= 3) longFuelTrim = (b[2] - 128) * 100.0f / 128.0f }
        query("020B", "420B")?.let { b -> if (b.size >= 3) map = b[2] }
        query("020F", "420F")?.let { b -> if (b.size >= 3) iat = b[2] - 40 }
        query("0242", "4242")?.let { b -> if (b.size >= 4) voltage = ((b[2] * 256) + b[3]) / 1000.0f }

        FreezeFrameData(dtcCode, rpm, speed, coolantTemp, engineLoad, throttle, shortFuelTrim, longFuelTrim, map, iat, voltage, fuelStatus)
    } }

    // ─────────────────────────── READINESS (MODE 01 PID 01) ──────────────────

    /**
     * Читает статус готовности систем мониторинга ОБД2 (Mode 01, PID 0x01).
     *
     * ЭБУ отвечает 4 байтами (A, B, C, D):
     *   Байт A: бит 7 = MIL on/off, биты 6:0 = количество ошибок.
     *   Байт B: биты 0-2 (суппортируется) / биты 4-6 (завершено):
     *     0 / 4 — мониторинг пропусков воспламенения
     *     1 / 5 — система топлива
     *     2 / 6 — общие компоненты
     *   Байты C, D: дополнительные мониторы (катализатор, EVAP, O₂ и др.)
     *     Бит supp=1 → монитор поддерживается.
     *     Бит ready=0 → монитор завершил тест ("готов").
     *     Бит ready=1 → монитор ещё не завершил тест ("не готов").
     */
    suspend fun readReadiness(): List<ReadinessMonitor> = ioMutex.withLock { withContext(Dispatchers.IO) {
        try {
            warmupIfNeeded()
            drainInput()
            sendRaw("0101"); delay(200)
            val clean = readUntilPrompt(2000).cleanObd()
            val idx = clean.indexOf("4101")
            if (idx < 0) return@withContext emptyList()
            val bytes = clean.substring(idx).chunked(2).mapNotNull { it.toIntOrNull(16) }
            // Структура ответа: [41, 01, A, B, C, D] — нам нужны байты B, C, D
            if (bytes.size < 6) return@withContext emptyList()
            val byteB = bytes[3]
            val byteC = bytes[4]
            val byteD = bytes[5]
            val list  = mutableListOf<ReadinessMonitor>()

            // supportBit = 1 означает, что монитор присутствует в этом ЭБУ.
            // readyBit = 0 означает "завершён/готов" (инвертированная логика OBD2!).
            fun add(source: Int, supportBit: Int, readyBit: Int, name: String) {
                if (source and supportBit != 0)
                    list.add(ReadinessMonitor(name, ready = source and readyBit == 0))
            }

            // Байт B — три основных монитора (присутствуют на всех машинах)
            add(byteB, 0x01, 0x10, "Пропуски воспламенения")
            add(byteB, 0x02, 0x20, "Система топлива")
            add(byteB, 0x04, 0x40, "Компоненты системы")
            // Байт C — мониторы выхлопа и пара топлива
            add(byteC, 0x01, 0x10, "Каталитический нейтрализатор")
            add(byteC, 0x02, 0x20, "Подогрев катализатора")
            add(byteC, 0x04, 0x40, "Система EVAP")
            add(byteC, 0x08, 0x80.toInt(), "Вторичный воздух")
            // Байт D — мониторы кислородных датчиков и EGR
            add(byteD, 0x01, 0x10, "Кислородный датчик")
            add(byteD, 0x02, 0x20, "Нагрев O₂ датчика")
            add(byteD, 0x04, 0x40, "EGR / VVT система")
            list
        } catch (e: Exception) {
            err(TAG, "readReadiness() failed", e)
            emptyList()
        }
    } }

    // ─────────────────────────── OTHER ECUs (CAN ADDRESSING) ─────────────────

    /**
     * Пробует считать DTC с нестандартных блоков: ABS, SRS, TCM, BCM.
     *
     * Работает **только на CAN-шине** (большинство машин с 2008+).
     * Старые протоколы (K-Line, ISO 9141) не поддерживают адресацию блоков.
     *
     * Механизм: команда [ATSH] устанавливает 11-битный CAN-заголовок запроса.
     * ELM327 отправляет "03\r" (Mode 03 = чтение DTC) с этим заголовком;
     * ЭБУ целевого блока отвечает на canId = txHeader + 8 (стандарт ISO 15765).
     *
     * После опроса всех блоков ATSH восстанавливается в 7DF (broadcast).
     *
     * Типичные CAN-адреса (могут отличаться у разных производителей):
     *   7DF — broadcast (OBD2 standard), ответ от 7E8
     *   7E0 — Engine ECU,         ответ 7E8
     *   7E1 — TCM / АКПП,         ответ 7E9
     *   7B0 — ABS / ESP,          ответ 7B8
     *   7D0 — SRS / Airbag,       ответ 7D8
     *   7E4 — BCM / Кузов,        ответ 7EC
     *
     * По [vehicleInfo] (марка / WMI) добавляются марочные адреса, см. [BrandEcuHints]
     * (напр. VW Group: 710/714/7B6; Toyota: 750; Ford/Lincoln: 720/724/726/732).
     *
     * @param vehicleInfo если null — только универсальные четыре блока.
     */
    /**
     * @param manualMakeHint марка из ручного профиля — если VIN пустой, всё равно добавляет марочные адреса (EPS, gateway…).
     */
    suspend fun readOtherEcuDtcs(
        vehicleInfo: VehicleInfo? = null,
        manualMakeHint: String? = null,
    ): List<EcuDtcResult> = ioMutex.withLock { withContext(Dispatchers.IO) {
        val ecus = BrandEcuHints.ecuProbeList(vehicleInfo?.detectedMake, vehicleInfo?.vin, manualMakeHint)

        warmupIfNeeded()    // K-Line сессия должна быть активна перед опросом блоков
        val results = mutableListOf<EcuDtcResult>()
        for (ecu in ecus) {
            try {
                sendRaw("ATSH ${ecu.txHeader}"); delay(100); consumeAtResponse()

                // ── Шаг 1: стандартный OBD2 Mode 03 ────────────────────────────
                sendRaw("03")
                val raw   = readUntilPrompt(1500)
                val clean = raw.cleanObd()
                val blockResponds = !clean.contains("NODATA") && !clean.contains("UNABLE") &&
                    !clean.contains("ERROR") && clean.isNotEmpty()
                var confirmed = when {
                    !blockResponds -> DtcResult.Error("Блок не отвечает")
                    clean.contains("43") -> parseDtcResponse("43", raw)
                    else -> DtcResult.Error("Нет ответа")
                }
                var pending: DtcResult = DtcResult.NoDtcs
                var permanent: DtcResult = DtcResult.NoDtcs
                val mode03Failed = !blockResponds || confirmed is DtcResult.Error

                if (blockResponds && !mode03Failed) {
                    try {
                        drainInput()
                        sendRaw("07")
                        val raw07 = readUntilPrompt(1500)
                        val clean07 = raw07.cleanObd()
                        if (clean07.contains("47")) pending = parseDtcResponse("47", raw07)
                    } catch (_: Exception) { /* optional */ }
                    try {
                        drainInput()
                        sendRaw("0A")
                        val raw0A = readUntilPrompt(1500)
                        val clean0A = raw0A.cleanObd()
                        if (clean0A.contains("4A")) permanent = parseDtcResponse("4A", raw0A)
                    } catch (_: Exception) { /* optional */ }
                }

                // ── Шаг 2: UDS 0x19 fallback (только CAN) ──────────────────────
                // Если Mode 03 не поддерживается (NO DATA / 7F0311 / нет маркера 43),
                // пробуем UDS ReadDTCInformation: 10 03 (extended session) + 19 02 FF.
                if (mode03Failed && isCanProtocol) {
                    try {
                        drainInput()
                        sendRaw("10 03"); delay(200)
                        readUntilPrompt(1500) // 50 03 = accepted; 7F 10 XX = отказ — продолжаем в любом случае
                        drainInput()
                        sendRaw("19 02 FF")
                        val rawUds = readUntilPrompt(3000)
                        val udsResult = parseUdsDtcResponse(rawUds)
                        if (udsResult !is DtcResult.Error) {
                            confirmed = udsResult
                            dbg(TAG, "UDS 0x19 OK for ${ecu.txHeader}: $udsResult")
                        } else {
                            dbg(TAG, "UDS 0x19 failed for ${ecu.txHeader}: $udsResult")
                        }
                    } catch (e: Exception) {
                        dbg(TAG, "UDS 0x19 exception for ${ecu.txHeader}: ${e.message}")
                    }
                }

                results.add(EcuDtcResult(ecu.name, ecu.txHeader, confirmed, pending, permanent))
            } catch (_: Exception) {
                results.add(EcuDtcResult(ecu.name, ecu.txHeader, DtcResult.Error("Ошибка связи")))
            }
            drainInput()
        }
        // ── Восстанавливаем состояние адаптера ───────────────────────────────────
        restoreElmAfterAtsh(tag = "readOtherEcuDtcs")
        results
    } }

    /**
     * После `ATSH` на другой CAN-ID: `ATD` + настройки ELM + `0100` (восстановление K-Line / сессии).
     */
    private suspend fun restoreElmAfterAtsh(tag: String) {
        try {
            sendRaw("ATD");   delay(200); consumeAtResponse()
            sendRaw("ATE0");  delay(100); consumeAtResponse()
            sendRaw("ATL0");  delay(100); consumeAtResponse()
            sendRaw("ATH0");  delay(100); consumeAtResponse()
            sendRaw("ATS0");  delay(100); consumeAtResponse()
            sendRaw("0100")
            dbg(TAG, "$tag warmup: '${readUntilPrompt(9000).cleanObd()}'")
            drainInput()
            dbg(TAG, "$tag: adapter state fully restored")
        } catch (e: Exception) {
            warn(TAG, "$tag: restore failed: ${e.message}")
        }
    }

    private suspend fun elmProtocolDescription(): String = try {
        drainInput()
        sendRaw("ATDP"); delay(120)
        readUntilPrompt(1000)
    } catch (_: Exception) { "" }

    /**
     * UDS 0x22 на адресах комбинации приборов (см. [ClusterOdometerProbes], марки в [BrandEcuHints]).
     * Перед отдельными пробами возможен prelude (`10 03` extended session). Только CAN; в конце [restoreElmAfterAtsh].
     */
    private suspend fun tryReadClusterOdometerKm(detectedMake: String?, vin: String?): Pair<Int?, String?> {
        val proto = elmProtocolDescription().uppercase()
        if (!proto.contains("CAN") && !proto.contains("15765")) return null to null
        val group = BrandEcuHints.classify(detectedMake, vin)
        val probes = ClusterOdometerProbes.probesFor(group)
        if (probes.isEmpty()) return null to null
        try {
            for (probe in probes) {
                try {
                    sendRaw("ATSH ${probe.txHeader}"); delay(120); consumeAtResponse()
                    drainInput()
                    for (pre in probe.preludeHex) {
                        drainInput()
                        sendRaw(pre); delay(200)
                        readUntilPrompt(1200)
                        drainInput()
                    }
                    sendRaw(probe.requestHex); delay(280)
                    val raw = readUntilPrompt(4000)
                    val clean = normalizeElmMode09Raw(raw).cleanObd()
                    if (clean.contains("7F22") || clean.contains("7F31")) continue
                    val bytes = ClusterOdometerProbes.extractPayloadAfterMarker(clean, probe.positiveMarker)
                        ?: continue
                    val km = ClusterOdometerProbes.parseOdometerKm(bytes) ?: continue
                    dbg(TAG, "Cluster odo OK: ${probe.groupLabel} ${probe.txHeader} ${probe.requestHex} -> $km km")
                    return km to "${probe.groupLabel} CAN ${probe.txHeader} UDS ${probe.requestHex}"
                } catch (_: Exception) { /* next probe */ }
            }
        } finally {
            restoreElmAfterAtsh(tag = "clusterOdo")
        }
        return null to null
    }

    /** Имя ЭБУ АКПП (Mode 09/0A на `7E1`), только если шина CAN — иначе `ATSH` портит K-Line. */
    private suspend fun tryReadTcmEcuName(): String? {
        val proto = elmProtocolDescription().uppercase()
        if (!proto.contains("CAN") && !proto.contains("15765")) return null
        return try {
            sendRaw("ATSH 7E1"); delay(120); consumeAtResponse()
            drainInput()
            sendRaw("090A"); delay(200)
            val raw = readUntilPrompt(2000)
            parseEcuName(raw)
        } catch (_: Exception) {
            null
        } finally {
            restoreElmAfterAtsh(tag = "tryReadTcmEcuName")
        }
    }

    // ─────────────────────────── CLEAR DTCs (MODE 04) ────────────────────────

    /**
     * Сбрасывает все постоянные и ожидающие коды, гасит лампу Check Engine (Mode 04).
     *
     * ЭБУ также сбрасывает счётчики "Distance with MIL on" и Freeze Frame.
     * Возвращает true, если в ответе присутствует маркер "44" (positive response).
     */
    suspend fun clearDtcs(): Boolean = ioMutex.withLock { withContext(Dispatchers.IO) {
        try {
            warmupIfNeeded()
            drainInput()
            sendRaw("04")
            val raw = readUntilPrompt()
            val ok = raw.cleanObd().contains("44")
            // Mode 04 вызывает внутренний сброс ЭБУ — K-Line сессия умирает.
            // Восстанавливаем сессию, чтобы следующий readDtcs() не получил NO DATA.
            postClearWarmup()
            ok
        } catch (e: Exception) {
            err(TAG, "clearDtcs() error", e); false
        }
    } }

    // ─────────────────────────── VEHICLE INFO (MODE 09) ──────────────────────

    /**
     * Запрашивает максимум **универсальных** данных по OBD2 (без фирменных UDS):
     *
     * Mode 09: VIN (02), маска поддерживаемых PID (00), Calibration ID (03), CVN (04),
     * при поддержке — сырые данные 01, 05–09; имя ЭБУ двигателя (0A).
     * На **CAN** дополнительно: имя ЭБУ КПП (`ATSH 7E1` + 090A), затем восстановление адаптера.
     *
     * Mode 01: тип OBD (1C), тип топлива (51), пробег MIL (21), после сброса DTC (31).
     *
     * **Одометр щитка (экспериментально):** на CAN — цепочка UDS `22` по группе марки ([BrandEcuHints] + [ClusterOdometerProbes]),
     * при необходимости prelude `10 03`. **0x27** (SecurityAccess) и **0x2E** (запись) не используются.
     */
    suspend fun readVehicleInfo(): VehicleInfo = ioMutex.withLock { withContext(Dispatchers.IO) {
        var vin: String? = null
        var ecuName: String? = null
        var distanceMil: Int?
        var distanceCleared: Int?
        var mode09SupportMaskHex: String? = null
        var calibrationId: String? = null
        var cvnHex: String? = null
        var mode09ExtrasSummary: String? = null
        var obdStandardLabel: String? = null
        var fuelTypeLabel: String? = null
        var transmissionEcuName: String? = null
        var clusterOdometerKm: Int? = null
        var clusterOdometerNote: String? = null

        // VIN — мультифреймовый ответ, нужен увеличенный таймаут
        try {
            warmupIfNeeded()
            drainInput()
            sendRaw("0902"); delay(200)
            val raw = readUntilPrompt(3000)
            dbg(TAG, "VIN raw: '$raw'")
            vin = parseVin(raw)
        } catch (e: Exception) { warn(TAG, "VIN read failed: ${e.message}") }

        var mode09Mask: ByteArray? = null
        try {
            drainInput()
            sendRaw("0900"); delay(150)
            val c00 = readUntilPrompt(2000).cleanObd()
            mode09Mask = ObdVehicleInfoParse.mode09SupportMask(c00)
            mode09SupportMaskHex = mode09Mask?.joinToString("") { b ->
                (b.toInt() and 0xFF).toString(16).uppercase().padStart(2, '0')
            }
        } catch (e: Exception) { warn(TAG, "Mode 09/00 failed: ${e.message}") }

        try {
            drainInput()
            sendRaw("0903"); delay(200)
            calibrationId = ObdVehicleInfoParse.bestAsciiAfterMarker(
                readUntilPrompt(2500).cleanObd(), "4903", maxChars = 96,
            )
        } catch (e: Exception) { warn(TAG, "Calibration ID failed: ${e.message}") }

        try {
            drainInput()
            sendRaw("0904"); delay(200)
            cvnHex = ObdVehicleInfoParse.cvnHexLine(readUntilPrompt(2500).cleanObd())
        } catch (e: Exception) { warn(TAG, "CVN failed: ${e.message}") }

        val extraParts = mutableListOf<String>()
        for (pid in listOf(1, 5, 6, 7, 8, 9)) {
            if (mode09Mask != null && !ObdVehicleInfoParse.isMode09PidSupported(mode09Mask, pid)) continue
            try {
                drainInput()
                val cmd = "09" + pid.toString(16).uppercase().padStart(2, '0')
                sendRaw(cmd); delay(120)
                val clean = readUntilPrompt(1500).cleanObd()
                val marker = "49" + pid.toString(16).uppercase().padStart(2, '0')
                val hex = ObdVehicleInfoParse.hexPayloadAfterMarker(clean, marker, maxDataBytes = 48)
                if (hex != null) extraParts.add("09/${pid.toString(16).uppercase().padStart(2, '0')}:$hex")
            } catch (_: Exception) { /* optional */ }
        }
        if (extraParts.isNotEmpty()) {
            mode09ExtrasSummary = extraParts.joinToString(" ").take(500)
        }

        try {
            drainInput()
            sendRaw("090A"); delay(200)
            val raw = readUntilPrompt(2000)
            ecuName = parseEcuName(raw)
        } catch (e: Exception) { warn(TAG, "ECU name failed: ${e.message}") }

        try {
            drainInput()
            sendRaw("011C"); delay(100)
            val b = ObdVehicleInfoParse.singleByteMode01(readUntilPrompt(1500).cleanObd(), "1C")
            obdStandardLabel = b?.let { ObdStandardLabels.obdStandard1c(it) }
        } catch (e: Exception) { warn(TAG, "OBD standard 1C failed: ${e.message}") }

        try {
            drainInput()
            sendRaw("0151"); delay(100)
            val b = ObdVehicleInfoParse.singleByteMode01(readUntilPrompt(1500).cleanObd(), "51")
            fuelTypeLabel = b?.let { ObdStandardLabels.fuelType51(it) }
        } catch (e: Exception) { warn(TAG, "Fuel type 51 failed: ${e.message}") }

        suspend fun readTwoByteMode1(pidCmd: String, marker: String): Int? = try {
            drainInput()
            sendRaw(pidCmd); delay(100)
            val clean = readUntilPrompt(1500).cleanObd()
            parseMode01TwoByteFromCleaned(clean, marker)
        } catch (_: Exception) { null }

        distanceMil     = readTwoByteMode1("0121", "4121")
        distanceCleared = readTwoByteMode1("0131", "4131")

        var fuelSystemStatus: String? = null
        var warmUpsCleared: Int? = null
        var timeSinceClearedMin: Int? = null

        try {
            drainInput()
            sendRaw("0103"); delay(100)
            val clean03 = readUntilPrompt(1500).cleanObd()
            val idx03 = clean03.indexOf("4103")
            if (idx03 >= 0) {
                val hex = clean03.substring(idx03).chunked(2).mapNotNull { it.toIntOrNull(16) }
                if (hex.size >= 4) fuelSystemStatus = decodeFuelSystemStatus(hex[2], hex[3])
                else if (hex.size >= 3) fuelSystemStatus = decodeFuelSystemStatus(hex[2], 0)
            }
        } catch (_: Exception) { /* optional */ }

        try {
            drainInput()
            sendRaw("0130"); delay(100)
            val clean30 = readUntilPrompt(1500).cleanObd()
            val idx30 = clean30.indexOf("4130")
            if (idx30 >= 0) {
                val hex = clean30.substring(idx30).chunked(2).mapNotNull { it.toIntOrNull(16) }
                if (hex.size >= 3) warmUpsCleared = hex[2]
            }
        } catch (_: Exception) { /* optional */ }

        timeSinceClearedMin = readTwoByteMode1("014E", "414E")

        val make     = vin?.let { decodeVinMake(it) }
        val year     = vin?.let { decodeVinYear(it) }
        val imperial = vin?.firstOrNull()?.let { it in '1'..'5' } ?: false
        val vds      = vin?.takeIf { it.length >= 9 }?.uppercase()?.substring(3, 9)
        val brandGrp = BrandEcuHints.classify(make, vin).name

        try {
            val (km, note) = tryReadClusterOdometerKm(make, vin)
            clusterOdometerKm = km
            clusterOdometerNote = note
        } catch (e: Exception) { warn(TAG, "Cluster odometer failed: ${e.message}") }

        try {
            transmissionEcuName = tryReadTcmEcuName()
        } catch (e: Exception) { warn(TAG, "TCM ECU name failed: ${e.message}") }

        VehicleInfo(
            vin                    = vin,
            detectedMake           = make,
            detectedYear           = year,
            ecuName                = ecuName,
            calibrationId          = calibrationId,
            cvnHex                 = cvnHex,
            mode09SupportMaskHex   = mode09SupportMaskHex,
            mode09ExtrasSummary    = mode09ExtrasSummary,
            obdStandardLabel       = obdStandardLabel,
            fuelTypeLabel          = fuelTypeLabel,
            transmissionEcuName    = transmissionEcuName,
            clusterOdometerKm      = clusterOdometerKm,
            clusterOdometerNote    = clusterOdometerNote,
            vinVehicleDescriptor   = vds,
            diagnosticBrandGroup   = brandGrp,
            distanceMil            = distanceMil,
            distanceCleared        = distanceCleared,
            fuelSystemStatus       = fuelSystemStatus,
            warmUpsCleared         = warmUpsCleared,
            timeSinceClearedMin    = timeSinceClearedMin,
            usesImperialUnits      = imperial,
        )
    } }

    /**
     * Нормализует сырой ответ ELM327 для Mode 09 (VIN / ECU name): убирает PCI,
     * индексы ISO-TP кадров (`0:`, `1:`, …) без порчи hex-последовательностей.
     *
     * **Почему нельзя сначала убрать все пробелы и regex `[0-9]+:`:**
     * после склейки появляются ложные совпадения вроде `4331:` внутри VIN (Toyota),
     * и парсер съедает полезные байты.
     */
    internal fun normalizeElmMode09Raw(raw: String): String {
        var s = raw.uppercase().substringBefore(">").trim()
        s = s.replace(Regex("SEARCHING\\.\\.\\.[^\\r\\n>]*", RegexOption.IGNORE_CASE), "")
        val parts = s.split(Regex("\\s+\\d{1,2}:\\s*"))
        val sb = StringBuilder()
        for ((i, part) in parts.withIndex()) {
            val t = part.trim()
            if (t.isEmpty()) continue
            // Первый фрагмент до `0:` часто только счётчик строки ELM (`014`)
            if (i == 0 && t.matches(Regex("^\\d{1,4}$"))) continue
            sb.append(t)
        }
        return sb.toString().replace(Regex("\\s+"), "")
    }

    /**
     * Парсит ответ на запрос VIN (Mode 09 PID 02).
     *
     * ELM327 возвращает ответ в формате ISO-TP:
     *   "014 0: 49 02 01 XX XX XX 1: XX XX … 2: XX …"
     * Кадры режутся по `\s+\d{1,2}:`, затем ищется маркер "4902".
     * После маркера идут данные: возможный счётчик "01" и 17×2 hex-символов.
     */
    internal fun parseVin(raw: String): String? {
        val clean = normalizeElmMode09Raw(raw)

        // Маркер 4902 = 0x49 (positive response Mode 09) + 0x02 (PID 02 = VIN)
        var idx = clean.indexOf("4902")
        if (idx < 0) return null
        idx += 4
        // Некоторые ЭБУ добавляют счётчик данных "01" перед самим VIN
        if (clean.length > idx + 2 && clean.substring(idx, idx + 2) == "01") idx += 2

        // Читаем байты → ASCII, фильтруем: только допустимые символы VIN (A-Z, 0-9, без I/O/Q)
        val vin = StringBuilder()
        var i = idx
        while (i + 1 < clean.length && vin.length < 17) {
            val byte = clean.substring(i, i + 2).toIntOrNull(16) ?: break
            val ch   = byte.toChar()
            if (ch.isLetterOrDigit() && ch != 'I' && ch != 'O' && ch != 'Q') vin.append(ch)
            i += 2
        }
        return if (vin.length == 17) vin.toString() else null
    }

    /**
     * Парсит ответ на запрос ECU Name (Mode 09 PID 0A).
     * Несколько ЭБУ могут ответить в одном буфере — берём самую длинную валидную строку.
     */
    private fun parseEcuName(raw: String): String? {
        val clean = normalizeElmMode09Raw(raw)
        var best: String? = null
        var from = 0
        while (from < clean.length) {
            val idx = clean.indexOf("490A", from)
            if (idx < 0) break
            val name = parseEcuNameFrom490A(clean, idx)
            if (name != null && (best == null || name.length > best.length)) best = name
            from = idx + 4
        }
        return best
    }

    private fun parseEcuNameFrom490A(clean: String, idx: Int): String? {
        var start = idx + 4
        if (clean.length > start + 2 && clean.substring(start, start + 2) == "01") start += 2
        // Multi-ECU: ограничиваем чтение до следующего маркера 490A,
        // иначе парсер захватывает мусор из соседних фреймов.
        val nextMarker = clean.indexOf("490A", start)
        val end = if (nextMarker > 0) nextMarker else clean.length
        val name = StringBuilder()
        var i = start
        while (i + 1 < end && name.length < 32) {
            val byte = clean.substring(i, i + 2).toIntOrNull(16) ?: break
            if (byte == 0) break
            val ch = byte.toChar()
            if (ch.code in 32..126) name.append(ch)
            i += 2
        }
        val s = name.toString().trim()
        return s.takeIf { it.length >= 2 && isPlausibleEcuName(it) }
    }

    private fun decodeFuelSystemStatus(byte1: Int, byte2: Int): String? {
        fun label(b: Int): String? = when (b) {
            0    -> null
            0x01 -> "Open loop (холодный)"
            0x02 -> "Closed loop (O₂)"
            0x04 -> "Open loop (нагрузка)"
            0x08 -> "Open loop (сбой)"
            0x10 -> "Closed loop (сбой O₂)"
            else -> "0x${b.toString(16).uppercase()}"
        }
        val parts = listOfNotNull(label(byte1), label(byte2))
        return parts.joinToString(" / ").takeIf { it.isNotEmpty() }
    }

    /** Отсекает мусор из ASCII Mode 09/0A (битая интерпретация бинарных данных). */
    private fun isPlausibleEcuName(s: String): Boolean {
        if (s.contains('&') || s.contains('\u007F')) return false
        val letters = s.count { it.isLetter() }
        if (letters < 3) return false
        if (s.count { it.isDigit() } > s.length / 2) return false
        return true
    }

    /**
     * Декодирует марку/завод из первых трёх символов VIN (WMI).
     * Используется широкая таблица [VinWmiTable] (Wikibooks WMI); при отсутствии кода — null.
     */
    internal fun decodeVinMake(vin: String): String? {
        if (vin.length < 3) return null
        return VinWmiTable.getMake(vin.substring(0, 3))
    }

    /**
     * Декодирует модельный год из 10-го символа VIN (индекс 9). SAE J1044: 30-летний цикл.
     *
     * - **Северная Америка** (WMI `1`–`5`): 7-й символ (индекс 6) — цифра ⇒ новый цикл (2010+),
     *   буква ⇒ старый (1980–2009).
     * - **Остальной мир**: выбирается интерпретация **ближе к текущему календарному году**
     *   (иначе у EU/RU VIN с буквой на 7-й позиции получался бы заведомо старый год, напр. `M` → 1991).
     */
    internal fun decodeVinYear(vin: String): String? {
        if (vin.length < 10) return null
        val u = vin.uppercase()
        val c10 = u[9]
        val pos7 = u[6]
        val wmi0 = u[0]
        val wmi3 = u.take(3)
        // WDB Mercedes: 10-й символ в европейском VIN не кодирует год
        if (wmi3 == "WDB") return null
        val pair = vinYearPair(c10) ?: return null
        val ref = java.util.Calendar.getInstance().get(java.util.Calendar.YEAR)
        val year = if (wmi0 in '1'..'5') {
            if (pos7.isDigit()) pair.second else pair.first
        } else {
            val a = kotlin.math.abs(pair.first - ref)
            val b = kotlin.math.abs(pair.second - ref)
            when {
                b < a -> pair.second
                a < b -> pair.first
                else -> pair.second
            }
        }
        return year.toString()
    }

    private fun vinYearPair(c: Char): Pair<Int, Int>? = when (c) {
        'A' -> 1980 to 2010; 'B' -> 1981 to 2011; 'C' -> 1982 to 2012; 'D' -> 1983 to 2013
        'E' -> 1984 to 2014; 'F' -> 1985 to 2015; 'G' -> 1986 to 2016; 'H' -> 1987 to 2017
        'J' -> 1988 to 2018; 'K' -> 1989 to 2019; 'L' -> 1990 to 2020; 'M' -> 1991 to 2021
        'N' -> 1992 to 2022; 'P' -> 1993 to 2023; 'R' -> 1994 to 2024; 'S' -> 1995 to 2025
        'T' -> 1996 to 2026; 'V' -> 1997 to 2027; 'W' -> 1998 to 2028; 'X' -> 1999 to 2029
        'Y' -> 2000 to 2030
        '1' -> 2001 to 2031; '2' -> 2002 to 2032; '3' -> 2003 to 2033; '4' -> 2004 to 2034
        '5' -> 2005 to 2035; '6' -> 2006 to 2036; '7' -> 2007 to 2037; '8' -> 2008 to 2038
        '9' -> 2009 to 2039
        else -> null
    }

    // ─────────────────────────── LIVE SENSOR (MODE 01) ───────────────────────

    /**
     * Запрашивает один PID в режиме текущих данных (Mode 01) и возвращает [SensorReading].
     *
     * Формат запроса: команда вида "010C\r" → "41 0C 1A F8 >"
     *   41 = 0x40 | 0x01 — положительный ответ Mode 01
     *   0C = эхо PID
     *   1A F8 = данные; RPM = (0x1A × 256 + 0xF8) / 4 = 1726 об/мин
     *
     * Таймаут [sensorTimeout] зависит от транспорта: 800 мс (Wi-Fi) или 1500 мс (BT/K-Line).
     * Если ЭБУ ответил "NO DATA" или "?" — PID не поддерживается этой машиной,
     * возвращается статус UNSUPPORTED (не ошибка, просто скрывает карточку).
     */
    suspend fun pollSensor(pid: ObdPid): SensorReading {
        if (!isConnected) return SensorReading(pid, null, SensorStatus.DISCONNECTED)
        // tryLock: если DTC-скан держит мьютекс, немедленно возвращаем ERROR (N/A в UI),
        // не блокируя весь цикл мониторинга на время скана ошибок.
        if (!ioMutex.tryLock()) return SensorReading(pid, null, SensorStatus.ERROR)
        return try {
            withContext(Dispatchers.IO) {
                warmupIfNeeded()    // восстанавливаем K-Line сессию если пауза >3.5 с
                drainInput()
                sendRaw(pid.command)
                parseSensorResponse(pid, readUntilPrompt(sensorTimeout))
            }
        } catch (e: Exception) {
            warn(TAG, "pollSensor ${pid.command} error: ${e.message}")
            SensorReading(pid, null, SensorStatus.ERROR)
        } finally {
            ioMutex.unlock()
        }
    }

    private fun parseSensorResponse(pid: ObdPid, raw: String): SensorReading {
        val clean = raw.cleanObd()

        // ELM327 всё ещё определяет протокол — не считаем это неподдерживаемым PID
        if (clean.contains("SEARCHING")) return SensorReading(pid, null, SensorStatus.ERROR)

        // ELM327 отвечает этими строками, если ЭБУ не поддерживает PID
        if (clean.contains("NODATA") || clean.contains("UNABLE") ||
            clean.contains("ERROR") || clean == "?" || clean.isEmpty()
        ) {
            return SensorReading(pid, null, SensorStatus.UNSUPPORTED)
        }

        // Ищем начало ответа "41" (положительный ответ Mode 01)
        val idx = clean.indexOf("41")
        if (idx < 0) return SensorReading(pid, null, SensorStatus.UNSUPPORTED)

        val bytes = clean.substring(idx)
            .chunked(2)
            .mapNotNull { it.toIntOrNull(16) }

        // Минимум нужно 3 байта: [41, PID, data_byte]
        if (bytes.size < 3) return SensorReading(pid, null, SensorStatus.UNSUPPORTED)

        return try {
            val value  = pid.decode(bytes)
            val status = when {
                pid.maxWarning != null && value > pid.maxWarning -> SensorStatus.WARNING
                pid.minWarning != null && value < pid.minWarning -> SensorStatus.WARNING
                else                                              -> SensorStatus.OK
            }
            SensorReading(pid, value, status)
        } catch (_: Exception) {
            SensorReading(pid, null, SensorStatus.ERROR)
        }
    }

    // ─────────────────────────── IO HELPERS ─────────────────────────────────

    /**
     * Отправляет AT/OBD2-команду в поток.
     * ELM327 требует завершающий `\r` (Carriage Return) — без него команда игнорируется.
     * ISO 8859-1 используется вместо UTF-8, т.к. ELM327 — ASCII-устройство.
     */
    private fun sendRaw(command: String) {
        val out = output ?: throw IllegalStateException("Нет соединения")
        out.write("$command\r".toByteArray(Charsets.ISO_8859_1))
        out.flush()
        dbg(TAG, ">> $command")
        // Обновляем таймстамп только для OBD2-команд (не AT).
        // K-Line P3_Max отсчитывается от последней ECU-транзакции, AT-команды его не сбрасывают.
        if (!command.startsWith("AT", ignoreCase = true)) {
            lastEcuCommandMs = System.currentTimeMillis()
        }
    }

    /**
     * Читает байты из потока до появления символа `>` (prompt ELM327) или таймаута.
     *
     * ELM327 всегда завершает ответ символом `>`, который означает готовность
     * принять следующую команду.
     *
     * **Bluetooth (RFCOMM)**: `available()` корректно возвращает число байт в буфере,
     * поэтому используем неблокирующий опрос с паузой [POLL_INTERVAL_MS].
     *
     * **Wi-Fi (TCP)**: `available()` для TCP-потоков почти всегда возвращает 0,
     * даже когда данные уже пришли — Java буферизует TCP иначе. Поэтому устанавливаем
     * `soTimeout` на сокете и делаем блокирующий `read()`. `SocketTimeoutException`
     * означает нормальный выход по таймауту (ответа больше нет).
     */
    private suspend fun readUntilPrompt(timeoutMs: Long = READ_TIMEOUT_MS): String =
        withContext(Dispatchers.IO) {
            val buf      = StringBuilder()
            val stream   = input ?: return@withContext ""
            val deadline = System.currentTimeMillis() + timeoutMs
            try {
                if (isWifi) {
                    wifiSocket?.soTimeout = timeoutMs.toInt()
                }
                loop@ while (System.currentTimeMillis() < deadline) {
                    if (isWifi || stream.available() > 0) {
                        val byte = try {
                            stream.read()
                        } catch (_: java.net.SocketTimeoutException) {
                            break@loop      // Wi-Fi: таймаут = ответ завершён
                        }
                        if (byte == -1) break@loop      // поток закрыт
                        val ch = byte.toChar()
                        if (ch == '>') break@loop       // конец ответа ELM327
                        buf.append(ch)
                    } else {
                        delay(POLL_INTERVAL_MS)         // BT: ждём следующую порцию байт
                    }
                }
            } catch (e: Exception) {
                warn(TAG, "readUntilPrompt: ${e.message}")
            }
            val result = buf.toString()
            // Логируем ответ (укорачиваем длинные ответы для читаемости)
            val preview = result.replace(Regex("[\r\n]"), " ").trim().let {
                if (it.length > 120) it.take(120) + "…" else it
            }
            dbg(TAG, "<< ${preview.ifEmpty { "(empty)" }}")
            result
        }

    /**
     * Поглощает ответ на AT-команду (например "OK>") после её выполнения.
     *
     * **Wi-Fi TCP**: `available()` ненадёжен → обязательно `readUntilPrompt()`,
     * иначе "OK>" накапливаются в TCP-буфере и сбивают парсинг следующих запросов.
     *
     * **BT RFCOMM**: `available()` + `skip()` в `drainInput()` работал корректно
     * до смены стратегии — оставляем прежнее поведение без изменений.
     */
    private suspend fun consumeAtResponse(timeoutMs: Long = 1000L) {
        if (isWifi) readUntilPrompt(timeoutMs) else drainInput()
    }

    /**
     * Проверяет, не истекла ли K-Line / KWP2000 сессия (P3_Max = 5 с), и если да —
     * отправляет `0100` для её восстановления.
     *
     * **Вызывать внутри блока `ioMutex`** — использует сырой I/O без дополнительной блокировки.
     *
     * Поведение по таймаутам:
     * - CAN (большинство машин 2008+): ответ `0100` за ~200 мс.
     * - K-Line активная (пауза ≤ P3_Max): ~300 мс.
     * - K-Line истёкшая (пауза > 5 с): 5-baud re-init 5–7 с, таймаут 9 с — допустимо.
     *
     * Для BT: в начале цикла мониторинга, если пауза >3.5 с (например, пользователь
     *   перешёл на другой экран), warmup занимает ~300 мс и прозрачно восстанавливает сессию.
     * Для ClearDTC: Mode 04 перезагружает ЭБУ — warmup вызывается явно через [postClearWarmup].
     */
    private suspend fun warmupIfNeeded() {
        val idleMs = System.currentTimeMillis() - lastEcuCommandMs
        if (idleMs > 3500L) {
            info(TAG, "⚡ warmup: idle ${idleMs}ms > 3.5s → 0100")
            drainInput()
            sendRaw("0100")
            val resp = readUntilPrompt(9000).cleanObd()
            drainInput()
            // Если ответ NODATA/пустой — K-Line сессия мертва: ELM327 послал в истёкшую сессию.
            // ATPC закрывает её, следующий 0100 делает 5-baud re-init «с нуля».
            if (resp.isEmpty() || resp.contains("NODATA") || resp.contains("UNABLE") || resp.contains("ERROR")) {
                warn(TAG, "warmup got '$resp' → ATPC + re-init 0100")
                sendRaw("ATPC"); delay(500); consumeAtResponse()
                sendRaw("0100")
                val resp2 = readUntilPrompt(9000).cleanObd()
                info(TAG, "warmup retry: '$resp2'")
                drainInput()
            } else {
                info(TAG, "warmup OK: '$resp'")
            }
        }
    }

    /**
     * Восстанавливает сессию после Mode 04 (Clear DTC).
     *
     * Mode 04 вызывает внутренний сброс ЭБУ, после которого K-Line сессия мертва.
     * Алгоритм:
     *   1. delay(2500) — ЭБУ завершает перезагрузку (на некоторых авто 2+ с, было 1.5 с).
     *   2. ATPC       — закрываем мёртвую сессию в ELM327; без этого ELM327 шлёт
     *                   команды в старую сессию → NO DATA.
     *   3. 0100       — принудительная переинициализация: CAN ~200 мс, K-Line 5–7 с.
     */
    private suspend fun postClearWarmup() {
        info(TAG, "⚡ postClearWarmup: waiting for ECU reboot after Mode 04…")
        delay(2500)
        drainInput()            // очищаем стек байт, накопившийся за время перезагрузки
        sendRaw("ATPC"); delay(500); consumeAtResponse()
        sendRaw("0100")
        val resp = readUntilPrompt(9000).cleanObd()
        info(TAG, "postClearWarmup done: '$resp'")
        drainInput()
    }

    /**
     * Сбрасывает накопленные в буфере входного потока байты.
     * Вызывается перед отправкой следующей команды, чтобы остатки предыдущего ответа
     * не смешивались с новым.
     *
     * **Bluetooth**: `available()` корректно показывает число буферизованных байт,
     * поэтому используем skip().
     *
     * **Wi-Fi (TCP)**: `available()` почти всегда 0 (данные не буферизуются Java
     * до явного `read()`), поэтому устанавливаем короткий `soTimeout` и читаем
     * до тайм-аута — всё, что пришло менее чем за 80 мс, считается хвостом предыдущей команды.
     */
    private suspend fun drainInput() {
        val stream = input ?: return
        delay(100)  // 100 мс: ждём прихода хвостовых байт от предыдущего ответа
        try {
            if (isWifi) {
                // WiFi: soTimeout=150ms (было 80ms). ELM327 может прислать финальный '>'
                // с задержкой до ~200ms после нашего readUntilPrompt-таймаута — теперь ловим.
                wifiSocket?.soTimeout = 150
                try { while (true) stream.read() } catch (_: java.net.SocketTimeoutException) {}
            } else {
                if (stream.available() > 0) stream.skip(stream.available().toLong())
            }
        } catch (_: Exception) {}
    }

    // ─────────────────────────── DISCONNECT ─────────────────────────────────

    /** Закрывает RFCOMM-сокет и сбрасывает все ссылки на потоки. */
    fun disconnect() {
        info(TAG, "═══ disconnect ═══")
        runCatching { input?.close() }
        runCatching { output?.close() }
        runCatching { socket?.close() }
        runCatching { wifiSocket?.close() }
        input = null; output = null; socket = null; wifiSocket = null
        connectedDeviceLabel = null
        lastEcuCommandMs = 0L
        isCanProtocol = true
    }
}

// ─────────────────────────── OBD2 LIVE DATA MODELS ──────────────────────────

/**
 * Описание одного OBD2 Mode 01 PID.
 *
 * @param command    AT-команда (напр. "010C"). Первые два символа = режим (01 = Mode 01).
 * @param shortCode  2-4 буквы для бейджа на карточке (напр. "RPM").
 * @param name       Полное название на русском языке.
 * @param unit       Единица измерения (напр. "°C", "об/мин", "%").
 * @param minWarning Нижний предупредительный порог; null = не проверяется.
 * @param maxWarning Верхний предупредительный порог; null = не проверяется.
 * @param decode     Функция декодирования байт ответа в float-значение.
 *                   Байты: b[0]=0x41 (mode), b[1]=PID, b[2..]=данные.
 */
data class ObdPid(
    val command: String,
    val shortCode: String,
    val name: String,
    val unit: String,
    val minWarning: Float? = null,
    val maxWarning: Float? = null,
    val decode: (List<Int>) -> Float,
)

/** Результат одного опроса датчика. */
data class SensorReading(
    val pid: ObdPid,
    val value: Float?,       // null = нет данных / не поддерживается
    val status: SensorStatus,
)

/** Статус показания датчика для цветовой индикации. */
enum class SensorStatus { OK, WARNING, UNSUPPORTED, ERROR, DISCONNECTED }

/**
 * Стандартные OBD2 PIDs Mode 01, которые работают на всех машинах с 1996 года
 * (Honda, BMW, Toyota, VAG, Ford и т.д.) при условии исправного ЭБУ.
 *
 * Не все ЭБУ поддерживают все PIDs — если машина не отвечает на конкретный PID,
 * `pollSensor` вернёт статус UNSUPPORTED, и карточка не отображается.
 *
 * Формат команды: "01" + hex(PID). Ответ: "41" + hex(PID) + байты данных.
 */
val UNIVERSAL_PIDS = listOf(

    // ── Основные параметры двигателя ─────────────────────────────────────────

    // RPM: (A * 256 + B) / 4 → об/мин
    ObdPid("010C", "RPM",  "Обороты двигателя",          "об/мин", 500f, 7000f)
        { b -> if (b.size >= 4) ((b[2] * 256) + b[3]) / 4.0f else 0f },

    // Speed: A → км/ч (прямое значение)
    ObdPid("010D", "SPD",  "Скорость",                   "км/ч",   null, 280f)
        { b -> if (b.size >= 3) b[2].toFloat() else 0f },

    // Calculated Load: A * 100 / 255 → %
    ObdPid("0104", "ENG",  "Нагрузка двигателя",         "%",      null, 100f)
        { b -> if (b.size >= 3) b[2] * 100.0f / 255.0f else 0f },

    // Throttle Position: A * 100 / 255 → %
    ObdPid("0111", "TPS",  "Положение дросселя",         "%",      null, 100f)
        { b -> if (b.size >= 3) b[2] * 100.0f / 255.0f else 0f },

    // Engine Run Time: (A * 256 + B) → секунды
    ObdPid("011F", "RUN",  "Время работы двигателя",     "сек",    null, null)
        { b -> if (b.size >= 4) ((b[2] * 256) + b[3]).toFloat() else 0f },

    // ── Температуры ──────────────────────────────────────────────────────────

    // Coolant Temp: A - 40 → °C (диапазон -40..+215)
    ObdPid("0105", "ECT",  "Охлаждающая жидкость",       "°C",     70f,  115f)
        { b -> if (b.size >= 3) (b[2] - 40).toFloat() else 0f },

    // Intake Air Temp: A - 40 → °C
    ObdPid("010F", "IAT",  "Температура воздуха впуска", "°C",     null, 60f)
        { b -> if (b.size >= 3) (b[2] - 40).toFloat() else 0f },

    // Ambient Air Temp: A - 40 → °C
    ObdPid("0146", "AMB",  "Температура окружающей среды","°C",    null, null)
        { b -> if (b.size >= 3) (b[2] - 40).toFloat() else 0f },

    // Engine Oil Temp: A - 40 → °C
    ObdPid("015C", "OIL",  "Температура масла",          "°C",     null, 130f)
        { b -> if (b.size >= 3) (b[2] - 40).toFloat() else 0f },

    // ── Давление / поток воздуха ──────────────────────────────────────────────

    // Intake Manifold Absolute Pressure: A → кПа
    ObdPid("010B", "MAP",  "Давление впуска (MAP)",       "кПа",   20f,  105f)
        { b -> if (b.size >= 3) b[2].toFloat() else 0f },

    // Mass Air Flow: (A * 256 + B) / 100 → г/с
    ObdPid("0110", "MAF",  "Массовый расход воздуха",    "г/с",    null, null)
        { b -> if (b.size >= 4) ((b[2] * 256) + b[3]) / 100.0f else 0f },

    // Barometric Pressure: A → кПа
    ObdPid("0133", "BAR",  "Атм. давление",              "кПа",    85f,  105f)
        { b -> if (b.size >= 3) b[2].toFloat() else 0f },

    // ── Топливная система ─────────────────────────────────────────────────────

    // Fuel Level: A * 100 / 255 → %
    ObdPid("012F", "FLV",  "Уровень топлива",             "%",     10f,  null)
        { b -> if (b.size >= 3) b[2] * 100.0f / 255.0f else 0f },

    // Fuel Rail Pressure (gauge): A * 3 → кПа
    ObdPid("010A", "FRP",  "Давление топлива",            "кПа",   null, null)
        { b -> if (b.size >= 3) b[2] * 3.0f else 0f },

    // Short Term Fuel Trim Bank 1: (A - 128) * 100 / 128 → %
    ObdPid("0106", "STF1", "Краткоср. коррекция B1",     "%",      -10f, 10f)
        { b -> if (b.size >= 3) (b[2] - 128) * 100.0f / 128.0f else 0f },

    // Long Term Fuel Trim Bank 1: (A - 128) * 100 / 128 → %
    ObdPid("0107", "LTF1", "Долгоср. коррекция B1",      "%",      -10f, 10f)
        { b -> if (b.size >= 3) (b[2] - 128) * 100.0f / 128.0f else 0f },

    // Short Term Fuel Trim Bank 2 (V-образные, bi-turbo)
    ObdPid("0108", "STF2", "Краткоср. коррекция B2",     "%",      -10f, 10f)
        { b -> if (b.size >= 3) (b[2] - 128) * 100.0f / 128.0f else 0f },

    // Long Term Fuel Trim Bank 2
    ObdPid("0109", "LTF2", "Долгоср. коррекция B2",      "%",      -10f, 10f)
        { b -> if (b.size >= 3) (b[2] - 128) * 100.0f / 128.0f else 0f },

    // ── Электрика ─────────────────────────────────────────────────────────────

    // Control Module Voltage: (A * 256 + B) / 1000 → В
    ObdPid("0142", "VLT",  "Напряжение бортсети",         "В",     11.5f, 14.8f)
        { b -> if (b.size >= 4) ((b[2] * 256) + b[3]) / 1000.0f else 0f },

    // ── Зажигание / выхлоп ───────────────────────────────────────────────────

    // Timing Advance: A / 2 - 64 → ° (относительно ВМТ)
    ObdPid("010E", "IGN",  "Угол опережения зажигания",  "°",      -20f, 60f)
        { b -> if (b.size >= 3) (b[2] / 2.0f) - 64f else 0f },

    // Catalyst Temp Bank 1 Sensor 1: (A * 256 + B) / 10 - 40 → °C
    ObdPid("013C", "CT1",  "Температура катализатора B1S1","°C",   null, 900f)
        { b -> if (b.size >= 4) ((b[2] * 256) + b[3]) / 10.0f - 40f else 0f },

    // Catalyst Temp Bank 2 Sensor 1
    ObdPid("013E", "CT2",  "Температура катализатора B2S1","°C",   null, 900f)
        { b -> if (b.size >= 4) ((b[2] * 256) + b[3]) / 10.0f - 40f else 0f },

    // ── O₂ датчики ───────────────────────────────────────────────────────────

    // O2 Sensor Bank 1 Sensor 1 voltage: A / 200 → В (типично 0.1–0.9 В)
    ObdPid("0114", "O2S1", "Датчик O₂ B1S1",              "В",     0.1f, 0.9f)
        { b -> if (b.size >= 3) b[2] / 200.0f else 0f },

    // O2 Sensor Bank 1 Sensor 2 (после катализатора)
    ObdPid("0115", "O2S2", "Датчик O₂ B1S2",              "В",     0.1f, 0.9f)
        { b -> if (b.size >= 3) b[2] / 200.0f else 0f },

    // ── EGR / дополнительные ─────────────────────────────────────────────────

    // Commanded EGR: A * 100 / 255 → %
    ObdPid("012C", "EGR",  "Клапан EGR (команда)",        "%",     null, 100f)
        { b -> if (b.size >= 3) b[2] * 100.0f / 255.0f else 0f },

    // Absolute Load Value: (A * 256 + B) * 100 / 65535 → %
    ObdPid("0143", "ALD",  "Абсолютная нагрузка",         "%",     null, 100f)
        { b -> if (b.size >= 4) ((b[2] * 256) + b[3]) * 100.0f / 65535.0f else 0f },

    // Commanded Equivalence Ratio (lambda): (A * 256 + B) * 2 / 65536
    ObdPid("0144", "AFR",  "Команд. соотношение A/F (λ)",  "",     null, null)
        { b -> if (b.size >= 4) ((b[2] * 256) + b[3]) * 2.0f / 65536.0f else 0f },

    // Time Run with MIL on: (A * 256 + B) → минуты
    ObdPid("014D", "MLT",  "Время с Check Engine",         "мин",  null, null)
        { b -> if (b.size >= 4) ((b[2] * 256) + b[3]).toFloat() else 0f },

    // Engine Fuel Rate: (A * 256 + B) / 20 → л/ч
    ObdPid("015E", "FRT",  "Расход топлива",               "л/ч",  null, null)
        { b -> if (b.size >= 4) ((b[2] * 256) + b[3]) / 20.0f else 0f },
)

// ─────────────────────────── DTC RESULT ─────────────────────────────────────

/**
 * Результат запроса диагностических кодов.
 * Используется для Mode 03 (постоянные) и Mode 07 (ожидающие).
 */
sealed class DtcResult {
    /** ЭБУ ответил: ошибок нет (или список пуст). */
    data object NoDtcs : DtcResult()
    /** Список найденных кодов. */
    data class DtcList(val codes: List<String>) : DtcResult()
    /** Нераспознанный ответ (например, нестандартный формат ЭБУ). */
    data class RawResponse(val raw: String) : DtcResult()
    /** Ошибка связи или таймаут. */
    data class Error(val message: String) : DtcResult()
}

// ─────────────────────────── VEHICLE INFO ────────────────────────────────────

/**
 * Статическая информация об автомобиле, прочитанная через OBD2 Mode 09
 * сразу после успешного подключения.
 */
data class VehicleInfo(
    /** 17-символьный идентификационный номер, ISO 3779. */
    val vin: String? = null,
    /** Марка, декодированная из WMI (первые 3 символа VIN). */
    val detectedMake: String? = null,
    /** Модельный год, декодированный из 10-го символа VIN. */
    val detectedYear: String? = null,
    /** Название ЭБУ двигателя (Mode 09, PID 0A). */
    val ecuName: String? = null,
    /** Calibration ID (Mode 09, PID 03), часто строка ПО ЭБУ. */
    val calibrationId: String? = null,
    /** CVN — контрольные суммы калибровок (Mode 09, PID 04), группы по 8 hex. */
    val cvnHex: String? = null,
    /** 4 байта маски «поддерживаемые PID Mode 09 (01–20)» в hex (ответ PID 00). */
    val mode09SupportMaskHex: String? = null,
    /** Сырые hex-фрагменты опциональных PID Mode 09 (01, 05–09), усечено. */
    val mode09ExtrasSummary: String? = null,
    /** PID 0x1C — тип требований OBD (CARB, EOBD, …). */
    val obdStandardLabel: String? = null,
    /** PID 0x51 — тип топлива двигателя. */
    val fuelTypeLabel: String? = null,
    /** Имя ЭБУ АКПП (Mode 09/0A на CAN-адресе 7E1), если удалось прочитать. */
    val transmissionEcuName: String? = null,
    /**
     * Пробег с щитка приборов (UDS 0x22, марочные пробы) — **экспериментально** на CAN.
     * Может отличаться от реального или быть null.
     */
    val clusterOdometerKm: Int? = null,
    /** Откуда взято значение [clusterOdometerKm] (для отладки / PDF). */
    val clusterOdometerNote: String? = null,
    /** Символы 4–9 VIN (ISO 3779 VDS) — задел для платформенных веток. */
    val vinVehicleDescriptor: String? = null,
    /** Имя [BrandEcuHints.VehicleBrandGroup] для выбранной марочной ветки. */
    val diagnosticBrandGroup: String? = null,
    /** Пробег с горящим Check Engine (PID 0x21), моторный ЭБУ; не полный одометр. */
    val distanceMil: Int? = null,
    /**
     * PID 0x31 (SAE): пройдено с **последнего сброса DTC в сканере** (Mode 04 / clear codes).
     * Это **не** показание одометра на приборке; максимум 65535 км по стандарту (2 байта).
     */
    val distanceCleared: Int? = null,
    /** PID 0x03 — статус топливной системы (Open/Closed Loop). */
    val fuelSystemStatus: String? = null,
    /** PID 0x30 — количество прогревов двигателя с последнего сброса DTC. */
    val warmUpsCleared: Int? = null,
    /** PID 0x4E — минуты с последнего сброса DTC. */
    val timeSinceClearedMin: Int? = null,
    /**
     * true = WMI 1-5 (Северная Америка). Некоторые такие авто передают
     * PIDs 0x21/0x31 в милях, нарушая стандарт. Конвертация автоматическая.
     */
    val usesImperialUnits: Boolean = false,
) {
    /** Дистанция с MIL в км (конвертирована из миль, если нужно). */
    fun distanceMilKm(): Int?     = distanceMil?.let     { if (usesImperialUnits) (it * 1.60934).toInt() else it }
    /** Дистанция после сброса в км (конвертирована из миль, если нужно). */
    fun distanceClearedKm(): Int? = distanceCleared?.let { if (usesImperialUnits) (it * 1.60934).toInt() else it }
}

// ─────────────────────────── FREEZE FRAME DATA ───────────────────────────────

/**
 * Снимок параметров двигателя в момент появления приоритетной ошибки (Mode 02).
 * Поля null = ЭБУ не поддерживает соответствующий PID или не вернул данные.
 */
data class FreezeFrameData(
    val dtcCode:       String? = null, // DTC, вызвавший снимок (PID 02)
    val rpm:           Int?   = null,  // об/мин
    val speed:         Int?   = null,  // км/ч
    val coolantTemp:   Int?   = null,  // °C
    val engineLoad:    Float? = null,  // %
    val throttle:      Float? = null,  // %
    val shortFuelTrim: Float? = null,  // %
    val longFuelTrim:  Float? = null,  // %
    val map:           Int?   = null,  // кПа
    val iat:           Int?   = null,  // °C
    val voltage:       Float? = null,  // В
    val fuelStatus:    String? = null, // Open/Closed Loop
) {
    val isEmpty: Boolean get() = dtcCode == null && rpm == null && speed == null && coolantTemp == null &&
            engineLoad == null && throttle == null && shortFuelTrim == null && longFuelTrim == null &&
            map == null && iat == null && voltage == null && fuelStatus == null
}

// ─────────────────────────── READINESS MONITOR ───────────────────────────────

/**
 * Одна запись о готовности системы мониторинга ОБД2.
 *
 * @param name  Название монитора на русском языке.
 * @param ready true = монитор завершил тест (готов к проверке выбросов).
 *              false = тест ещё не пройден (нужно проехать driving cycle).
 */
data class ReadinessMonitor(val name: String, val ready: Boolean)

// ─────────────────────────── OTHER ECU DTC RESULT ────────────────────────────

/**
 * Результат попытки считать DTC с нестандартного блока через CAN-адресацию.
 *
 * @param name     Человекочитаемое название блока (напр. "ABS / Тормоза").
 * @param address  CAN-заголовок запроса (напр. "7B0").
 * @param result   Результат опроса (коды / ошибка / нет данных).
 */
data class EcuDtcResult(
    val name: String,
    val address: String,
    val result: DtcResult,
    val pendingResult: DtcResult = DtcResult.NoDtcs,
    val permanentResult: DtcResult = DtcResult.NoDtcs,
)
