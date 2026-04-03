package com.uremont.bluetooth

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// ─────────────────────────── REPORT DATA STRUCTURES ──────────────────────────

/**
 * Предварительно подготовленные данные для PDF-отчёта.
 * Строится в MainActivity (где доступна функция dtcInfo) и передаётся в генератор.
 */
data class DiagnosticReportData(
    val generatedAt: Long,
    val vehicleDisplayName: String,
    val vin: String?,
    val detectedMake: String?,
    val detectedYear: String?,
    val ecuName: String?,
    val calibrationId: String?,
    val cvnHex: String?,
    val mode09SupportMaskHex: String?,
    val mode09ExtrasSummary: String?,
    val obdStandardLabel: String?,
    val fuelTypeLabel: String?,
    val transmissionEcuName: String?,
    val clusterOdometerKm: String?,
    val clusterOdometerNote: String?,
    val vinVehicleDescriptor: String?,
    val diagnosticBrandGroup: String?,
    /** Пробег с горящим MIL в км (уже сконвертирован, строка). */
    val distanceMilKm: String?,
    /** Пробег после сброса в км (уже сконвертирован, строка). */
    val distanceClearedKm: String?,
    val fuelSystemStatus: String? = null,
    val warmUpsCleared: Int? = null,
    val timeSinceClearedMin: Int? = null,
    val readinessMonitors: List<ReadinessMonitor>,
    val mainDtcs: List<DtcEntry>,
    val pendingDtcs: List<DtcEntry>,
    val permanentDtcs: List<DtcEntry> = emptyList(),
    val freezeFrame: FreezeFrameData?,
    /** Только блоки с ошибками. */
    val allBlocks: List<EcuStatusEntry>,
)

/** Запись о DTC для PDF (предварительно разобранная). */
data class DtcEntry(
    val code: String,
    val title: String,
    val causes: String,
    val repair: String,
    val severity: Int,
)

/**
 * Статус одного блока ЭБУ для раздела PDF «БЛОКИ УПРАВЛЕНИЯ».
 * Включает все опрошенные блоки — в том числе не ответившие.
 */
data class EcuStatusEntry(
    val name: String,
    val address: String,
    /** false — блок не ответил (NODATA / таймаут / ошибка связи). */
    val responded: Boolean,
    /** Confirmed DTC этого блока (Mode 03). */
    val dtcs: List<DtcEntry>,
    /** Pending DTC этого блока (Mode 07). */
    val pendingDtcs: List<DtcEntry> = emptyList(),
    /** Permanent DTC этого блока (Mode 0A). */
    val permanentDtcs: List<DtcEntry> = emptyList(),
)

// ─────────────────────────── PDF REPORT GENERATOR ────────────────────────────

/**
 * Генерирует PDF-отчёт о диагностике автомобиля.
 *
 * Использует стандартный Android API:
 *   - [android.graphics.pdf.PdfDocument] — постраничный PDF-документ
 *   - [android.graphics.Canvas] + [android.graphics.Paint] — ручная отрисовка
 *   - [androidx.core.content.FileProvider] — безопасный share через Intent
 *
 * Формат страницы: A4 (595×842pt, ~72dpi).
 * Цвета воспроизводят фирменный стиль UREMONT.
 */
object PdfReportGenerator {

    // ── Размеры страницы и отступы ─────────────────────────────────────────────
    private const val PW = 595f   // ширина A4
    private const val PH = 842f   // высота A4
    private const val ML = 36f    // left margin
    private const val MR = 36f    // right margin
    private val CW = PW - ML - MR  // ширина контента = 523

