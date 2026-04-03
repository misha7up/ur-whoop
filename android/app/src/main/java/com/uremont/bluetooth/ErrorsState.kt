package com.uremont.bluetooth

/** Состояние экрана диагностики DTC (аналог `ErrorsState` в iOS `AppViewModel`). */
sealed class ErrorsState {
    /** Исходное состояние — ни одного запроса ещё не делалось. */
    data object Idle : ErrorsState()

    /** Идёт опрос ЭБУ — блокируем кнопки, показываем спиннер. */
    data object Loading : ErrorsState()

    /**
     * Все запросы завершены.
     * @param result           Постоянные коды (Mode 03).
     * @param pendingResult    Ожидающие коды (Mode 07).
     * @param permanentResult  Постоянные эмиссионные PDTC (Mode 0A); часто пусто на EU.
     * @param freezeFrame      Снимок параметров (Mode 02); null — если выключено в настройках.
     * @param otherEcus        Результаты опроса ABS/SRS/TCM/BCM; пусто — если выключено.
     */
    data class Result(
        val result: DtcResult,
        val pendingResult: DtcResult = DtcResult.NoDtcs,
        val permanentResult: DtcResult = DtcResult.NoDtcs,
        val freezeFrame: FreezeFrameData? = null,
        val otherEcus: List<EcuDtcResult> = emptyList(),
    ) : ErrorsState()
}
