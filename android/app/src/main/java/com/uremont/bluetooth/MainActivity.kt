@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package com.uremont.bluetooth

import android.app.Application
import android.Manifest
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOutCubic
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.painterResource
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.core.content.ContextCompat
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import android.content.ClipData
import android.content.ClipboardManager
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel

// ─────────────────────────── BRAND PALETTE ──────────────────────────────────

private val BrandBlue     = Color(0xFF227DF5)
private val BrandBlueDark = Color(0xFF0063E4)
private val BrandBg       = Color(0xFF0D0D0F)
private val BrandSurface  = Color(0xFF18181B)
private val BrandCard     = Color(0xFF242428)
private val BrandBorder   = Color(0xFF36363C)
private val BrandText     = Color(0xFFF0F0F5)
private val BrandSubtext  = Color(0xFF8E8E93)
private val BrandYellow   = Color(0xFFFCC900)
private val BrandGreen    = Color(0xFF34C759)
private val BrandRed      = Color(0xFFFF3B30)
private val BrandOrange   = Color(0xFFFF9500)

// ─────────────────────────── THEME ──────────────────────────────────────────

private val UremontColorScheme = darkColorScheme(
    primary          = BrandBlue,
    onPrimary        = Color.White,
    primaryContainer = BrandBlueDark,
    secondary        = BrandYellow,
    onSecondary      = Color.Black,
    background       = BrandBg,
    onBackground     = BrandText,
    surface          = BrandSurface,
    onSurface        = BrandText,
    surfaceVariant   = BrandCard,
    onSurfaceVariant = BrandText,
    outline          = BrandBorder,
    error            = BrandRed,
    onError          = Color.White,
)

@Composable
fun UremontTheme(content: @Composable () -> Unit) {
    androidx.compose.material3.MaterialTheme(
        colorScheme = UremontColorScheme,
        typography  = Typography(),
        content     = content,
    )
}

// ─────────────────────────── CAR PROFILE ────────────────────────────────────

/**
 * Профиль автомобиля.
 *
 * Auto — протокол ATSP0, марка/модель определяются из VIN или не указаны.
 * Manual — пользователь вручную указывает марку, модель и год.
 *           На логику OBD2 не влияет (ATSP0 работает для всех машин).
 *           Используется только для DTC-описаний и генерации URL.
 */
sealed class CarProfile {
    data object Auto : CarProfile()
    data class Manual(val make: String, val model: String = "", val year: String = "") : CarProfile()

    val displayName: String get() = when (this) {
        is Auto   -> "Авто"
        is Manual -> listOf(make, model, year).filter { it.isNotBlank() }.joinToString(" ")
    }
    val isAuto: Boolean get() = this is Auto
}

// ─────────────────────────── CAR DATABASE ────────────────────────────────────

private val ALL_MAKES = listOf(
    "Audi", "BMW", "Chevrolet", "Citroën", "Dacia", "Fiat", "Ford",
    "GAZ (ГАЗ)", "Honda", "Hyundai", "Infiniti", "Jaguar", "Jeep",
    "Kia", "LADA (ВАЗ)", "Land Rover", "Lexus", "Mazda", "Mercedes-Benz",
    "Mitsubishi", "Nissan", "Opel", "Peugeot", "Porsche", "Renault",
    "Seat", "Škoda", "Subaru", "Suzuki", "Toyota", "UAZ (УАЗ)",
    "Volkswagen", "Volvo", "Другое / Иное",
)

// ─────────────────────────── MAIN ACTIVITY ───────────────────────────────────

/** Индексы страниц HorizontalPager. Используем константы вместо магических чисел. */
private const val PAGE_CONNECTION = 0
private const val PAGE_ERRORS     = 1
private const val PAGE_DASHBOARD  = 2

/**
 * true — планшет (smallestScreenWidth ≥ 600 dp).
 * Используется для адаптации отступов, размеров логотипа и числа колонок сетки.
 */
@Composable
private fun isTablet() = LocalConfiguration.current.smallestScreenWidthDp >= 600

/** Логотип UREMONT из векторного ресурса. */
@Composable
private fun UremontLogoIcon(modifier: Modifier = Modifier) {
    Image(
        painter = painterResource(R.drawable.ic_logo),
        contentDescription = "UREMONT",
        modifier = modifier,
    )
}

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val btManager  = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val btAdapter  = btManager?.adapter
        val obdManager = (application as UremontApp).obdConnectionManager
        setContent {
            UremontTheme {
                AppRoot(obdManager = obdManager, btAdapter = btAdapter)
            }
        }
    }
}

// ─────────────────────────── APP ROOT + SPLASH ───────────────────────────────

private enum class AppScreen { SPLASH, MAIN }

@Composable
private fun AppRoot(
    obdManager: ObdConnectionManager,
    btAdapter: BluetoothAdapter?,
) {
    var screen by remember { mutableStateOf(AppScreen.SPLASH) }
    AnimatedContent(targetState = screen, transitionSpec = { fadeIn(tween(600)) togetherWith fadeOut(tween(400)) }, label = "root") { s ->
        when (s) {
            AppScreen.SPLASH -> SplashScreen(onFinished = { screen = AppScreen.MAIN })
            AppScreen.MAIN   -> OBDScreen(obdManager, btAdapter)
        }
    }
}

@Composable
private fun SplashScreen(onFinished: () -> Unit) {
    val scale  = remember { Animatable(0.6f) }
    val alpha  = remember { Animatable(0f) }
    var progress by remember { mutableStateOf(0f) }
    LaunchedEffect(Unit) {
        launch { scale.animateTo(1f, tween(700, easing = EaseOutCubic)) }
        launch { alpha.animateTo(1f, tween(600)) }
        repeat(40) { delay(60); progress = (it + 1) / 40f }
        delay(300); onFinished()
    }
    Box(Modifier.fillMaxSize().background(BrandBg), contentAlignment = Alignment.Center) {
        Box(Modifier.size(320.dp).background(Brush.radialGradient(listOf(BrandBlue.copy(0.15f), Color.Transparent)), CircleShape))
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.scale(scale.value).alpha(alpha.value)) {
            UremontLogoIcon(Modifier.size(72.dp))
            Spacer(Modifier.height(20.dp))
            Text("UREMONT WHOOP", color = BrandText, fontSize = 26.sp, fontWeight = FontWeight.Black, letterSpacing = 2.sp)
            Spacer(Modifier.height(6.dp))
            Text("OBD2 Диагностика", color = BrandSubtext, fontSize = 14.sp)
            Spacer(Modifier.height(48.dp))
            LinearProgressIndicator(
                progress = { progress }, modifier = Modifier.width(200.dp).height(2.dp).clip(CircleShape),
                color = BrandBlue, trackColor = BrandBorder,
            )
        }
    }
}