    // ── Цвета PDF (android.graphics.Color.rgb) ─────────────────────────────────
    private val C_HEADER_BG = Color.rgb(13,  13,  20)   // тёмный фон шапки
    private val C_ACCENT    = Color.rgb(34,  125, 245)  // синий акцент
    private val C_TEXT      = Color.rgb(20,  20,  26)   // основной текст
    private val C_SUBTEXT   = Color.rgb(110, 110, 120)  // подтекст
    private val C_DIVIDER   = Color.rgb(218, 218, 226)  // разделительная линия
    private val C_CARD      = Color.rgb(245, 245, 252)  // фон карточки
    private val C_GREEN     = Color.rgb(52,  199, 89)
    private val C_ORANGE    = Color.rgb(255, 149, 0)
    private val C_RED       = Color.rgb(255, 59,  48)
    private val C_YELLOW    = Color.rgb(252, 201, 0)
    private val C_PENDING   = Color.rgb(255, 246, 228)

    // ─────────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Генерирует PDF в `filesDir/reports/` и возвращает файл.
     * Вызывается из корутины (может занимать 100–300 мс на слабых устройствах).
     */
    fun generate(context: Context, data: DiagnosticReportData): File {
        val doc   = PdfDocument()
        val state = PageState(doc)
        state.newPage()

        drawHeader(state, data, context)
        drawVehicleInfoSection(state, data)
        if (data.readinessMonitors.isNotEmpty()) drawReadinessSection(state, data)
        drawDtcSection(state, data)
        if (data.freezeFrame != null && !data.freezeFrame.isEmpty) drawFreezeSection(state, data.freezeFrame)
        if (data.allBlocks.isNotEmpty()) drawBlocksSummarySection(state, data.allBlocks)

        state.finish()  // завершает страницу и рисует footer

        val dir  = File(context.filesDir, "reports").also { it.mkdirs() }
        val file = File(dir, "uremont_report_${data.generatedAt}.pdf")
        // try-finally гарантирует вызов doc.close() и освобождение нативных ресурсов
        // даже при исключении во время записи файла
        try {
            file.outputStream().use { doc.writeTo(it) }
        } finally {
            doc.close()
        }
        return file
    }

