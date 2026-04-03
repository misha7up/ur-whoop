package com.uremont.bluetooth

import android.annotation.SuppressLint
import android.app.Application
import android.widget.Toast
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File

/**
 * Состояние и сценарии OBD-экрана (подключение, DTC, live, история) — аналог iOS [AppViewModel].
 */
data class ObdUiState(
    val connectionStatus: String,
    val isConnected: Boolean = false,
    val isConnecting: Boolean = false,
    val carProfile: CarProfile = CarProfile.Auto,
    val vehicleInfo: VehicleInfo? = null,
    val readinessMonitors: List<ReadinessMonitor> = emptyList(),
    val settings: AppSettings,
    val errorsState: ErrorsState = ErrorsState.Idle,
    val errorsLoadingMessage: String = "",
    val isMonitoring: Boolean = false,
    val sessions: List<SessionRecord> = emptyList(),
    val sessionLoadUserMessage: String? = null,
    val pdfPendingFile: File? = null,
) {
    companion object {
        fun initial(app: Application) = ObdUiState(
            connectionStatus = app.getString(R.string.status_no_connection),
            settings = AppSettings.load(app),
            errorsLoadingMessage = app.getString(R.string.errors_loading_default),
        )
    }
}

class ObdScreenViewModel(
    application: Application,
    private val obdManager: ObdConnectionManager,
) : AndroidViewModel(application) {

    private val app: Application get() = getApplication()

    private val _ui = MutableStateFlow(ObdUiState.initial(app))
    val uiState: StateFlow<ObdUiState> = _ui.asStateFlow()

    private val _sensorReadings = MutableStateFlow<Map<String, SensorReading>>(emptyMap())
    val sensorReadings: StateFlow<Map<String, SensorReading>> = _sensorReadings.asStateFlow()

    private fun toast(resId: Int) {
        Toast.makeText(app, resId, Toast.LENGTH_SHORT).show()
    }

    private fun toast(text: String) {
        Toast.makeText(app, text, Toast.LENGTH_SHORT).show()
    }

    fun consumeSessionLoadMessage() {
        _ui.update { it.copy(sessionLoadUserMessage = null) }
    }

    fun loadInitialState() {
        viewModelScope.launch {
            val outcome = SessionRepository.loadAllDetailed(app)
            val msg = when (outcome.issue) {
                SessionHistoryIssue.IO_FAILED ->
                    app.getString(R.string.session_history_io_error)
                SessionHistoryIssue.PARSE_FAILED ->
                    app.getString(R.string.session_history_parse_error)
                SessionHistoryIssue.PARTIAL_ENTRIES ->
                    app.getString(R.string.session_history_partial, outcome.corruptEntryCount)
                null -> null
            }
            _ui.update {
                it.copy(sessions = outcome.sessions, sessionLoadUserMessage = msg)
            }
            if (obdManager.isConnected) {
                val label = obdManager.connectedDeviceLabel
                _ui.update {
                    it.copy(
                        isConnected = true,
                        isConnecting = false,
                        connectionStatus = label?.let { l ->
                            app.getString(R.string.status_connected_param, l)
                        } ?: app.getString(R.string.status_connected),
                    )
                }
                val vi = obdManager.readVehicleInfo()
                val rm = obdManager.readReadiness()
                _ui.update { it.copy(vehicleInfo = vi, readinessMonitors = rm) }
            }
        }
    }

    fun onTransportDisconnectedUi() {
        _ui.update { it.copy(isMonitoring = false, errorsState = ErrorsState.Idle) }
    }

    fun updateSettings(s: AppSettings) {
        _ui.update { it.copy(settings = s) }
        AppSettings.save(app, s)
    }

    fun setCarProfile(p: CarProfile) {
        _ui.update { it.copy(carProfile = p) }
    }

    fun setMonitoring(on: Boolean) {
        _ui.update { it.copy(isMonitoring = on) }
    }

    fun mergeSensorReading(command: String, reading: SensorReading) {
        _sensorReadings.update { cur -> cur + (command to reading) }
    }

    fun clearSensorReadings() {
        _sensorReadings.value = emptyMap()
    }

    fun setPdfPendingFile(file: File?) {
        _ui.update { it.copy(pdfPendingFile = file) }
    }

    fun disconnectAdapter() {
        obdManager.disconnect()
        _ui.update {
            it.copy(
                isConnected = false,
                isConnecting = false,
                connectionStatus = app.getString(R.string.status_no_connection),
            )
        }
    }

    fun connectWifi(host: String, port: Int) {
        viewModelScope.launch {
            _ui.update {
                it.copy(
                    connectionStatus = app.getString(R.string.connecting_wifi, host, port.toString()),
                    isConnecting = true,
                    isConnected = false,
                )
            }
            val result = obdManager.connectWifi(host, port)
            _ui.update { it.copy(isConnecting = false) }
            if (result.isSuccess) {
                onConnectSuccess("$host:$port")
            } else {
                _ui.update {
                    it.copy(
                        connectionStatus = result.exceptionOrNull()?.message
                            ?: app.getString(R.string.error_wifi_connection),
                    )
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    fun connectBluetooth(device: android.bluetooth.BluetoothDevice, btAdapter: android.bluetooth.BluetoothAdapter?) {
        viewModelScope.launch {
            val name = try {
                device.name ?: device.address
            } catch (_: SecurityException) {
                device.address
            }
            _ui.update {
                it.copy(
                    connectionStatus = app.getString(R.string.connecting_bt, name),
                    isConnecting = true,
                    isConnected = false,
                )
            }
            val result = obdManager.connect(device, btAdapter)
            _ui.update { it.copy(isConnecting = false) }
            if (result.isSuccess) {
                onConnectSuccess(name)
            } else {
                _ui.update {
                    it.copy(
                        connectionStatus = result.exceptionOrNull()?.message
                            ?: app.getString(R.string.error_bluetooth_connection),
                    )
                }
            }
        }
    }

    private suspend fun onConnectSuccess(label: String) {
        _ui.update {
            it.copy(
                connectionStatus = app.getString(R.string.status_connected_param, label),
                isConnected = true,
                vehicleInfo = null,
                readinessMonitors = emptyList(),
            )
        }
        delay(AppConfig.POST_CONNECT_DELAY_MS)
        val vi = obdManager.readVehicleInfo()
        val rm = obdManager.readReadiness()
        _ui.update { it.copy(vehicleInfo = vi, readinessMonitors = rm) }
    }

    fun readErrors() {
        viewModelScope.launch {
            val st = _ui.value
            _ui.update { it.copy(errorsState = ErrorsState.Loading, errorsLoadingMessage = app.getString(R.string.errors_read_main)) }
            val mainResult = obdManager.readDtcs()
            _ui.update { it.copy(errorsLoadingMessage = app.getString(R.string.errors_read_pending)) }
            val pendingResult = obdManager.readPendingDtcs()
            _ui.update { it.copy(errorsLoadingMessage = app.getString(R.string.errors_read_permanent)) }
            val permanentResult = obdManager.readPermanentDtcs()
            val ff = if (st.settings.freezeFrameEnabled && mainResult is DtcResult.DtcList && mainResult.codes.isNotEmpty()) {
                _ui.update { it.copy(errorsLoadingMessage = app.getString(R.string.errors_read_freeze_frame)) }
                obdManager.readFreezeFrame()
            } else null
            val ecuResults = if (st.settings.otherEcusEnabled) {
                _ui.update { it.copy(errorsLoadingMessage = app.getString(R.string.errors_read_other_ecu)) }
                val makeHint = (st.carProfile as? CarProfile.Manual)?.make
                val r = obdManager.readOtherEcuDtcs(st.vehicleInfo, manualMakeHint = makeHint)
                _ui.update { it.copy(errorsLoadingMessage = app.getString(R.string.errors_read_finishing)) }
                r
            } else emptyList()
            _ui.update {
                it.copy(
                    errorsState = ErrorsState.Result(mainResult, pendingResult, permanentResult, ff, ecuResults),
                )
            }
            saveSessionAfterScan(mainResult, pendingResult, permanentResult, ff, ecuResults)
        }
    }

    private fun saveSessionAfterScan(
        mainResult: DtcResult,
        pendingResult: DtcResult,
        permanentResult: DtcResult,
        ff: FreezeFrameData?,
        ecuResults: List<EcuDtcResult>,
    ) {
        val st = _ui.value
        val mainCodes = (mainResult as? DtcResult.DtcList)?.codes ?: emptyList()
        val pendingCodes = (pendingResult as? DtcResult.DtcList)?.codes ?: emptyList()
        val permanentCodes = (permanentResult as? DtcResult.DtcList)?.codes ?: emptyList()
        val ecuErrors = ecuResults.mapNotNull { ecu ->
            val all = buildList {
                (ecu.result as? DtcResult.DtcList)?.codes?.let { addAll(it) }
                (ecu.pendingResult as? DtcResult.DtcList)?.codes?.let { addAll(it) }
                (ecu.permanentResult as? DtcResult.DtcList)?.codes?.let { addAll(it) }
            }
            if (all.isNotEmpty()) ecu.name to all else null
        }.toMap()
        val vehicleName = st.vehicleInfo
            ?.let { info ->
                listOfNotNull(info.detectedMake, info.detectedYear).joinToString(" ").ifBlank {
                    info.vin ?: app.getString(R.string.vehicle_fallback)
                }
            }
            ?: (if (st.carProfile is CarProfile.Manual) st.carProfile.displayName else app.getString(R.string.vehicle_fallback))
        SessionRepository.save(
            app,
            SessionRecord(
                vehicleName = vehicleName,
                vin = st.vehicleInfo?.vin,
                mainDtcs = mainCodes,
                pendingDtcs = pendingCodes,
                permanentDtcs = permanentCodes,
                hasFreezeFrame = ff != null && !ff.isEmpty,
                otherEcuErrors = ecuErrors,
            ),
        )
        _ui.update { it.copy(sessions = SessionRepository.loadAll(app)) }
    }

    fun clearErrors() {
        viewModelScope.launch {
            _ui.update {
                it.copy(
                    errorsState = ErrorsState.Loading,
                    errorsLoadingMessage = app.getString(R.string.errors_clearing),
                )
            }
            val ok = obdManager.clearDtcs()
            _ui.update { it.copy(errorsState = ErrorsState.Idle) }
            toast(if (ok) R.string.toast_errors_cleared else R.string.toast_clear_failed)
        }
    }

    fun clearSessionHistory() {
        SessionRepository.clear(app)
        _ui.update { it.copy(sessions = emptyList()) }
    }
}

class ObdScreenViewModelFactory(
    private val application: Application,
    private val obdManager: ObdConnectionManager,
) : androidx.lifecycle.ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(ObdScreenViewModel::class.java)) {
            return ObdScreenViewModel(application, obdManager) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }
}