// ─────────────────────────── OBD SCREEN (3 pages) ────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OBDScreen(
    obdManager: ObdConnectionManager,
    btAdapter: BluetoothAdapter?,
) {
    val context = LocalContext.current
    val app = context.applicationContext as Application
    val vm: ObdScreenViewModel = viewModel(factory = ObdScreenViewModelFactory(app, obdManager))
    val ui by vm.uiState.collectAsStateWithLifecycle()
    val sensorReadings by vm.sensorReadings.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    // ── Запрос разрешений ──────────────────────────────────────────────────────
    var showTransportPicker by remember { mutableStateOf(false) }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { grants ->
        if (grants.values.all { it }) showTransportPicker = true
    }

    var showDeviceSheet by remember { mutableStateOf(false) }
    var showManualPicker by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var showWifiSheet by remember { mutableStateOf(false) }
    var savedWifiHost by rememberSaveable { mutableStateOf(AppConfig.DEFAULT_WIFI_HOST) }
    var savedWifiPort by rememberSaveable { mutableStateOf(AppConfig.DEFAULT_WIFI_PORT.toString()) }
    var showHistory by remember { mutableStateOf(false) }

    val lifecycleOwner = LocalLifecycleOwner.current
    var isInBackground by remember { mutableStateOf(false) }
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> isInBackground = true
                Lifecycle.Event.ON_START -> isInBackground = false
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(Unit) {
        vm.loadInitialState()
    }

    LaunchedEffect(ui.sessionLoadUserMessage) {
        ui.sessionLoadUserMessage?.let {
            Toast.makeText(context, it, Toast.LENGTH_SHORT).show()
            vm.consumeSessionLoadMessage()
        }
    }

    LaunchedEffect(ui.isConnected) {
        if (!ui.isConnected) vm.onTransportDisconnectedUi()
    }

    // Цикл live PID: состояние читаем из ViewModel, чтобы не зациклиться на устаревшем snapshot.
    LaunchedEffect(ui.isMonitoring, ui.isConnected, isInBackground) {
        if (!ui.isMonitoring || !ui.isConnected) return@LaunchedEffect
        while (vm.uiState.value.isMonitoring && obdManager.isConnected) {
            if (isInBackground) {
                delay(AppConfig.LIVE_POLL_BACKGROUND_DELAY_MS)
                continue
            }
            val cycleStart = System.currentTimeMillis()
            for (pid in UNIVERSAL_PIDS) {
                if (!vm.uiState.value.isMonitoring) break
                vm.mergeSensorReading(pid.command, obdManager.pollSensor(pid))
            }
            val elapsed = System.currentTimeMillis() - cycleStart
            if (elapsed < AppConfig.LIVE_POLL_MIN_CYCLE_MS) {
                delay(AppConfig.LIVE_POLL_MIN_CYCLE_MS - elapsed)
            }
        }
    }

    fun requiredPermissions() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            listOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN)
        else listOf(Manifest.permission.BLUETOOTH, Manifest.permission.ACCESS_FINE_LOCATION)

    fun hasPermissions() = requiredPermissions().all {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }

    fun onSelectAdapter() {
        if (ui.isConnected) {
            vm.disconnectAdapter()
            return
        }
        if (hasPermissions()) showTransportPicker = true
        else permissionLauncher.launch(requiredPermissions().toTypedArray())
    }

    var savedPagerPage by rememberSaveable { mutableIntStateOf(0) }
    val pagerState = rememberPagerState(
        initialPage = savedPagerPage.coerceIn(0, 2),
        pageCount = { 3 },
    )
    LaunchedEffect(pagerState) {
        snapshotFlow { pagerState.currentPage }.collect { savedPagerPage = it }
    }

    Box(Modifier.fillMaxSize().background(BrandBg)) {
        HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
            when (page) {
                PAGE_CONNECTION -> ConnectionPage(
                    connectionStatus = ui.connectionStatus, isConnected = ui.isConnected, isConnecting = ui.isConnecting,
                    carProfile = ui.carProfile, vehicleInfo = ui.vehicleInfo,
                    readinessMonitors = ui.readinessMonitors,
                    onProfileAuto = { vm.setCarProfile(CarProfile.Auto) },
                    onProfileManual = { showManualPicker = true },
                    onSelectAdapter = { onSelectAdapter() },
                    pagerState = pagerState, scope = scope,
                )
                PAGE_ERRORS -> ErrorsPage(
                    isConnected = ui.isConnected, errorsState = ui.errorsState,
                    loadingMessage = ui.errorsLoadingMessage,
                    carProfile = ui.carProfile, vehicleInfo = ui.vehicleInfo,
                    onRead = { vm.readErrors() }, onClear = { vm.clearErrors() },
                    onDtcClick = { url ->
                        try {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        } catch (_: ActivityNotFoundException) {
                            Toast.makeText(context, context.getString(R.string.toast_browser_failed), Toast.LENGTH_SHORT).show()
                        }
                    },
                    onExportPdf = {
                        val result = ui.errorsState as? ErrorsState.Result ?: return@ErrorsPage
                        scope.launch {
                            val data = buildReportData(
                                vehicleInfo       = ui.vehicleInfo,
                                readinessMonitors = ui.readinessMonitors,
                                carProfile        = ui.carProfile,
                                result            = result,
                            )
                            vm.setPdfPendingFile(PdfReportGenerator.generate(context, data))
                        }
                    },
                )
                PAGE_DASHBOARD -> LiveDashboardPage(
                    isConnected = ui.isConnected, isMonitoring = ui.isMonitoring,
                    sensorReadings = sensorReadings, onToggle = { vm.setMonitoring(!ui.isMonitoring) },
                    onClearReadings = { vm.clearSensorReadings() },
                )
            }
        }

        PageDots(pagerState = pagerState, modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 10.dp))

        // ── Кнопки в правом верхнем углу: История + Настройки ────────────────
        Row(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 18.dp, end = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // Кнопка истории (📋)
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(BrandCard)
                    .border(1.dp, BrandBorder, RoundedCornerShape(10.dp))
                    .clickable { showHistory = true },
                contentAlignment = Alignment.Center,
            ) {
                Text("📋", fontSize = 16.sp)
            }
            // Кнопка настроек (⚙)
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(BrandCard)
                    .border(1.dp, BrandBorder, RoundedCornerShape(10.dp))
                    .clickable { showSettings = true },
                contentAlignment = Alignment.Center,
            ) {
                Text("⚙", fontSize = 16.sp)
            }
        }

    }

    ui.pdfPendingFile?.let { file ->
        AlertDialog(
            onDismissRequest = { vm.setPdfPendingFile(null) },
            containerColor = BrandSurface,
            titleContentColor = BrandText,
            textContentColor = BrandSubtext,
            title = { Text("Отчёт готов", fontWeight = FontWeight.Bold) },
            text = { Text("Открыть PDF в приложении для просмотра или отправить файл (мессенджер, почта…)?") },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (!PdfReportGenerator.open(context, file)) {
                            Toast.makeText(context, context.getString(R.string.toast_pdf_viewer_missing), Toast.LENGTH_SHORT).show()
                        }
                        vm.setPdfPendingFile(null)
                    },
                ) { Text("Открыть", color = BrandBlue, fontWeight = FontWeight.SemiBold) }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        PdfReportGenerator.share(context, file)
                        vm.setPdfPendingFile(null)
                    },
                ) { Text("Поделиться", color = BrandBlue, fontWeight = FontWeight.SemiBold) }
            },
        )
    }

    // ── Settings sheet ─────────────────────────────────────────────────────────
    if (showSettings) {
        SettingsSheet(settings = ui.settings, onUpdate = { vm.updateSettings(it) }, onDismiss = { showSettings = false })
    }

    // ── History sheet ──────────────────────────────────────────────────────────
    if (showHistory) {
        HistorySheet(
            sessions  = ui.sessions,
            onClear   = { vm.clearSessionHistory() },
            onDismiss = { showHistory = false },
        )
    }

    // ── Transport picker (BT / Wi-Fi) ─────────────────────────────────────────
    if (showTransportPicker) {
        ModalBottomSheet(
            onDismissRequest = { showTransportPicker = false },
            sheetState       = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor   = BrandSurface,
            dragHandle       = { BottomSheetDefaults.DragHandle(color = BrandBorder) },
        ) {
            TransportPickerContent(
                onBluetooth = {
                    showTransportPicker = false
                    // разрешения для BT уже были проверены перед показом пикера
                    showDeviceSheet = true
                },
                onWifi = { showTransportPicker = false; showWifiSheet = true },
            )
        }
    }

    // ── Wi-Fi sheet ────────────────────────────────────────────────────────────
    if (showWifiSheet) {
        ModalBottomSheet(
            onDismissRequest = { showWifiSheet = false },
            sheetState       = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor   = BrandSurface,
            dragHandle       = { BottomSheetDefaults.DragHandle(color = BrandBorder) },
        ) {
            WifiSheetContent(
                initialHost = savedWifiHost,
                initialPort = savedWifiPort,
                onConnect = { host, port ->
                    savedWifiHost = host; savedWifiPort = port
                    showWifiSheet = false
                    vm.connectWifi(host, port.toIntOrNull() ?: AppConfig.DEFAULT_WIFI_PORT)
                },
            )
        }
    }

    // ── Device sheet (Bluetooth) ──────────────────────────────────────────────
    if (showDeviceSheet) {
        ModalBottomSheet(
            onDismissRequest = { showDeviceSheet = false },
            sheetState       = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor   = BrandSurface,
            dragHandle       = { BottomSheetDefaults.DragHandle(color = BrandBorder) },
        ) {
            DeviceSheetContent(btAdapter = btAdapter, onSelect = { device ->
                showDeviceSheet = false
                vm.connectBluetooth(device, btAdapter)
            })
        }
    }

    // ── Manual car picker sheet ───────────────────────────────────────────────
    if (showManualPicker) {
        ModalBottomSheet(
            onDismissRequest = { showManualPicker = false },
            sheetState       = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor   = BrandSurface,
            dragHandle       = { BottomSheetDefaults.DragHandle(color = BrandBorder) },
        ) {
            ManualCarPickerSheet(
                current   = ui.carProfile as? CarProfile.Manual,
                onApply   = { profile -> vm.setCarProfile(profile); showManualPicker = false },
            )
        }
    }
}

// ─────────────────────────── REPORT BUILDER ──────────────────────────────────

/**
 * Собирает [DiagnosticReportData] из текущего состояния экрана.
 * Вызывается в OBDScreen, DTC-описания берутся из DtcLookup.dtcInfo().
 */
private fun buildReportData(
    vehicleInfo: VehicleInfo?,
    readinessMonitors: List<ReadinessMonitor>,
    carProfile: CarProfile,
    result: ErrorsState.Result,
): DiagnosticReportData {
    fun List<String>.toDtcEntries() = map { code ->
        val info = DtcLookup.dtcInfo(code, carProfile, vehicleInfo?.detectedMake)
        DtcEntry(code, info.title, info.causes, info.repair, info.severity)
    }

    val mainDtcs    = (result.result          as? DtcResult.DtcList)?.codes?.toDtcEntries() ?: emptyList()
    val pendingDtcs = (result.pendingResult   as? DtcResult.DtcList)?.codes?.toDtcEntries() ?: emptyList()
    val permanentDtcs = (result.permanentResult as? DtcResult.DtcList)?.codes?.toDtcEntries() ?: emptyList()

    // Все опрошенные блоки: сначала главный ЭБУ (всегда отвечает), затем остальные
    val allBlocks = buildList {
        add(EcuStatusEntry("Двигатель / ЭБУ", "7E0", responded = true,
            dtcs = mainDtcs, pendingDtcs = pendingDtcs, permanentDtcs = permanentDtcs))
        result.otherEcus.forEach { ecu ->
            val responded = ecu.result is DtcResult.DtcList || ecu.result is DtcResult.NoDtcs
            val dtcs = (ecu.result as? DtcResult.DtcList)?.codes?.toDtcEntries() ?: emptyList()
            val ecuPending = (ecu.pendingResult as? DtcResult.DtcList)?.codes?.toDtcEntries() ?: emptyList()
            val ecuPermanent = (ecu.permanentResult as? DtcResult.DtcList)?.codes?.toDtcEntries() ?: emptyList()
            add(EcuStatusEntry(ecu.name, ecu.address, responded, dtcs,
                pendingDtcs = ecuPending, permanentDtcs = ecuPermanent))
        }
    }

    val vehicleName = vehicleInfo
        ?.let { listOfNotNull(it.detectedMake, it.detectedYear).joinToString(" ").ifBlank { it.vin ?: "Автомобиль" } }
        ?: (if (carProfile is CarProfile.Manual) carProfile.displayName else "Автомобиль")

    return DiagnosticReportData(
        generatedAt          = System.currentTimeMillis(),
        vehicleDisplayName   = vehicleName,
        vin                  = vehicleInfo?.vin,
        detectedMake         = vehicleInfo?.detectedMake,
        detectedYear         = vehicleInfo?.detectedYear,
        ecuName              = vehicleInfo?.ecuName,
        calibrationId        = vehicleInfo?.calibrationId,
        cvnHex               = vehicleInfo?.cvnHex,
        mode09SupportMaskHex = vehicleInfo?.mode09SupportMaskHex,
        mode09ExtrasSummary  = vehicleInfo?.mode09ExtrasSummary,
        obdStandardLabel     = vehicleInfo?.obdStandardLabel,
        fuelTypeLabel        = vehicleInfo?.fuelTypeLabel,
        transmissionEcuName  = vehicleInfo?.transmissionEcuName,
        clusterOdometerKm    = vehicleInfo?.clusterOdometerKm?.toString(),
        clusterOdometerNote  = vehicleInfo?.clusterOdometerNote,
        vinVehicleDescriptor = vehicleInfo?.vinVehicleDescriptor,
        diagnosticBrandGroup = vehicleInfo?.diagnosticBrandGroup,
        distanceMilKm        = vehicleInfo?.distanceMilKm()?.toString(),
        distanceClearedKm    = vehicleInfo?.distanceClearedKm()?.toString(),
        fuelSystemStatus     = vehicleInfo?.fuelSystemStatus,
        warmUpsCleared       = vehicleInfo?.warmUpsCleared,
        timeSinceClearedMin  = vehicleInfo?.timeSinceClearedMin,
        readinessMonitors    = readinessMonitors,
        mainDtcs             = mainDtcs,
        pendingDtcs          = pendingDtcs,
        permanentDtcs        = permanentDtcs,
        freezeFrame          = result.freezeFrame,
        allBlocks            = allBlocks,
    )
}

// ─────────────────────────── APP SETTINGS ────────────────────────────────────

/**
 * Настройки приложения, управляемые пользователем через шестерёнку в правом углу.
 *
 * - [freezeFrameEnabled] добавляет ~3-5 сек (8 Mode 02 запросов); выключен по умолчанию
 * - [otherEcusEnabled]   добавляет порядка **1–3+ мин** на CAN (много `ATSH` + 03/07/0A и при сбое 03 ещё UDS); включён по умолчанию
 */