    private fun pdfUri(context: Context, file: File) = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        file,
    )

    /**
     * Открывает PDF во внешнем приложении (просмотрщик).
     * @return true, если найдено приложение для просмотра
     */
    fun open(context: Context, file: File): Boolean {
        val uri = pdfUri(context, file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/pdf")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return try {
            context.startActivity(Intent.createChooser(intent, "Открыть отчёт"))
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    /** Открывает системный диалог «Поделиться» для готового PDF-файла. */
    fun share(context: Context, file: File) {
        val uri = pdfUri(context, file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, "UREMONT WHOOP — Отчёт диагностики")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "Поделиться отчётом"))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Section renderers
    // ─────────────────────────────────────────────────────────────────────────

    private fun drawHeader(state: PageState, data: DiagnosticReportData, context: Context) {
        val c = state.canvas!!
        val p = paint()

        // Тёмный фон шапки
        p.color = C_HEADER_BG
        c.drawRect(0f, 0f, PW, 106f, p)

        // Синяя полоса-разделитель под шапкой
        p.color = C_ACCENT
        c.drawRect(0f, 104f, PW, 109f, p)

        // Логотип UREMONT SVG (VectorDrawable → draw на Canvas PDF)
        val logoDr = ContextCompat.getDrawable(context, R.drawable.ic_logo)
        if (logoDr != null) {
            // Оригинал 30×32 → размещаем в область 47×50 (сохраняет пропорцию ~0.94)
            logoDr.setBounds(ML.toInt(), 20, (ML + 47).toInt(), 70)
            logoDr.draw(c)
        } else {
            // Запасной вариант: синий прямоугольник с буквой U
            p.color = C_ACCENT
            c.drawRoundRect(RectF(ML, 20f, ML + 50f, 70f), 12f, 12f, p)
            p.color = Color.WHITE; p.textSize = 30f; p.typeface = Typeface.DEFAULT_BOLD
            c.drawText("U", ML + 13f, 58f, p)
        }

        // Заголовок
        p.color = Color.WHITE; p.textSize = 20f; p.typeface = Typeface.DEFAULT_BOLD
        c.drawText("UREMONT WHOOP", ML + 62f, 46f, p)
        p.color = Color.rgb(160, 172, 195); p.textSize = 10f; p.typeface = Typeface.DEFAULT
        c.drawText("OBD2 Диагностика автомобиля", ML + 62f, 64f, p)

        // Авто + дата (правый край)
        val dateStr = SimpleDateFormat("d MMM yyyy, HH:mm", Locale("ru")).format(Date(data.generatedAt))
        p.textAlign = Paint.Align.RIGHT
        p.color = Color.rgb(200, 212, 235); p.textSize = 10f; p.typeface = Typeface.DEFAULT_BOLD
        c.drawText(data.vehicleDisplayName, PW - MR, 44f, p)
        p.color = Color.rgb(140, 152, 175); p.textSize = 9f; p.typeface = Typeface.DEFAULT
        c.drawText(dateStr, PW - MR, 60f, p)
        p.textAlign = Paint.Align.LEFT

        state.y = 124f
    }

    private fun drawVehicleInfoSection(state: PageState, data: DiagnosticReportData) {
        val rows = buildList {
            data.detectedMake?.let { add("Марка автомобиля" to it) }
            data.detectedYear?.let { add("Год выпуска" to it) }
            data.vin?.let { add("VIN" to it) }
            data.vinVehicleDescriptor?.let { add("VDS (VIN 4–9)" to it) }
            data.diagnosticBrandGroup?.let { g ->
                if (g != "OTHER") add("Диагност. группа марки" to g)
            }
            data.ecuName?.let { add("ЭБУ двигателя" to it) }
            data.transmissionEcuName?.let { add("ЭБУ КПП (CAN 7E1)" to it) }
            data.clusterOdometerKm?.let { km ->
                val note = data.clusterOdometerNote?.let { " ($it)" } ?: ""
                add("Одометр щитка (UDS, опытно)$note" to "$km км")
            }
            data.obdStandardLabel?.let { add("Тип OBD (PID 1C)" to it) }
            data.fuelTypeLabel?.let { add("Топливо (PID 51)" to it) }
            data.calibrationId?.let { add("Calibration ID (09/03)" to it) }
            data.cvnHex?.let { add("CVN (09/04)" to it) }
            data.mode09SupportMaskHex?.let { add("Маска Mode 09 (00)" to it) }
            data.mode09ExtrasSummary?.let { add("Mode 09 (доп.)" to it) }
            data.distanceMilKm?.let { add("Пробег с Check Engine (PID 0x21)" to "$it км") }
            data.distanceClearedKm?.let { add("С последнего сброса DTC (0x31, не одометр)" to "$it км") }
            data.fuelSystemStatus?.let { add("Система топливоподачи (PID 03)" to it) }
            data.warmUpsCleared?.let { add("Прогревов после сброса DTC (PID 30)" to "$it") }
            data.timeSinceClearedMin?.let { add("Минут с момента сброса DTC (PID 4E)" to "$it мин") }
        }
        sectionHeader(state, "ИНФОРМАЦИЯ ОБ АВТОМОБИЛЕ")
        if (rows.isEmpty()) {
            smallText(state, "   Данные об автомобиле не получены от ЭБУ", C_SUBTEXT)
        } else {
            rows.forEach { (k, v) -> kvRow(state, k, v) }
        }
        state.y += 8f
    }

    private fun drawReadinessSection(state: PageState, data: DiagnosticReportData) {
        sectionHeader(state, "ГОТОВНОСТЬ СИСТЕМ МОНИТОРИНГА")
        val monitors = data.readinessMonitors
        var i = 0
        while (i < monitors.size) {
            state.ensureSpace(24f)
            val left  = monitors[i]
            val right = monitors.getOrNull(i + 1)
            val halfW = CW / 2 - 5f
            drawReadinessCell(state.canvas!!, state.y, left, ML, halfW)
            right?.let { drawReadinessCell(state.canvas!!, state.y, it, ML + halfW + 10f, halfW) }
            state.y += 24f
            i += 2
        }
        state.y += 8f
    }

    private fun drawDtcSection(state: PageState, data: DiagnosticReportData) {
        sectionHeader(state, "ПОСТОЯННЫЕ КОДЫ НЕИСПРАВНОСТЕЙ (${data.mainDtcs.size})")
        if (data.mainDtcs.isEmpty()) {
            smallText(state, "   ✓   Постоянных ошибок не обнаружено", C_GREEN)
        } else {
            data.mainDtcs.forEach { dtcCard(state, it, isPending = false) }
        }
        state.y += 4f

        if (data.pendingDtcs.isNotEmpty()) {
            sectionHeader(state, "ОЖИДАЮЩИЕ КОДЫ (${data.pendingDtcs.size})")
            data.pendingDtcs.forEach { dtcCard(state, it, isPending = true) }
            state.y += 4f
        }
        if (data.permanentDtcs.isNotEmpty()) {
            sectionHeader(state, "ПОСТОЯННЫЕ ЭМИССИОННЫЕ (MODE 0A) (${data.permanentDtcs.size})")
            data.permanentDtcs.forEach { dtcCard(state, it, isPending = false) }
            state.y += 4f
        }
    }

    private fun drawFreezeSection(state: PageState, ff: FreezeFrameData) {
        sectionHeader(state, "СНИМОК ПАРАМЕТРОВ В МОМЕНТ ОШИБКИ (FREEZE FRAME)")
        val cells = buildList {
            ff.dtcCode?.let      { add("DTC, вызвавший снимок" to it) }
            ff.rpm?.let          { add("Обороты"              to "$it об/мин") }
            ff.speed?.let        { add("Скорость"              to "$it км/ч") }
            ff.coolantTemp?.let  { add("Охлаждающая жидкость" to "$it °C") }
            ff.iat?.let          { add("Температура воздуха"  to "$it °C") }
            ff.engineLoad?.let   { add("Нагрузка двигателя"   to "${"%.1f".format(it)} %") }
            ff.throttle?.let     { add("Положение дросселя"   to "${"%.1f".format(it)} %") }
            ff.shortFuelTrim?.let { add("Коррекция топлива (краткоср.)" to "${"%.1f".format(it)} %") }
            ff.longFuelTrim?.let { add("Коррекция топлива (долгоср.)"  to "${"%.1f".format(it)} %") }
            ff.map?.let          { add("Давление впуска"       to "$it кПа") }
            ff.voltage?.let      { add("Напряжение бортсети"   to "${"%.1f".format(it)} В") }
            ff.fuelStatus?.let   { add("Система топливоподачи" to it) }
        }
        val half = CW / 2 - 5f
        var i = 0
        while (i < cells.size) {
            state.ensureSpace(32f)
            val left  = cells[i]; val right = cells.getOrNull(i + 1)
            drawFreezeCell(state.canvas!!, state.y, left.first, left.second, ML, half)
            right?.let { drawFreezeCell(state.canvas!!, state.y, it.first, it.second, ML + half + 10f, half) }
            state.y += 32f
            i += 2
        }
        state.y += 4f
    }

    private fun drawBlocksSummarySection(state: PageState, blocks: List<EcuStatusEntry>) {
        sectionHeader(state, "БЛОКИ УПРАВЛЕНИЯ (${blocks.size})")
        blocks.forEach { block ->
            state.ensureSpace(24f)
            val c = state.canvas!!; val p = paint()

            val totalErrs = block.dtcs.size + block.pendingDtcs.size + block.permanentDtcs.size
            val (statusText, statusColor) = when {
                !block.responded     -> "НЕТ ОТВЕТА" to C_SUBTEXT
                totalErrs == 0       -> "ОШИБОК НЕТ" to C_GREEN
                else                 -> "$totalErrs ОШИБОК" to C_ORANGE
            }

            // Фон строки блока
            p.color = Color.rgb(238, 238, 248)
            c.drawRoundRect(RectF(ML, state.y, ML + CW, state.y + 20f), 5f, 5f, p)

            // Название блока
            p.color = C_TEXT; p.textSize = 9f; p.typeface = Typeface.DEFAULT_BOLD
            c.drawText(block.name.uppercase(), ML + 8f, state.y + 13f, p)

            // Адрес (серый, по правому краю перед статусом)
            p.color = C_SUBTEXT; p.textSize = 7.5f; p.typeface = Typeface.DEFAULT
            p.textAlign = Paint.Align.RIGHT
            c.drawText(block.address, ML + CW - 60f, state.y + 13f, p)

            // Статус (цветной, правый край)
            p.color = statusColor; p.textSize = 8f; p.typeface = Typeface.DEFAULT_BOLD
            c.drawText(statusText, ML + CW - 6f, state.y + 13f, p)
            p.textAlign = Paint.Align.LEFT

            state.y += 24f

            block.dtcs.forEach { dtcCard(state, it, isPending = false) }
            block.pendingDtcs.forEach { dtcCard(state, it, isPending = true) }
            block.permanentDtcs.forEach { dtcCard(state, it, isPending = false) }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Primitive drawing helpers
    // ─────────────────────────────────────────────────────────────────────────

    private fun sectionHeader(state: PageState, title: String) {
        state.ensureSpace(38f)
        val c = state.canvas!!; val p = paint()
        // Синяя вертикальная полоса
        p.color = C_ACCENT
        c.drawRect(ML, state.y, ML + 4f, state.y + 22f, p)
        // Заголовок
        p.color = C_TEXT; p.textSize = 11f; p.typeface = Typeface.DEFAULT_BOLD
        c.drawText(title, ML + 12f, state.y + 15f, p)
        // Разделительная линия
        p.color = C_DIVIDER; p.strokeWidth = 0.8f; p.style = Paint.Style.STROKE
        c.drawLine(ML, state.y + 24f, ML + CW, state.y + 24f, p)
        p.style = Paint.Style.FILL
        state.y += 32f
    }

    private fun kvRow(state: PageState, key: String, value: String) {
        state.ensureSpace(22f)
        val c = state.canvas!!; val p = paint()
        p.color = C_SUBTEXT; p.textSize = 9f
        c.drawText(key, ML + 8f, state.y + 14f, p)
        p.color = C_TEXT; p.textSize = 10f; p.typeface = Typeface.DEFAULT_BOLD
        p.textAlign = Paint.Align.RIGHT
        c.drawText(value, ML + CW - 6f, state.y + 14f, p)
        p.textAlign = Paint.Align.LEFT
        p.color = C_DIVIDER; p.strokeWidth = 0.5f; p.style = Paint.Style.STROKE
        c.drawLine(ML + 4f, state.y + 19f, ML + CW - 4f, state.y + 19f, p)
        p.style = Paint.Style.FILL
        state.y += 21f
    }

    private fun smallText(state: PageState, text: String, color: Int) {
        state.ensureSpace(18f)
        val p = paint(); p.color = color; p.textSize = 10f
        state.canvas!!.drawText(text, ML + 8f, state.y + 12f, p)
        state.y += 18f
    }

    private fun drawReadinessCell(
        c: Canvas, y: Float, m: ReadinessMonitor, x: Float, w: Float,
    ) {
        val p = paint()
        p.color = if (m.ready) Color.rgb(232, 252, 238) else Color.rgb(255, 244, 224)
        c.drawRoundRect(RectF(x, y, x + w, y + 20f), 5f, 5f, p)
        p.color = if (m.ready) C_GREEN else C_ORANGE
        c.drawCircle(x + 10f, y + 10f, 4f, p)
        p.color = C_TEXT; p.textSize = 8.5f; p.typeface = Typeface.DEFAULT
        c.drawText(m.name, x + 19f, y + 13.5f, p)
        p.color = if (m.ready) C_GREEN else C_ORANGE
        p.textSize = 7f; p.typeface = Typeface.DEFAULT_BOLD; p.textAlign = Paint.Align.RIGHT
        c.drawText(if (m.ready) "ГОТОВ" else "НЕ ГОТОВ", x + w - 5f, y + 13.5f, p)
        p.textAlign = Paint.Align.LEFT
    }

    private fun drawFreezeCell(c: Canvas, y: Float, label: String, value: String, x: Float, w: Float) {
        val p = paint()
        p.color = C_CARD
        c.drawRoundRect(RectF(x, y, x + w, y + 28f), 5f, 5f, p)
        p.color = C_SUBTEXT; p.textSize = 8f
        c.drawText(label, x + 8f, y + 11f, p)
        p.color = C_TEXT; p.textSize = 13f; p.typeface = Typeface.DEFAULT_BOLD
        c.drawText(value, x + 8f, y + 25f, p)
    }

    private fun dtcCard(state: PageState, entry: DtcEntry, isPending: Boolean) {
        val causeLines  = wrapText(entry.causes, 8.5f, CW - 95f)
        val repairLines = wrapText(entry.repair,  8.5f, CW - 95f)
        val cardH = 14f + 14f +
                (if (entry.causes.isNotEmpty())  causeLines.size * 12f + 14f else 0f) +
                (if (entry.repair.isNotEmpty())  repairLines.size * 12f + 14f else 0f) + 10f

        state.ensureSpace(cardH + 8f)
        val c = state.canvas!!; val p = paint()
        val top = state.y

        // Фон карточки
        p.color = C_CARD
        c.drawRoundRect(RectF(ML, top, ML + CW, top + cardH), 7f, 7f, p)

        // Цветная полоса слева (критичность)
        val barC = when (entry.severity) { 3 -> C_RED; 2 -> C_ORANGE; else -> C_YELLOW }
        p.color = barC
        c.drawRoundRect(RectF(ML, top, ML + 5f, top + cardH), 7f, 7f, p)
        c.drawRect(ML + 2f, top, ML + 5f, top + cardH, p)

        // Бейдж с кодом
        p.color = if (isPending) C_PENDING else Color.rgb(228, 240, 255)
        c.drawRoundRect(RectF(ML + 12f, top + 7f, ML + 62f, top + 21f), 4f, 4f, p)
        p.color = if (isPending) C_ORANGE else C_ACCENT
        p.textSize = 9f; p.typeface = Typeface.DEFAULT_BOLD; p.textAlign = Paint.Align.CENTER
        c.drawText(entry.code, ML + 37f, top + 18f, p)
        p.textAlign = Paint.Align.LEFT

        // Бейдж "ОЖИДАЮЩИЙ"
        var xTitle = ML + 68f
        if (isPending) {
            p.color = C_PENDING
            c.drawRoundRect(RectF(xTitle, top + 7f, xTitle + 64f, top + 21f), 4f, 4f, p)
            p.color = C_ORANGE; p.textSize = 7f; p.typeface = Typeface.DEFAULT_BOLD
            p.textAlign = Paint.Align.CENTER
            c.drawText("ОЖИДАЮЩИЙ", xTitle + 32f, top + 18f, p)
            p.textAlign = Paint.Align.LEFT
            xTitle += 70f
        }

        // Название ошибки
        p.color = C_TEXT; p.textSize = 10f; p.typeface = Typeface.DEFAULT_BOLD
        c.drawText(entry.title, xTitle, top + 18f, p)

        var rowY = top + 30f

        // Причины
        if (entry.causes.isNotEmpty()) {
            p.color = C_SUBTEXT; p.textSize = 8f; p.typeface = Typeface.DEFAULT_BOLD
            c.drawText("Причина:", ML + 12f, rowY + 9f, p); rowY += 13f
            p.color = C_TEXT; p.textSize = 8.5f; p.typeface = Typeface.DEFAULT
            causeLines.forEach { c.drawText(it, ML + 20f, rowY + 9f, p); rowY += 12f }
        }

        // Рекомендации
        if (entry.repair.isNotEmpty()) {
            p.color = Color.rgb(30, 110, 60); p.textSize = 8f; p.typeface = Typeface.DEFAULT_BOLD
            c.drawText("Ремонт:", ML + 12f, rowY + 9f, p); rowY += 13f
            p.color = Color.rgb(30, 100, 55); p.textSize = 8.5f; p.typeface = Typeface.DEFAULT
            repairLines.forEach { c.drawText(it, ML + 20f, rowY + 9f, p); rowY += 12f }
        }

        state.y = top + cardH + 8f
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Utilities
    // ─────────────────────────────────────────────────────────────────────────

    /** Создаёт Paint с ANTI_ALIAS, Fill, LEFT align, дефолтным шрифтом. */
    private fun paint() = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style    = Paint.Style.FILL
        textAlign = Paint.Align.LEFT
        typeface = Typeface.DEFAULT
    }

    /**
     * Разбивает текст на строки, каждая из которых умещается в [maxWidth] пикселей
     * при заданном [textSize].
     */
    private fun wrapText(text: String, textSize: Float, maxWidth: Float): List<String> {
        if (text.isBlank()) return emptyList()
        val p = Paint().apply { this.textSize = textSize }
        val words   = text.split(" ")
        val lines   = mutableListOf<String>()
        var current = StringBuilder()
        for (word in words) {
            val candidate = if (current.isEmpty()) word else "$current $word"
            if (p.measureText(candidate) <= maxWidth) {
                current = StringBuilder(candidate)
            } else {
                if (current.isNotEmpty()) lines.add(current.toString())
                current = StringBuilder(word)
            }
        }
        if (current.isNotEmpty()) lines.add(current.toString())
        return lines.ifEmpty { listOf(text) }
    }
}

// ─────────────────────────── PAGE STATE ──────────────────────────────────────

/**
 * Отслеживает текущую позицию Y и обрабатывает создание новых страниц.
 * При переходе на новую страницу автоматически рисует footer предыдущей.
 */
private class PageState(private val doc: PdfDocument) {

    var canvas:  Canvas? = null
    var y        = 0f
    var pageNum  = 0
    private var currentPage: PdfDocument.Page? = null

    fun newPage() {
        finishCurrentPage()
        pageNum++
        val pi = PdfDocument.PageInfo.Builder(595, 842, pageNum).create()
        currentPage = doc.startPage(pi)
        canvas = currentPage!!.canvas.also { it.drawColor(Color.WHITE) }
        // На первой странице y=0 (рисуем шапку от верха), на остальных — от отступа
        y = if (pageNum == 1) 0f else 40f
    }

    /** Гарантирует наличие [needed] пикселей до нижней границы; если нет — новая страница. */
    fun ensureSpace(needed: Float) {
        if (y + needed > 842f - 50f) newPage()
    }

    fun finish() { finishCurrentPage() }

    private fun finishCurrentPage() {
        currentPage?.let { page ->
            canvas?.let { drawPageFooter(it, pageNum) }
            doc.finishPage(page)
        }
        currentPage = null
        canvas = null
    }

    private fun drawPageFooter(c: Canvas, page: Int) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
        p.color = Color.rgb(218, 218, 226); p.strokeWidth = 0.7f
        c.drawLine(36f, 808f, 559f, 808f, p)
        p.style = Paint.Style.FILL
        p.color = Color.rgb(110, 110, 120); p.textSize = 8f
        c.drawText("UREMONT WHOOP — Отчёт OBD2 диагностики", 36f, 824f, p)
        p.textAlign = Paint.Align.RIGHT
        c.drawText("Стр. $page", 559f, 824f, p)
    }
}