data class AppSettings(
    /** Снимать параметры двигателя в момент появления ошибки (Mode 02 Freeze Frame). */
    val freezeFrameEnabled: Boolean = false,
    /** Пробовать читать DTC с доп. ЭБУ (универсальные + марочные адреса; на CAN возможен UDS 0x19 после Mode 03). */
    val otherEcusEnabled: Boolean   = true,
) {
    companion object {
        private const val PREFS_NAME = "app_settings"
        private const val KEY_FREEZE = "freeze_frame_enabled"
        private const val KEY_ECUS   = "other_ecus_enabled"

        fun load(context: android.content.Context): AppSettings {
            val prefs = context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
            return AppSettings(
                freezeFrameEnabled = prefs.getBoolean(KEY_FREEZE, false),
                otherEcusEnabled   = prefs.getBoolean(KEY_ECUS, true),
            )
        }

        fun save(context: android.content.Context, s: AppSettings) {
            context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_FREEZE, s.freezeFrameEnabled)
                .putBoolean(KEY_ECUS, s.otherEcusEnabled)
                .apply()
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
//  PAGE 0 — CONNECTION
// ═════════════════════════════════════════════════════════════════════════════

@Composable
private fun ConnectionPage(
    connectionStatus: String,
    isConnected: Boolean,
    isConnecting: Boolean,
    carProfile: CarProfile,
    vehicleInfo: VehicleInfo?,
    readinessMonitors: List<ReadinessMonitor>,
    onProfileAuto: () -> Unit,
    onProfileManual: () -> Unit,
    /** Вызывается и для выбора адаптера (не подключено), и для отключения (подключено). */
    onSelectAdapter: () -> Unit,
    pagerState: PagerState,
    scope: kotlinx.coroutines.CoroutineScope,
) {
    val alpha = remember { Animatable(0f) }
    LaunchedEffect(Unit) { alpha.animateTo(1f, tween(400)) }

    val tablet = isTablet()
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BrandBg)
            .alpha(alpha.value)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = if (tablet) 28.dp else 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(if (tablet) 40.dp else 20.dp))

        // Logo
        UremontLogoIcon(Modifier.size(if (tablet) 60.dp else 48.dp))
        Spacer(Modifier.height(8.dp))
        Text("UREMONT WHOOP", color = BrandText, fontSize = if (tablet) 18.sp else 16.sp, fontWeight = FontWeight.Black, letterSpacing = 1.5.sp)
        Text("OBD2 Диагностика", color = BrandSubtext, fontSize = 12.sp)
        Spacer(Modifier.height(if (tablet) 28.dp else 16.dp))

        // Profile selector
        Text("ПРОФИЛЬ АВТОМОБИЛЯ", color = BrandSubtext, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val autoActive = carProfile.isAuto
            ProfileChip("Авто", autoActive) { onProfileAuto() }
            ProfileChip(
                label  = if (!carProfile.isAuto) carProfile.displayName else "Ручной режим",
                active = !carProfile.isAuto,
                onClick = onProfileManual,
            )
        }
        Spacer(Modifier.height(if (tablet) 20.dp else 12.dp))

        // Status
        StatusCard(status = connectionStatus, isConnected = isConnected, isLoading = isConnecting)
        Spacer(Modifier.height(if (tablet) 16.dp else 10.dp))

        // Adapter button
        if (isConnected) {
            WhoopButton(
                text = "Отключиться",
                onClick = onSelectAdapter,
                modifier = Modifier.fillMaxWidth(),
            )
        } else {
            WhoopButton(
                text = "Выбрать адаптер",
                onClick = onSelectAdapter,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        // Vehicle info card (shown after successful connection)
        AnimatedVisibility(visible = isConnected) {
            Column(Modifier.fillMaxWidth()) {
                Spacer(Modifier.height(20.dp))
                VehicleInfoCard(vehicleInfo = vehicleInfo)
                if (readinessMonitors.isNotEmpty()) {
                    Spacer(Modifier.height(12.dp))
                    ReadinessCard(monitors = readinessMonitors)
                }
                Spacer(Modifier.height(16.dp))
                // Navigate to errors
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(BrandGreen.copy(alpha = 0.12f))
                        .border(1.dp, BrandGreen.copy(alpha = 0.3f), RoundedCornerShape(12.dp))
                        .clickable { scope.launch { pagerState.animateScrollToPage(PAGE_ERRORS) } }
                        .padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("Перейти к диагностике", color = BrandGreen, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    Text("→", color = BrandGreen, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                }
            }
        }

        Spacer(Modifier.height(60.dp))
    }
}

@Composable
private fun ProfileChip(label: String, active: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(if (active) BrandBlue else BrandCard)
            .border(1.dp, if (active) BrandBlue else BrandBorder, RoundedCornerShape(20.dp))
            .clickable { onClick() }
            .padding(horizontal = 16.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text       = label,
            color      = if (active) Color.White else BrandSubtext,
            fontSize   = 13.sp,
            fontWeight = if (active) FontWeight.Bold else FontWeight.Normal,
            maxLines   = 1,
            overflow   = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun VehicleInfoCard(vehicleInfo: VehicleInfo?) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(BrandCard)
            .border(1.dp, BrandBlue.copy(alpha = 0.25f), RoundedCornerShape(16.dp))
            .padding(16.dp),
    ) {
        if (vehicleInfo == null) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("ДАННЫЕ АВТОМОБИЛЯ", color = BrandSubtext, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp)
                LinearProgressIndicator(
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(4.dp)),
                    color = BrandBlue,
                    trackColor = BrandBlue.copy(alpha = 0.15f),
                )
                Text("Читаю данные из ЭБУ…", color = BrandSubtext, fontSize = 13.sp)
                Text("Занимает 5–10 секунд", color = BrandSubtext.copy(alpha = 0.55f), fontSize = 11.sp)
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("ДАННЫЕ АВТОМОБИЛЯ", color = BrandSubtext, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp)

                val hasData = vehicleInfo.vin != null || vehicleInfo.detectedMake != null

                if (!hasData) {
                    Text("Автомобиль не передаёт данные (Mode 09 не поддерживается)", color = BrandSubtext, fontSize = 13.sp, lineHeight = 17.sp)
                } else {
                    // Порядок и подписи как в PDF (параметр слева — значение справа, разделители)
                    Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
                        vehicleInfo.detectedMake?.let { make ->
                            VehicleInfoRow("Марка автомобиля", make)
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.detectedYear?.let { year ->
                            VehicleInfoRow("Год выпуска", year)
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.vin?.let { vin ->
                            VehicleInfoRow("VIN", vin, FontFamily.Monospace)
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.vinVehicleDescriptor?.let { vds ->
                            VehicleInfoRow("VDS (VIN 4–9)", vds, FontFamily.Monospace)
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.diagnosticBrandGroup?.let { g ->
                            if (g != "OTHER") {
                                VehicleInfoRow("Диагност. группа марки", g, FontFamily.Monospace)
                                VehicleInfoCardRowDivider()
                            }
                        }
                        vehicleInfo.ecuName?.let { ecu ->
                            VehicleInfoRow("ЭБУ двигателя", ecu)
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.transmissionEcuName?.let { t ->
                            VehicleInfoRow("ЭБУ КПП (CAN 7E1)", t)
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.clusterOdometerKm?.let { km ->
                            val note = vehicleInfo.clusterOdometerNote?.let { " ($it)" } ?: ""
                            VehicleInfoRow("Одометр щитка (UDS, опытно)$note", "$km км")
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.obdStandardLabel?.let { o ->
                            VehicleInfoRow("Тип OBD (PID 1C)", o)
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.fuelTypeLabel?.let { f ->
                            VehicleInfoRow("Топливо (PID 51)", f)
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.calibrationId?.let { c ->
                            VehicleInfoRow("Calibration ID (09/03)", c)
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.cvnHex?.let { cvn ->
                            VehicleInfoRow("CVN (09/04)", cvn, FontFamily.Monospace)
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.mode09SupportMaskHex?.let { m ->
                            VehicleInfoRow("Маска Mode 09 (00)", m, FontFamily.Monospace)
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.mode09ExtrasSummary?.let { ex ->
                            VehicleInfoRow("Mode 09 (доп.)", ex, FontFamily.Monospace)
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.distanceMilKm()?.let { d ->
                            val suffix = if (vehicleInfo.usesImperialUnits) " км (конв.)" else " км"
                            VehicleInfoRow("Пробег с Check Engine (PID 0x21)", "$d$suffix", valueColor = if (d > 0) BrandYellow else BrandGreen)
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.distanceClearedKm()?.let { d ->
                            val suffix = if (vehicleInfo.usesImperialUnits) " км (конв.)" else " км"
                            VehicleInfoRow("С последнего сброса DTC (0x31, не одометр)", "$d$suffix")
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.fuelSystemStatus?.let { v ->
                            VehicleInfoRow("Система топливоподачи (PID 03)", v)
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.warmUpsCleared?.let { v ->
                            VehicleInfoRow("Прогревов после сброса DTC", "$v")
                            VehicleInfoCardRowDivider()
                        }
                        vehicleInfo.timeSinceClearedMin?.let { v ->
                            VehicleInfoRow("Минут с момента сброса DTC", "$v мин")
                            VehicleInfoCardRowDivider()
                        }
                        if (vehicleInfo.distanceMilKm() != null || vehicleInfo.distanceClearedKm() != null) {
                            Text(
                                "PID 0x31 — не одометр приборки, а пробег после сброса ошибок сканером (max 65535 км).",
                                color = BrandSubtext.copy(alpha = 0.72f),
                                fontSize = 10.sp,
                                lineHeight = 13.sp,
                                modifier = Modifier.padding(top = 4.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun VehicleInfoCardRowDivider() {
    Spacer(Modifier.height(5.dp))
    Box(Modifier.fillMaxWidth().height(0.5.dp).background(BrandSubtext.copy(alpha = 0.18f)))
    Spacer(Modifier.height(5.dp))
}

@Composable
private fun VehicleInfoRow(
    label: String,
    value: String,
    fontFamily: FontFamily = FontFamily.Default,
    valueColor: Color = BrandText,
) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            label,
            color = BrandSubtext,
            fontSize = 11.sp,
            modifier = Modifier.widthIn(max = 168.dp),
        )
        Text(
            value,
            color = valueColor,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = fontFamily,
            modifier = Modifier.weight(1f),
            textAlign = TextAlign.End,
            maxLines = 6,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun ReadinessCard(monitors: List<ReadinessMonitor>) {
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
            .background(BrandCard).border(1.dp, BrandBorder, RoundedCornerShape(16.dp)).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            "ГОТОВНОСТЬ СИСТЕМ",
            color = BrandSubtext, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.2.sp,
        )
        monitors.forEach { m ->
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(m.name, color = BrandText, fontSize = 12.sp, modifier = Modifier.weight(1f))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Box(Modifier.size(8.dp).background(if (m.ready) BrandGreen else BrandYellow, CircleShape))
                    Text(
                        if (m.ready) "Готов" else "Не готов",
                        color = if (m.ready) BrandGreen else BrandYellow,
                        fontSize = 11.sp, fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
//  PAGE 1 — ERRORS
// ═════════════════════════════════════════════════════════════════════════════

@Composable
private fun ErrorsPage(
    isConnected: Boolean,
    errorsState: ErrorsState,
    loadingMessage: String,
    carProfile: CarProfile,
    vehicleInfo: VehicleInfo?,
    onRead: () -> Unit,
    onClear: () -> Unit,
    onDtcClick: (url: String) -> Unit,
    onExportPdf: () -> Unit,
) {
    val tablet = isTablet()
    Column(
        modifier = Modifier.fillMaxSize().background(BrandBg)
            .padding(start = if (tablet) 20.dp else 12.dp, end = if (tablet) 20.dp else 12.dp, top = if (tablet) 20.dp else 12.dp),
    ) {
        PageHeader(
            title = "ДИАГНОСТИКА ОШИБОК",
            subtitle = if (isConnected) "● ${vehicleInfo?.detectedMake ?: carProfile.displayName}" else "Нет соединения",
            subtitleColor = if (isConnected) BrandGreen else BrandRed,
        )
        Spacer(Modifier.height(14.dp))

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            WhoopButton(
                text = when (errorsState) { is ErrorsState.Loading -> "Опрашиваю…"; else -> "Прочитать" },
                label = "OBD", onClick = onRead,
                enabled = isConnected && errorsState !is ErrorsState.Loading,
                isLoading = errorsState is ErrorsState.Loading,
                modifier = Modifier.weight(1f),
            )
            ClearButton(enabled = isConnected && errorsState !is ErrorsState.Loading, onClick = onClear, modifier = Modifier.weight(1f))
            // Кнопка экспорта PDF — только когда есть результат
            if (errorsState is ErrorsState.Result) {
                Box(
                    modifier = Modifier
                        .height(48.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(BrandCard)
                        .border(1.dp, BrandBorder, RoundedCornerShape(14.dp))
                        .clickable { onExportPdf() }
                        .padding(horizontal = 14.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("📤 PDF", color = BrandText, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        Spacer(Modifier.height(16.dp))

        when (errorsState) {
            is ErrorsState.Idle -> EmptyHint("🔍",
                if (isConnected) "Нажмите «Прочитать»" else "Подключите адаптер",
                if (isConnected) "Запрос кодов неисправности OBD2" else "Выберите ELM327 адаптер на первом экране")
            is ErrorsState.Loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    CircularProgressIndicator(color = BrandBlue, modifier = Modifier.size(40.dp))
                    Text(loadingMessage, color = BrandSubtext, fontSize = 14.sp)
                    Text("Не закрывайте приложение", color = BrandSubtext.copy(alpha = 0.6f), fontSize = 12.sp)
                }
            }
            is ErrorsState.Result -> {
                val state = errorsState
                LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp), contentPadding = PaddingValues(bottom = 80.dp)) {
                    // ── Снимок параметров (Freeze Frame) ──────────────────────
                    state.freezeFrame?.let { ff ->
                        if (!ff.isEmpty) {
                            item { FreezeFrameCard(ff) }
                        }
                    }

                    // ── Постоянные ошибки ──────────────────────────────────────
                    when (val r = state.result) {
                        is DtcResult.NoDtcs      -> item {
                            EmptyHint(
                                "✅", "Постоянных ошибок нет",
                                "Mode 03: подтверждённых кодов нет. По КПП/ABS/SRS см. блоки ниже при включённых «Других блоках».",
                            )
                        }
                        is DtcResult.RawResponse -> item { EmptyHint("⚠", "Нераспознанный ответ", r.raw) }
                        is DtcResult.Error       -> item { EmptyHint("✕", "Ошибка соединения", r.message) }
                        is DtcResult.DtcList     -> {
                            item {
                                DtcSectionHeader(
                                    label = "ПОСТОЯННЫЕ ОШИБКИ",
                                    count = r.codes.size,
                                    color = BrandRed,
                                    hint = "Mode 03 — подтверждённые коды в памяти ЭБУ («сохранённые» в OBD-II)",
                                )
                            }
                            items(r.codes) { code ->
                                val info = DtcLookup.dtcInfo(code, carProfile, vehicleInfo?.detectedMake)
                                DtcErrorCard(code = code, info = info,
                                    url = DtcLookup.buildUremontUrl(carProfile, vehicleInfo, code, info),
                                    onOpenUrl = onDtcClick)
                            }
                        }
                    }

                    // ── Ожидающие ошибки (Mode 07) ────────────────────────────
                    when (val p = state.pendingResult) {
                        is DtcResult.DtcList -> {
                            item {
                                Spacer(Modifier.height(4.dp))
                                DtcSectionHeader(
                                    label = "ОЖИДАЮЩИЕ ОШИБКИ",
                                    count = p.codes.size,
                                    color = BrandYellow,
                                    hint  = "Зафиксированы в текущем цикле, но ещё не стали постоянными",
                                )
                            }
                            items(p.codes) { code ->
                                val info = DtcLookup.dtcInfo(code, carProfile, vehicleInfo?.detectedMake)
                                DtcErrorCard(code = code, info = info,
                                    url = DtcLookup.buildUremontUrl(carProfile, vehicleInfo, code, info),
                                    onOpenUrl = onDtcClick,
                                    isPending = true)
                            }
                        }
                        else -> {}
                    }

                    // ── Mode 0A Permanent DTC ─────────────────────────────────
                    when (val pr = state.permanentResult) {
                        is DtcResult.DtcList -> {
                            item {
                                Spacer(Modifier.height(4.dp))
                                DtcSectionHeader(
                                    label = "ПОСТОЯННЫЕ ЭМИССИОННЫЕ (0A)",
                                    count = pr.codes.size,
                                    color = BrandOrange,
                                    hint = "Mode 0A (Permanent DTC): не гасятся сразу после Clear; чаще USA OBD-II",
                                )
                            }
                            items(pr.codes) { code ->
                                val info = DtcLookup.dtcInfo(code, carProfile, vehicleInfo?.detectedMake)
                                DtcErrorCard(code = code, info = info,
                                    url = DtcLookup.buildUremontUrl(carProfile, vehicleInfo, code, info),
                                    onOpenUrl = onDtcClick)
                            }
                        }
                        else -> {}
                    }

                    // ── Единый раздел: все опрошенные блоки ──────────────────
                    item {
                        Spacer(Modifier.height(4.dp))
                        DtcSectionHeader(
                            label = "БЛОКИ УПРАВЛЕНИЯ",
                            count = null,
                            color = BrandBlue,
                            hint  = "Mode 03 по CAN-адресам: КПП 7E1, у Ford — доп. адреса; те же сохранённые коды, что в сканерах",
                        )
                    }
                    // Главный ЭБУ — компактная карточка-статус (DTCs показаны выше)
                    item {
                        MainEcuBlockCard(
                            mainResult    = state.result,
                            pendingResult = state.pendingResult,
                        )
                    }
                    // Остальные блоки: все результаты, включая «нет ответа»
                    if (state.otherEcus.isNotEmpty()) {
                        items(state.otherEcus) { ecu ->
                            OtherEcuCard(ecu = ecu, carProfile = carProfile, vehicleInfo = vehicleInfo, onDtcClick = onDtcClick)
                        }
                    } else {
                        item {
                            EmptyHint("⚙", "Дополнительные блоки не опрошены",
                                "Включите «Другие блоки» в настройках")
                        }
                    }
                }
            }
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
//  PAGE 2 — LIVE DASHBOARD
// ═════════════════════════════════════════════════════════════════════════════

@Composable
private fun LiveDashboardPage(
    isConnected: Boolean,
    isMonitoring: Boolean,
    sensorReadings: Map<String, SensorReading>,
    onToggle: () -> Unit,
    onClearReadings: () -> Unit,
) {
    val tablet = isTablet()
    Column(Modifier.fillMaxSize().background(BrandBg).padding(start = 16.dp, end = 16.dp, top = if (tablet) 20.dp else 12.dp)) {
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            PageHeader(title = "LIVE ДАТЧИКИ",
                subtitle = if (isConnected) "● Онлайн" else "Нет соединения",
                subtitleColor = if (isConnected) BrandGreen else BrandRed)
            if (isMonitoring) {
                val pulse = rememberInfiniteTransition(label = "pulse")
                val pa by pulse.animateFloat(0.4f, 1f, infiniteRepeatable(tween(900), RepeatMode.Reverse), "pa")
                Box(Modifier.size(10.dp).alpha(pa).background(BrandGreen, CircleShape))
            }
        }
        Spacer(Modifier.height(10.dp))

        Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(10.dp)) {
            WhoopButton(
                text = if (!isConnected) "Нет соединения" else if (isMonitoring) "Остановить" else "Запустить мониторинг",
                label = if (isMonitoring) "■" else "▶", onClick = onToggle,
                enabled = isConnected, modifier = Modifier.weight(1f),
            )
            if (sensorReadings.isNotEmpty()) {
                Box(
                    modifier = Modifier.clip(RoundedCornerShape(14.dp)).background(BrandCard)
                        .border(1.dp, BrandBorder, RoundedCornerShape(14.dp))
                        .clickable { onClearReadings() }.padding(horizontal = 16.dp, vertical = 14.dp),
                    contentAlignment = Alignment.Center,
                ) { Text("Сброс", color = BrandSubtext, fontSize = 13.sp, fontWeight = FontWeight.Medium) }
            }
        }
        Spacer(Modifier.height(12.dp))

        when {
            !isConnected -> EmptyHint("📡", "Нет соединения", "Подключите адаптер ELM327")
            !isMonitoring && sensorReadings.isEmpty() ->
                EmptyHint("▶", "Нажмите «Запустить мониторинг»", "Данные всех датчиков обновляются в реальном времени")
            else -> LazyVerticalGrid(
                columns = GridCells.Adaptive(if (tablet) 155.dp else 130.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(bottom = 80.dp),
            ) {
                gridItems(UNIVERSAL_PIDS) { pid -> SensorCard(pid = pid, reading = sensorReadings[pid.command]) }
            }
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
//  TRANSPORT PICKER SHEET  (Bluetooth / Wi-Fi)
// ═════════════════════════════════════════════════════════════════════════════

@Composable
private fun TransportPickerContent(
    onBluetooth: () -> Unit,
    onWifi: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            "Тип подключения",
            color = BrandText, fontSize = 17.sp, fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(bottom = 4.dp),
        )
        // Bluetooth
        TransportOptionCard(
            icon = "📡",
            title = "Bluetooth",
            subtitle = "Классический ELM327 (синий/чёрный свисток)",
            accent = BrandBlue,
            onClick = onBluetooth,
        )
        // Wi-Fi
        TransportOptionCard(
            icon = "📶",
            title = "Wi-Fi",
            subtitle = "ELM327 Wi-Fi (Kingbolen, PIC18F25K80 и аналоги)",
            accent = BrandGreen,
            onClick = onWifi,
        )
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun TransportOptionCard(
    icon: String,
    title: String,
    subtitle: String,
    accent: Color,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(BrandCard)
            .border(1.dp, accent.copy(alpha = 0.35f), RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(46.dp)
                .background(accent.copy(alpha = 0.12f), RoundedCornerShape(12.dp)),
            contentAlignment = Alignment.Center,
        ) { Text(icon, fontSize = 22.sp) }
        Column(modifier = Modifier.weight(1f)) {
            Text(title, color = BrandText, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            Text(subtitle, color = BrandSubtext, fontSize = 12.sp, lineHeight = 16.sp)
        }
        Text("→", color = accent, fontSize = 18.sp, fontWeight = FontWeight.Bold)
    }
}

// ═════════════════════════════════════════════════════════════════════════════
//  WI-FI SHEET
// ═════════════════════════════════════════════════════════════════════════════

/**
 * Шит подключения к Wi-Fi ELM327.
 * Показывает пошаговую инструкцию, кнопку открытия системных настроек Wi-Fi,
 * поля ввода IP:порт с пресетами популярных адаптеров.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WifiSheetContent(
    initialHost: String,
    initialPort: String,
    onConnect: (host: String, port: String) -> Unit,
) {
    val context = LocalContext.current
    var host by remember { mutableStateOf(initialHost.ifBlank { AppConfig.DEFAULT_WIFI_HOST }) }
    var port by remember { mutableStateOf(initialPort.ifBlank { AppConfig.DEFAULT_WIFI_PORT.toString() }) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Подключение по Wi-Fi", color = BrandText, fontSize = 17.sp, fontWeight = FontWeight.Bold)

        // Пошаговая инструкция
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(BrandCard)
                .border(1.dp, BrandBorder, RoundedCornerShape(12.dp))
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("Как подключиться", color = BrandText, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            listOf(
                "Вставьте адаптер в OBD2-разъём, включите зажигание",
                "Откройте настройки Wi-Fi и подключитесь к сети адаптера (обычно «OBDII», «ELM327» или «WiFi_OBDII»)",
                "Вернитесь в приложение и нажмите «Подключить»",
            ).forEachIndexed { i, text ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(
                        modifier = Modifier.size(18.dp).background(BrandBlue, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("${i + 1}", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    }
                    Text(text, color = BrandSubtext, fontSize = 12.sp, lineHeight = 17.sp, modifier = Modifier.weight(1f))
                }
            }
            // Кнопка быстрого перехода в настройки Wi-Fi
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(BrandBlue.copy(alpha = 0.12f))
                    .border(1.dp, BrandBlue.copy(alpha = 0.3f), RoundedCornerShape(8.dp))
                    .clickable {
                        context.startActivity(Intent(Settings.ACTION_WIFI_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                    }
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text("📶  Открыть настройки Wi-Fi", color = BrandBlue, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }

        // Host
        Text("IP-адрес адаптера", color = BrandSubtext, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp)
        OutlinedTextField(
            value = host,
            onValueChange = { host = it },
            placeholder = { Text("192.168.0.10", color = BrandBorder, fontSize = 14.sp) },
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor   = BrandBlue,
                unfocusedBorderColor = BrandBorder,
                focusedTextColor     = BrandText,
                unfocusedTextColor   = BrandText,
                cursorColor          = BrandBlue,
            ),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Next),
            singleLine = true,
            modifier   = Modifier.fillMaxWidth(),
        )

        // Port
        Text("Порт", color = BrandSubtext, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp)
        OutlinedTextField(
            value = port,
            onValueChange = { port = it },
            placeholder = { Text("35000", color = BrandBorder, fontSize = 14.sp) },
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor   = BrandBlue,
                unfocusedBorderColor = BrandBorder,
                focusedTextColor     = BrandText,
                unfocusedTextColor   = BrandText,
                cursorColor          = BrandBlue,
            ),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
            singleLine = true,
            modifier   = Modifier.fillMaxWidth(),
        )

        // Пресеты — самые популярные Wi-Fi ELM327 адреса; FlowRow переносит на следующую строку
        // если не помещается на экране (телефон vs планшет)
        Text("Популярные адаптеры", color = BrandSubtext, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp)
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement   = Arrangement.spacedBy(6.dp),
        ) {
            WifiPreset("Kingbolen / Vgate", "192.168.0.10", "35000") { h, p -> host = h; port = p }
            WifiPreset("ESP32 AP",          "192.168.4.1",  "35000") { h, p -> host = h; port = p }
            WifiPreset("OBDLink WiFi",      "192.168.0.10", "23")    { h, p -> host = h; port = p }
            WifiPreset("Alt 10.0.0.x",      "10.0.0.1",    "35000") { h, p -> host = h; port = p }
        }

        Spacer(Modifier.height(4.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .background(BrandBlue)
                .clickable(enabled = host.isNotBlank() && port.isNotBlank()) {
                    onConnect(host.trim(), port.trim())
                }
                .padding(vertical = 14.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text("Подключить", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun WifiPreset(label: String, host: String, port: String, onApply: (String, String) -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(BrandCard)
            .border(1.dp, BrandBorder, RoundedCornerShape(8.dp))
            .clickable { onApply(host, port) }
            .padding(horizontal = 10.dp, vertical = 6.dp),
    ) {
        Text(label, color = BrandSubtext, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
    }
}

// ═════════════════════════════════════════════════════════════════════════════
//  MANUAL CAR PICKER SHEET
// ═════════════════════════════════════════════════════════════════════════════

@Composable
private fun ManualCarPickerSheet(
    current: CarProfile.Manual?,
    onApply: (CarProfile.Manual) -> Unit,
) {
    var selectedMake by remember { mutableStateOf(current?.make ?: "") }
    var model        by remember { mutableStateOf(current?.model ?: "") }
    var year         by remember { mutableStateOf(current?.year ?: "") }
    var search       by remember { mutableStateOf("") }

    val filteredMakes = remember(search) {
        if (search.isBlank()) ALL_MAKES
        else ALL_MAKES.filter { it.contains(search, ignoreCase = true) }
    }

    Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.85f)) {
        // Header
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Text("Выбор автомобиля", color = BrandText, fontSize = 17.sp, fontWeight = FontWeight.Bold)
            if (selectedMake.isNotBlank()) {
                Box(
                    modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(BrandBlue)
                        .clickable { onApply(CarProfile.Manual(selectedMake, model, year)) }
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) { Text("Применить", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold) }
            }
        }

        if (selectedMake.isBlank()) {
            // Make selection
            OutlinedTextField(
                value = search, onValueChange = { search = it },
                placeholder = { Text("Поиск марки…", color = BrandBorder, fontSize = 14.sp) },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = BrandBlue, unfocusedBorderColor = BrandBorder,
                    focusedTextColor = BrandText, unfocusedTextColor = BrandText, cursorColor = BrandBlue,
                ),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                singleLine = true,
            )
            Spacer(Modifier.height(8.dp))
            LazyColumn(
                contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                items(filteredMakes) { make ->
                    Box(
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(BrandCard)
                            .border(1.dp, BrandBorder, RoundedCornerShape(12.dp))
                            .clickable { selectedMake = make }.padding(horizontal = 16.dp, vertical = 13.dp),
                    ) { Text(make, color = BrandText, fontSize = 14.sp, fontWeight = FontWeight.Medium) }
                }
            }
        } else {
            // Model + year
            Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                // Selected make chip with edit
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(
                        Modifier.clip(RoundedCornerShape(20.dp)).background(BrandBlue).padding(horizontal = 14.dp, vertical = 7.dp)
                    ) { Text(selectedMake, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold) }
                    Box(
                        Modifier.clip(RoundedCornerShape(20.dp)).background(BrandCard)
                            .border(1.dp, BrandBorder, RoundedCornerShape(20.dp))
                            .clickable { selectedMake = ""; search = "" }.padding(horizontal = 12.dp, vertical = 7.dp),
                    ) { Text("Изменить", color = BrandSubtext, fontSize = 12.sp) }
                }

                OutlinedTextField(
                    value = model, onValueChange = { model = it },
                    label = { Text("Модель (необязательно)", color = BrandSubtext, fontSize = 12.sp) },
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = BrandBlue, unfocusedBorderColor = BrandBorder,
                        focusedTextColor = BrandText, unfocusedTextColor = BrandText,
                        focusedLabelColor = BrandBlue, unfocusedLabelColor = BrandSubtext, cursorColor = BrandBlue,
                    ),
                    modifier = Modifier.fillMaxWidth(), singleLine = true,
                    placeholder = { Text("например: 3 Series, Camry, Creta…", color = BrandBorder, fontSize = 13.sp) },
                )
                OutlinedTextField(
                    value = year, onValueChange = { if (it.length <= 4) year = it.filter { c -> c.isDigit() } },
                    label = { Text("Год выпуска (необязательно)", color = BrandSubtext, fontSize = 12.sp) },
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = BrandBlue, unfocusedBorderColor = BrandBorder,
                        focusedTextColor = BrandText, unfocusedTextColor = BrandText,
                        focusedLabelColor = BrandBlue, unfocusedLabelColor = BrandSubtext, cursorColor = BrandBlue,
                    ),
                    modifier = Modifier.fillMaxWidth(), singleLine = true,
                    placeholder = { Text("например: 2019", color = BrandBorder, fontSize = 13.sp) },
                )

                Spacer(Modifier.height(4.dp))
                WhoopButton(
                    text = "Применить профиль", label = "✓",
                    onClick = { onApply(CarProfile.Manual(selectedMake, model, year)) },
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(16.dp))
            }
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SHARED UI COMPONENTS
// ═════════════════════════════════════════════════════════════════════════════

@Composable
private fun PageHeader(title: String, subtitle: String, subtitleColor: Color = BrandSubtext) {
    Column {
        Text(title, color = BrandText, fontSize = 18.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
        Text(subtitle, color = subtitleColor, fontSize = 11.sp, fontWeight = FontWeight.Medium)
    }
}

// ─────────────────────────── SETTINGS SHEET ──────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HistorySheet(
    sessions: List<SessionRecord>,
    onClear: () -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState       = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor   = BrandSurface,
        dragHandle       = { BottomSheetDefaults.DragHandle(color = BrandBorder) },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.85f)
                .padding(horizontal = 20.dp),
        ) {
            // ── Заголовок ──────────────────────────────────────────────────
            Row(
                Modifier.fillMaxWidth().padding(bottom = 16.dp),
                Arrangement.SpaceBetween,
                Alignment.CenterVertically,
            ) {
                Text("История диагностики", color = BrandText, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                if (sessions.isNotEmpty()) {
                    Box(
                        Modifier
                            .clip(RoundedCornerShape(10.dp))
                            .background(BrandCard)
                            .border(1.dp, BrandBorder, RoundedCornerShape(10.dp))
                            .clickable { onClear() }
                            .padding(horizontal = 12.dp, vertical = 6.dp),
                    ) {
                        Text("Очистить", color = BrandRed, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                    }
                }
            }

            if (sessions.isEmpty()) {
                // ── Пусто ──────────────────────────────────────────────────
                Box(Modifier.fillMaxSize(), Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("📋", fontSize = 40.sp)
                        Text("Историй пока нет", color = BrandSubtext, fontSize = 15.sp)
                        Text("Записи появятся после сканирования", color = BrandBorder, fontSize = 12.sp)
                    }
                }
            } else {
                // ── Список сессий ──────────────────────────────────────────
                LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(sessions) { session -> SessionCard(session) }
                    item { Spacer(Modifier.height(24.dp)) }
                }
            }
        }
    }
}

@Composable
private fun SessionCard(session: SessionRecord) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(BrandCard)
            .border(1.dp, BrandBorder, RoundedCornerShape(14.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        // ── Дата + иконка снимка ───────────────────────────────────────────
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Text(session.formattedDate, color = BrandText, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                if (session.hasFreezeFrame) {
                    // Значок наличия снимка параметров
                    Box(
                        Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(Color(0xFF1C2A1E))
                            .border(1.dp, BrandGreen.copy(0.4f), RoundedCornerShape(6.dp))
                            .padding(horizontal = 7.dp, vertical = 3.dp),
                    ) {
                        Text("📷 Снимок", color = BrandGreen, fontSize = 10.sp, fontWeight = FontWeight.Medium)
                    }
                }
                // Бейдж количества ошибок
                val errorCount = session.totalErrors
                Box(
                    Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(if (errorCount > 0) BrandOrange.copy(0.15f) else BrandGreen.copy(0.15f))
                        .border(1.dp, if (errorCount > 0) BrandOrange.copy(0.4f) else BrandGreen.copy(0.4f), RoundedCornerShape(6.dp))
                        .padding(horizontal = 7.dp, vertical = 3.dp),
                ) {
                    Text(
                        if (errorCount > 0) "⚠ $errorCount ошибок" else "✓ Чисто",
                        color = if (errorCount > 0) BrandOrange else BrandGreen,
                        fontSize = 10.sp, fontWeight = FontWeight.Bold,
                    )
                }
            }
        }

        // ── Авто / VIN ─────────────────────────────────────────────────────
        Text(
            session.vehicleName + (session.vin?.let { " · ${it.takeLast(8)}" } ?: ""),
            color = BrandSubtext, fontSize = 12.sp,
        )

        // ── Коды ошибок ────────────────────────────────────────────────────
        val allCodes = session.mainDtcs + session.pendingDtcs +
                session.otherEcuErrors.values.flatten()
        if (allCodes.isNotEmpty()) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                // Показываем максимум 6 кодов, остаток в "+N"
                val visible = allCodes.take(6)
                val rest    = allCodes.size - visible.size
                visible.forEach { code ->
                    val isPending = code in session.pendingDtcs
                    Box(
                        Modifier
                            .clip(RoundedCornerShape(5.dp))
                            .background(if (isPending) BrandOrange.copy(0.12f) else BrandBlue.copy(0.12f))
                            .border(1.dp, if (isPending) BrandOrange.copy(0.3f) else BrandBlue.copy(0.3f), RoundedCornerShape(5.dp))
                            .padding(horizontal = 6.dp, vertical = 3.dp),
                    ) {
                        Text(code, color = if (isPending) BrandOrange else BrandBlue, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    }
                }
                if (rest > 0) {
                    Text("+$rest", color = BrandSubtext, fontSize = 10.sp, modifier = Modifier.align(Alignment.CenterVertically))
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsSheet(settings: AppSettings, onUpdate: (AppSettings) -> Unit, onDismiss: () -> Unit) {
    var showConsole by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState       = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor   = BrandSurface,
        dragHandle       = { BottomSheetDefaults.DragHandle(color = BrandBorder) },
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 36.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                "НАСТРОЙКИ ДИАГНОСТИКИ",
                color = BrandSubtext, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp,
            )
            Spacer(Modifier.height(12.dp))

            SettingToggleRow(
                title       = "Снимок параметров при ошибке",
                subtitle    = "Mode 02 — фиксирует показатели датчиков в момент появления каждой ошибки. Увеличивает время чтения.",
                enabled     = settings.freezeFrameEnabled,
                onToggle    = { onUpdate(settings.copy(freezeFrameEnabled = it)) },
            )

            Spacer(Modifier.height(4.dp))

            SettingToggleRow(
                title       = "Опрос других блоков",
                subtitle    = "Пробует считать DTC из ABS, SRS, КПП и BCM по CAN-шине. Работает только на машинах с 2008+ (CAN). Может занять 10–20 сек.",
                enabled     = settings.otherEcusEnabled,
                onToggle    = { onUpdate(settings.copy(otherEcusEnabled = it)) },
            )

            Spacer(Modifier.height(12.dp))

            // ── Консоль отладки ───────────────────────────────────────────────
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(BrandCard)
                    .border(1.dp, BrandBorder, RoundedCornerShape(14.dp))
                    .clickable { showConsole = true }
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("Консоль отладки", color = BrandText, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    Text(
                        "Логи соединения и OBD2-команд — ${DebugLogger.size} записей",
                        color = BrandSubtext, fontSize = 11.sp,
                    )
                }
                Text("›", color = BrandSubtext, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            }
        }
    }

    if (showConsole) {
        DebugConsoleDialog(onDismiss = { showConsole = false })
    }
}

@Composable
private fun SettingToggleRow(title: String, subtitle: String, enabled: Boolean, onToggle: (Boolean) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(BrandCard)
            .border(1.dp, BrandBorder, RoundedCornerShape(14.dp))
            .clickable { onToggle(!enabled) }
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, color = BrandText, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            Text(subtitle, color = BrandSubtext, fontSize = 11.sp, lineHeight = 15.sp)
        }
        // Toggle indicator
        Box(
            modifier = Modifier
                .width(46.dp).height(26.dp)
                .clip(RoundedCornerShape(13.dp))
                .background(if (enabled) BrandBlue else BrandBorder),
            contentAlignment = if (enabled) Alignment.CenterEnd else Alignment.CenterStart,
        ) {
            Box(
                Modifier.padding(3.dp).size(20.dp).clip(CircleShape).background(Color.White),
            )
        }
    }
}

@Composable
private fun DebugConsoleDialog(onDismiss: () -> Unit) {
    val context   = LocalContext.current
    val listState = rememberLazyListState()

    // Живой снимок логов, обновляемый каждые 500 мс
    var entries by remember { mutableStateOf(DebugLogger.entries) }
    LaunchedEffect(Unit) {
        while (true) {
            entries = DebugLogger.entries
            // Автопрокрутка к последней записи
            if (entries.isNotEmpty()) listState.animateScrollToItem(entries.lastIndex)
            delay(500)
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties       = DialogProperties(usePlatformDefaultWidth = false, dismissOnClickOutside = true),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xFF0A0A0D))
                .padding(horizontal = 0.dp),
        ) {
            // ── Шапка ─────────────────────────────────────────────────────────
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(BrandSurface)
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment    = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column {
                    Text("Консоль отладки", color = BrandText, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                    Text("${entries.size} записей · обновляется каждые 500 мс", color = BrandSubtext, fontSize = 11.sp)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    // Кнопка "Скопировать"
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(BrandCard)
                            .border(1.dp, BrandBorder, RoundedCornerShape(8.dp))
                            .clickable {
                                val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                clipboard.setPrimaryClip(ClipData.newPlainText("OBD Debug Log", DebugLogger.formatAll()))
                                Toast.makeText(context, "Скопировано в буфер", Toast.LENGTH_SHORT).show()
                            }
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                    ) {
                        Text("Скопировать", color = BrandBlue, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    }
                    // Кнопка "Очистить"
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(BrandCard)
                            .border(1.dp, BrandBorder, RoundedCornerShape(8.dp))
                            .clickable {
                                DebugLogger.clear()
                                entries = emptyList()
                            }
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                    ) {
                        Text("Очистить", color = BrandYellow, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    }
                    // Кнопка "Закрыть"
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(BrandRed.copy(alpha = 0.15f))
                            .border(1.dp, BrandRed.copy(alpha = 0.3f), RoundedCornerShape(8.dp))
                            .clickable { onDismiss() }
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                    ) {
                        Text("✕", color = BrandRed, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }

            // ── Список записей ────────────────────────────────────────────────
            if (entries.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("Логов пока нет.\nНачните диагностику.", color = BrandSubtext, fontSize = 13.sp, textAlign = TextAlign.Center)
                }
            } else {
                val fmt = remember { SimpleDateFormat("HH:mm:ss.SSS", Locale.US) }
                LazyColumn(
                    state           = listState,
                    contentPadding  = PaddingValues(vertical = 6.dp),
                    modifier        = Modifier.fillMaxSize(),
                ) {
                    items(entries, key = { it.timeMs.toString() + it.message.take(20) }) { entry ->
                        val (levelColor, levelBg) = when (entry.level) {
                            LogLevel.DEBUG -> BrandSubtext to Color.Transparent
                            LogLevel.INFO  -> BrandBlue   to BrandBlue.copy(alpha = 0.06f)
                            LogLevel.WARN  -> BrandYellow to BrandYellow.copy(alpha = 0.06f)
                            LogLevel.ERROR -> BrandRed    to BrandRed.copy(alpha = 0.08f)
                        }
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(levelBg)
                                .padding(horizontal = 12.dp, vertical = 3.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            // Время
                            Text(
                                fmt.format(Date(entry.timeMs)),
                                color    = BrandSubtext.copy(alpha = 0.6f),
                                fontSize = 10.sp,
                                fontFamily = FontFamily.Monospace,
                                modifier = Modifier.width(80.dp),
                            )
                            // Уровень
                            Text(
                                entry.level.letter,
                                color      = levelColor,
                                fontSize   = 10.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = FontFamily.Monospace,
                                modifier   = Modifier.width(12.dp),
                            )
                            // TAG + сообщение
                            Text(
                                "${entry.tag}: ${entry.message}",
                                color      = if (entry.level == LogLevel.DEBUG) BrandSubtext else BrandText,
                                fontSize   = 11.sp,
                                fontFamily = FontFamily.Monospace,
                                lineHeight = 15.sp,
                                modifier   = Modifier.weight(1f),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PageDots(pagerState: PagerState, modifier: Modifier = Modifier) {
    val labels = listOf("CONNECT", "ОШИБКИ", "ДАТЧИКИ")
    Row(
        modifier = modifier.background(BrandBg.copy(alpha = 0.9f), RoundedCornerShape(20.dp)).padding(horizontal = 16.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        labels.forEachIndexed { index, label ->
            val active = pagerState.currentPage == index
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Box(Modifier.size(6.dp).background(if (active) BrandBlue else BrandBorder, CircleShape))
                Text(label, color = if (active) BrandBlue else BrandBorder, fontSize = 9.sp,
                    fontWeight = if (active) FontWeight.Bold else FontWeight.Normal, letterSpacing = 0.8.sp)
            }
        }
    }
}

@Composable
private fun EmptyHint(icon: String, title: String, subtitle: String) {
    Box(Modifier.fillMaxSize(), Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(40.dp)) {
            Text(icon, fontSize = 40.sp)
            Spacer(Modifier.height(12.dp))
            Text(title, color = BrandText, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
            Spacer(Modifier.height(6.dp))
            Text(subtitle, color = BrandSubtext, fontSize = 13.sp, textAlign = TextAlign.Center, lineHeight = 18.sp)
        }
    }
}

@Composable
private fun StatusCard(status: String, isConnected: Boolean, isLoading: Boolean) {
    val pulse = rememberInfiniteTransition(label = "sc")
    val dotAlpha by pulse.animateFloat(0.4f, 1f, infiniteRepeatable(tween(900), RepeatMode.Reverse), "dot")
    val dotColor = when { isLoading -> BrandYellow; isConnected -> BrandGreen; else -> BrandRed }
    Box(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(BrandCard)
            .border(1.dp, if (isConnected) BrandGreen.copy(0.3f) else BrandBorder, RoundedCornerShape(14.dp)).padding(16.dp),
    ) {
        Column {
            Text("СТАТУС", color = BrandSubtext, fontSize = 9.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp)
            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (isLoading) CircularProgressIndicator(color = BrandYellow, modifier = Modifier.size(10.dp), strokeWidth = 1.5.dp)
                else Box(Modifier.size(8.dp).alpha(dotAlpha).background(dotColor, CircleShape))
                Spacer(Modifier.width(8.dp))
                Text(status, color = if (isConnected) BrandGreen else BrandRed, fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold, lineHeight = 17.sp, modifier = Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun WhoopButton(
    text: String, label: String = "", onClick: () -> Unit,
    modifier: Modifier = Modifier, enabled: Boolean = true, isLoading: Boolean = false,
) {
    val a by animateFloatAsState(if (enabled) 1f else 0.45f, label = "btn")
    Row(
        modifier = modifier.height(52.dp).alpha(a).clip(RoundedCornerShape(14.dp))
            .background(Brush.horizontalGradient(listOf(BrandBlue, BrandBlueDark)))
            .clickable(enabled = enabled && !isLoading) { onClick() }.padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
    ) {
        if (isLoading) {
            CircularProgressIndicator(color = Color.White, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
            Spacer(Modifier.width(10.dp))
        } else if (label.isNotEmpty()) {
            Box(Modifier.clip(RoundedCornerShape(6.dp)).background(Color.White.copy(alpha = 0.18f)).padding(horizontal = 5.dp, vertical = 2.dp)) {
                Text(label, color = Color.White, fontSize = 9.sp, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.width(10.dp))
        }
        Text(text, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun ClearButton(enabled: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val a by animateFloatAsState(if (enabled) 1f else 0.45f, label = "clr")
    Row(
        modifier = modifier.height(52.dp).alpha(a).clip(RoundedCornerShape(14.dp))
            .background(BrandRed.copy(alpha = 0.15f)).border(1.dp, BrandRed.copy(alpha = 0.4f), RoundedCornerShape(14.dp))
            .clickable(enabled = enabled) { onClick() }.padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
    ) {
        Text("✕", color = BrandRed, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.width(8.dp))
        Text("Стереть ошибки", color = BrandRed, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
    }
}

// ─────────────────────────── DTC SECTION HEADER ──────────────────────────────

/**
 * Компактная карточка статуса главного ЭБУ (Двигатель) в разделе «БЛОКИ УПРАВЛЕНИЯ».
 * Детальные DTC уже выведены выше в разделах ПОСТОЯННЫЕ / ОЖИДАЮЩИЕ.
 */
@Composable
private fun MainEcuBlockCard(mainResult: DtcResult, pendingResult: DtcResult) {
    val mainCount    = (mainResult    as? DtcResult.DtcList)?.codes?.size ?: 0
    val pendingCount = (pendingResult as? DtcResult.DtcList)?.codes?.size ?: 0
    val hasErrors    = mainCount > 0 || pendingCount > 0
    val borderColor  = if (hasErrors) BrandOrange else BrandGreen
    val statusText   = when {
        mainCount > 0 && pendingCount > 0 -> "$mainCount пост. / $pendingCount ожид."
        mainCount > 0                     -> "$mainCount постоянных"
        pendingCount > 0                  -> "$pendingCount ожидающих"
        else                              -> "Ошибок нет"
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(BrandCard)
            .border(1.dp, borderColor.copy(0.2f), RoundedCornerShape(14.dp))
            .padding(14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column {
            Text("Двигатель / ЭБУ", color = BrandText, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Text("Подробности — в разделах выше", color = BrandSubtext, fontSize = 11.sp)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(statusText, color = borderColor, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            Text("7E0", color = BrandSubtext, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
        }
    }
}

/**
 * Компактная сводная карточка с результатами опроса всех ЭБУ.
 * Показывается в начале экрана ошибок после успешного сканирования —
 * позволяет одним взглядом оценить, какие блоки ответили и есть ли в них ошибки.
 */
@Composable
private fun EcuBlocksStatusCard(
    mainResult: DtcResult,
    otherEcus: List<EcuDtcResult>,
) {
    data class BlockStatus(val name: String, val color: Color, val status: String, val address: String)

    val blocks: List<BlockStatus> = buildList {
        // Главный блок — двигатель / ЭБУ (всегда присутствует после сканирования)
        val (mc, mt) = when (val r = mainResult) {
            is DtcResult.NoDtcs      -> BrandGreen   to "Ошибок нет"
            is DtcResult.DtcList     -> if (r.codes.isEmpty()) BrandGreen to "Ошибок нет"
                                        else BrandOrange to "${r.codes.size} ошибок"
            is DtcResult.Error       -> BrandSubtext  to "Нет ответа"
            is DtcResult.RawResponse -> BrandYellow   to "Нет данных"
        }
        add(BlockStatus("Двигатель / ЭБУ", mc, mt, "7E0"))
        // Остальные блоки — только если был включён опрос других ЭБУ
        otherEcus.forEach { ecu ->
            val (ec, et) = when (val r = ecu.result) {
                is DtcResult.NoDtcs      -> BrandGreen   to "Ошибок нет"
                is DtcResult.DtcList     -> if (r.codes.isEmpty()) BrandGreen to "Ошибок нет"
                                            else BrandOrange to "${r.codes.size} ошибок"
                is DtcResult.Error       -> BrandSubtext  to "Нет ответа"
                is DtcResult.RawResponse -> BrandYellow   to "Нет данных"
            }
            add(BlockStatus(ecu.name, ec, et, ecu.address))
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(BrandCard)
            .border(1.dp, BrandBorder, RoundedCornerShape(14.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            "ОПРОШЕННЫЕ БЛОКИ",
            color = BrandSubtext, fontSize = 10.sp,
            fontWeight = FontWeight.SemiBold, letterSpacing = 1.2.sp,
        )
        blocks.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { block ->
                    Row(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(8.dp))
                            .background(block.color.copy(alpha = 0.10f))
                            .padding(horizontal = 10.dp, vertical = 7.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(block.name, color = BrandText, fontSize = 11.sp, fontWeight = FontWeight.Medium, maxLines = 1)
                            Text(block.address, color = BrandSubtext, fontSize = 9.sp, fontFamily = FontFamily.Monospace)
                        }
                        Spacer(Modifier.width(6.dp))
                        Text(block.status, color = block.color, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    }
                }
                // Заполнитель, если строка нечётная (последний элемент одиночный)
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun DtcSectionHeader(label: String, count: Int?, color: Color, hint: String = "") {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(3.dp, 14.dp).background(color, RoundedCornerShape(2.dp)))
            Text(label, color = color, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp)
            if (count != null) {
                Box(
                    Modifier.clip(RoundedCornerShape(10.dp)).background(color.copy(alpha = 0.15f)).padding(horizontal = 6.dp, vertical = 1.dp)
                ) { Text("$count", color = color, fontSize = 10.sp, fontWeight = FontWeight.Bold) }
            }
        }
        if (hint.isNotBlank()) Text(hint, color = BrandSubtext, fontSize = 11.sp, lineHeight = 14.sp)
    }
}

// ─────────────────────────── FREEZE FRAME CARD ───────────────────────────────

@Composable
private fun FreezeFrameCard(ff: FreezeFrameData) {
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
            .background(BrandSurface).border(1.dp, BrandBlue.copy(0.3f), RoundedCornerShape(14.dp)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.size(3.dp, 14.dp).background(BrandBlue, RoundedCornerShape(2.dp)))
            Text("СНИМОК ПАРАМЕТРОВ ПРИ ОШИБКЕ", color = BrandBlue, fontSize = 11.sp,
                fontWeight = FontWeight.Bold, letterSpacing = 1.1.sp)
        }
        Text("Состояние датчиков в момент появления первой ошибки", color = BrandSubtext, fontSize = 11.sp)
        val cols = buildList {
            ff.dtcCode?.let      { add("DTC снимка" to it) }
            ff.rpm?.let          { add("Обороты" to "$it об/мин") }
            ff.speed?.let        { add("Скорость" to "$it км/ч") }
            ff.coolantTemp?.let  { add("Охлаждающая ж-сть" to "$it °C") }
            ff.engineLoad?.let   { add("Нагрузка" to "${it.toInt()} %") }
            ff.throttle?.let     { add("Дроссель" to "${it.toInt()} %") }
            ff.shortFuelTrim?.let{ add("Коррекция (краткоср.)" to "${String.format("%.1f", it)} %") }
            ff.longFuelTrim?.let { add("Коррекция (долгоср.)" to "${String.format("%.1f", it)} %") }
            ff.map?.let          { add("Давление впуска" to "$it кПа") }
            ff.iat?.let          { add("Темп. воздуха" to "$it °C") }
            ff.voltage?.let      { add("Напряжение борт." to "${String.format("%.1f", it)} В") }
            ff.fuelStatus?.let   { add("Топливоподача" to it) }
        }
        cols.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { (label, value) ->
                    Column(Modifier.weight(1f).clip(RoundedCornerShape(8.dp))
                        .background(BrandCard).padding(8.dp)) {
                        Text(label, color = BrandSubtext, fontSize = 10.sp)
                        Text(value, color = BrandText, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

// ─────────────────────────── OTHER ECU CARD ──────────────────────────────────

@Composable
private fun OtherEcuCard(
    ecu: EcuDtcResult,
    carProfile: CarProfile,
    vehicleInfo: VehicleInfo?,
    onDtcClick: (String) -> Unit,
) {
    val confirmedCount = (ecu.result as? DtcResult.DtcList)?.codes?.size ?: 0
    val pendingCount   = (ecu.pendingResult as? DtcResult.DtcList)?.codes?.size ?: 0
    val permanentCount = (ecu.permanentResult as? DtcResult.DtcList)?.codes?.size ?: 0
    val totalCount     = confirmedCount + pendingCount + permanentCount

    val (headerColor, icon) = when {
        ecu.result is DtcResult.Error -> BrandSubtext to "—"
        totalCount > 0                -> BrandOrange to "⚠"
        ecu.result is DtcResult.NoDtcs || (ecu.result is DtcResult.DtcList && confirmedCount == 0) -> BrandGreen to "✅"
        else                          -> BrandSubtext to "?"
    }
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
            .background(BrandCard).border(1.dp, headerColor.copy(0.2f), RoundedCornerShape(14.dp)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Text(ecu.name, color = BrandText, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(icon, fontSize = 12.sp)
                Text(ecu.address, color = BrandSubtext, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
            }
        }
        if (ecu.result is DtcResult.Error) {
            Text((ecu.result as DtcResult.Error).message, color = BrandSubtext, fontSize = 12.sp)
        } else if (totalCount == 0) {
            Text("Ошибок нет", color = BrandGreen, fontSize = 12.sp)
        } else {
            (ecu.result as? DtcResult.DtcList)?.codes?.takeIf { it.isNotEmpty() }?.let { codes ->
                Text("Постоянные", color = BrandRed, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                codes.forEach { code ->
                    val info = DtcLookup.dtcInfo(code, carProfile, vehicleInfo?.detectedMake)
                    DtcErrorCard(code = code, info = info,
                        url = DtcLookup.buildUremontUrl(carProfile, vehicleInfo, code, info),
                        onOpenUrl = onDtcClick, isPending = false)
                }
            }
            (ecu.pendingResult as? DtcResult.DtcList)?.codes?.takeIf { it.isNotEmpty() }?.let { codes ->
                Text("Ожидающие", color = BrandYellow, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                codes.forEach { code ->
                    val info = DtcLookup.dtcInfo(code, carProfile, vehicleInfo?.detectedMake)
                    DtcErrorCard(code = code, info = info,
                        url = DtcLookup.buildUremontUrl(carProfile, vehicleInfo, code, info),
                        onOpenUrl = onDtcClick, isPending = true)
                }
            }
            (ecu.permanentResult as? DtcResult.DtcList)?.codes?.takeIf { it.isNotEmpty() }?.let { codes ->
                Text("Permanent", color = BrandOrange, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                codes.forEach { code ->
                    val info = DtcLookup.dtcInfo(code, carProfile, vehicleInfo?.detectedMake)
                    DtcErrorCard(code = code, info = info,
                        url = DtcLookup.buildUremontUrl(carProfile, vehicleInfo, code, info),
                        onOpenUrl = onDtcClick, isPending = false)
                }
            }
        }
    }
}

// ─────────────────────────── DTC ERROR CARD ──────────────────────────────────

@Composable
private fun DtcErrorCard(code: String, info: DtcInfo, url: String, onOpenUrl: (String) -> Unit, isPending: Boolean = false) {
    val sevColor = when (info.severity) { 3 -> BrandRed; 2 -> BrandOrange; else -> BrandYellow }
    val sevLabel = when (info.severity) { 3 -> "КРИТИЧНО"; 2 -> "ВНИМАНИЕ"; else -> "ИНФО" }
    val context  = LocalContext.current
    val isOnline = remember { context.isNetworkAvailable() }
    var showQrDialog by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(BrandCard)
            .border(1.dp, sevColor.copy(alpha = 0.25f), RoundedCornerShape(16.dp)).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(code, color = BrandYellow, fontSize = 20.sp, fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace)
                if (isPending) {
                    Box(Modifier.clip(RoundedCornerShape(6.dp)).background(BrandYellow.copy(0.12f))
                        .border(1.dp, BrandYellow.copy(0.35f), RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 2.dp)) {
                        Text("ОЖИДАЮЩИЙ", color = BrandYellow, fontSize = 9.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp)
                    }
                }
            }
            Box(Modifier.clip(RoundedCornerShape(6.dp)).background(sevColor.copy(alpha = 0.15f))
                .border(1.dp, sevColor.copy(alpha = 0.4f), RoundedCornerShape(6.dp)).padding(horizontal = 8.dp, vertical = 3.dp)) {
                Text(sevLabel, color = sevColor, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.8.sp)
            }
        }
        Text(info.title, color = BrandText, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = 19.sp)
        if (info.causes.isNotBlank()) Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Причины:", color = BrandSubtext, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
            Text(info.causes, color = BrandSubtext, fontSize = 12.sp, lineHeight = 17.sp)
        }
        if (info.repair.isNotBlank()) Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Действие:", color = BrandBlue, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
            Text(info.repair, color = BrandText, fontSize = 12.sp, lineHeight = 17.sp)
        }

        Row(
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
                .background(BrandBlue.copy(alpha = 0.12f))
                .border(1.dp, BrandBlue.copy(alpha = 0.35f), RoundedCornerShape(10.dp))
                .clickable { if (isOnline) onOpenUrl(url) else showQrDialog = true }
                .padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(if (isOnline) "🔍" else "📵", fontSize = 14.sp)
            Spacer(Modifier.width(8.dp))
            Text(
                text = if (isOnline) "Узнать стоимость ремонта" else "Узнать стоимость (QR-код)",
                color = BrandBlue, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
            )
        }
    }

    if (showQrDialog) {
        QrCodeDialog(url = url, onDismiss = { showQrDialog = false })
    }
}

// ─────────────────────────── QR CODE DIALOG ──────────────────────────────────

@Composable
private fun QrCodeDialog(url: String, onDismiss: () -> Unit) {
    androidx.compose.ui.window.Dialog(
        onDismissRequest = onDismiss,
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            modifier = Modifier.fillMaxSize()
                .background(Color.Black.copy(alpha = 0.75f))
                .clickable(indication = null, interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }) { onDismiss() },
            contentAlignment = Alignment.Center,
        ) {
            Column(
                modifier = Modifier
                    .padding(horizontal = 48.dp)
                    .clip(RoundedCornerShape(24.dp))
                    .background(BrandCard)
                    .border(1.dp, BrandBorder, RoundedCornerShape(24.dp))
                    .clickable(indication = null, interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }) {}
                    .padding(28.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Text(
                    "Нет интернета? Не проблема!",
                    color = BrandText, fontSize = 16.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                )
                Text(
                    "Отсканируйте QR-код, чтобы узнать справедливую стоимость ремонта через UREMONT",
                    color = BrandSubtext, fontSize = 13.sp, textAlign = TextAlign.Center, lineHeight = 18.sp,
                )
                QrCodeImage(content = url, sizeDp = 220)
                Box(
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                        .background(BrandSurface).border(1.dp, BrandBorder, RoundedCornerShape(12.dp))
                        .clickable { onDismiss() }.padding(vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("Закрыть", color = BrandSubtext, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun QrCodeImage(content: String, sizeDp: Int) {
    val bitmap = remember(content) {
        try {
            val hints = mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 1)
            val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, sizeDp, sizeDp, hints)
            val pixels = IntArray(sizeDp * sizeDp) { i ->
                if (matrix[i % sizeDp, i / sizeDp]) android.graphics.Color.BLACK else android.graphics.Color.WHITE
            }
            Bitmap.createBitmap(sizeDp, sizeDp, Bitmap.Config.RGB_565).also { it.setPixels(pixels, 0, sizeDp, 0, 0, sizeDp, sizeDp) }
        } catch (_: Exception) { null }
    }
    bitmap?.let {
        Image(
            bitmap = it.asImageBitmap(),
            contentDescription = "QR код для UREMONT",
            modifier = Modifier.size(sizeDp.dp).clip(RoundedCornerShape(12.dp)),
        )
    }
}

private fun Context.isNetworkAvailable(): Boolean {
    val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        val caps = cm.getNetworkCapabilities(cm.activeNetwork ?: return false) ?: return false
        caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    } else {
        @Suppress("DEPRECATION")
        cm.activeNetworkInfo?.isConnected == true
    }
}

// ─────────────────────────── SENSOR CARD ─────────────────────────────────────

@Composable
private fun SensorCard(pid: ObdPid, reading: SensorReading?) {
    val statusColor = when (reading?.status) {
        SensorStatus.OK          -> BrandGreen
        SensorStatus.WARNING     -> BrandYellow
        SensorStatus.UNSUPPORTED -> BrandBorder
        SensorStatus.ERROR       -> BrandRed
        else                     -> BrandBorder
    }
    val animValue by animateFloatAsState(reading?.value ?: 0f, tween(400), label = "sv_${pid.command}")
    val displayValue = when {
        reading?.status == SensorStatus.UNSUPPORTED -> "N/A"
        reading?.value == null -> "—"
        else -> if (animValue == animValue.toLong().toFloat()) animValue.toLong().toString() else "%.1f".format(animValue)
    }
    val maxForBar = pid.maxWarning ?: when (pid.shortCode) {
        "RPM" -> 8000f; "SPD" -> 240f; "ECT" -> 130f; "VLT" -> 16f
        "IGN" -> 60f; "MAF" -> 50f; "RUN" -> 3600f; else -> 100f
    }
    val barProgress = ((reading?.value ?: 0f) / maxForBar).coerceIn(0f, 1f)

    Box(Modifier.clip(RoundedCornerShape(14.dp)).background(BrandCard).border(1.dp, BrandBorder, RoundedCornerShape(14.dp)).padding(12.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                Box(Modifier.clip(RoundedCornerShape(6.dp)).background(BrandBlue.copy(alpha = 0.15f)).padding(horizontal = 6.dp, vertical = 2.dp)) {
                    Text(pid.shortCode, color = BrandBlue, fontSize = 9.sp, fontWeight = FontWeight.Bold)
                }
                Box(Modifier.size(7.dp).background(statusColor, CircleShape))
            }
            Text(displayValue,
                color = if (reading?.status == SensorStatus.UNSUPPORTED) BrandSubtext else BrandText,
                fontSize = 24.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
            Text(pid.unit, color = BrandSubtext, fontSize = 10.sp)
            Text(pid.name, color = BrandSubtext.copy(alpha = 0.65f), fontSize = 9.sp, lineHeight = 11.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (reading?.value != null && reading.status != SensorStatus.UNSUPPORTED) {
                LinearProgressIndicator(
                    progress = { barProgress }, modifier = Modifier.fillMaxWidth().height(3.dp).clip(CircleShape),
                    color = statusColor, trackColor = BrandBorder,
                )
            }
        }
    }
}

// ─────────────────────────── DEVICE SHEET ────────────────────────────────────

@SuppressLint("MissingPermission")
@Composable
private fun DeviceSheetContent(btAdapter: BluetoothAdapter?, onSelect: (BluetoothDevice) -> Unit) {
    val context = LocalContext.current
    val discoveredDevices = remember { mutableStateListOf<BluetoothDevice>() }
    var isScanning by remember { mutableStateOf(false) }
    val pairedDevices = remember {
        try { btAdapter?.bondedDevices?.toList() ?: emptyList() } catch (_: Exception) { emptyList() }
    }

    DisposableEffect(Unit) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                when (intent.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val dev = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                        else @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        if (dev != null && !discoveredDevices.any { it.address == dev.address } && !pairedDevices.any { it.address == dev.address })
                            discoveredDevices.add(dev)
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> isScanning = false
                }
            }
        }
        val filter = IntentFilter().apply { addAction(BluetoothDevice.ACTION_FOUND); addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED) }
        // На Android 13+ (API 33) обязателен флаг экспорта для динамических BroadcastReceiver.
        // ACTION_FOUND — системный broadcast → RECEIVER_EXPORTED (принимаем от системы).
        ContextCompat.registerReceiver(context, receiver, filter, ContextCompat.RECEIVER_EXPORTED)
        try { btAdapter?.startDiscovery(); isScanning = true } catch (_: Exception) {}
        onDispose { context.unregisterReceiver(receiver); try { btAdapter?.cancelDiscovery() } catch (_: Exception) {} }
    }

    Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.7f)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp), Arrangement.SpaceBetween, Alignment.CenterVertically) {
            Text("Выбор адаптера", color = BrandText, fontSize = 17.sp, fontWeight = FontWeight.Bold)
            Row(
                modifier = Modifier.clip(RoundedCornerShape(10.dp))
                    .background(if (isScanning) BrandBlue.copy(alpha = 0.15f) else BrandCard)
                    .border(1.dp, if (isScanning) BrandBlue.copy(0.4f) else BrandBorder, RoundedCornerShape(10.dp))
                    .clickable {
                        if (isScanning) { btAdapter?.cancelDiscovery(); isScanning = false }
                        else { discoveredDevices.clear(); btAdapter?.startDiscovery(); isScanning = true }
                    }.padding(horizontal = 12.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                if (isScanning) CircularProgressIndicator(color = BrandBlue, modifier = Modifier.size(12.dp), strokeWidth = 1.5.dp)
                Text(if (isScanning) "Стоп" else "Найти", color = if (isScanning) BrandBlue else BrandSubtext, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        LazyColumn(contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (pairedDevices.isNotEmpty()) {
                item { Text("СОПРЯЖЁННЫЕ", color = BrandSubtext, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp); Spacer(Modifier.height(6.dp)) }
                items(pairedDevices) { dev -> DeviceRow(device = dev, badge = "🔗", onSelect = onSelect) }
                item { Spacer(Modifier.height(12.dp)) }
            }
            item { Text("ПОБЛИЗОСТИ", color = BrandSubtext, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp); Spacer(Modifier.height(6.dp)) }
            if (discoveredDevices.isEmpty()) {
                item {
                    Box(Modifier.fillMaxWidth().padding(vertical = 16.dp), Alignment.Center) {
                        Text(if (isScanning) "Ищем устройства…" else "Устройства не найдены", color = BrandSubtext, fontSize = 13.sp)
                    }
                }
            } else {
                items(discoveredDevices) { dev -> DeviceRow(device = dev, badge = "BT", onSelect = onSelect) }
            }
        }
    }
}

@SuppressLint("MissingPermission")
@Composable
private fun DeviceRow(device: BluetoothDevice, badge: String, onSelect: (BluetoothDevice) -> Unit) {
    val name = try { device.name ?: device.address } catch (_: SecurityException) { device.address }
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(BrandCard)
            .border(1.dp, BrandBorder, RoundedCornerShape(12.dp)).clickable { onSelect(device) }
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(36.dp).background(BrandBlue.copy(alpha = 0.15f), RoundedCornerShape(10.dp)), Alignment.Center) {
            Text(badge, color = BrandBlue, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        }
        Column(Modifier.weight(1f)) {
            Text(name, color = BrandText, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            Text(device.address, color = BrandSubtext, fontSize = 11.sp)
        }
        Text("→", color = BrandBorder, fontSize = 16.sp, fontWeight = FontWeight.Bold)
    }
}

