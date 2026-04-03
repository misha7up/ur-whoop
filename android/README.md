# UREMONT WHOOP — Android

Android-приложение для OBD2-диагностики через ELM327-адаптер по **Bluetooth** или **Wi-Fi**.  
Оптимизировано для планшета 9" на борту автомобиля; корректно работает и на обычных Android-смартфонах.

> Для общего контекста проекта (оба платформы) смотри [`../CONTEXT.md`](../CONTEXT.md).

---

## Стек

| Компонент | Версия | Заметки |
|-----------|--------|---------|
| Kotlin | 1.9.23 | НЕ 2.0 — `kotlin.plugin.compose` **не нужен** |
| Android Gradle Plugin | 8.3.2 | |
| Jetpack Compose BOM | 2024.04.00 | |
| Compose Compiler | 1.5.11 | Строго привязан к Kotlin 1.9.23 |
| Min SDK | 24 (Android 7.0) | |
| Target SDK | 34 (Android 14) | |
| Gradle | 8.7 | |
| JVM target | 17 | |
| ZXing Core | 3.5.3 | QR-коды |
| Coroutines | 1.8.1 | |
| applicationId | `com.uremont.bluetooth` | |
| versionCode / versionName | 7 / 1.7.0-stable | |

> **Важно:** Kotlin 1.9.23 + Compose Compiler 1.5.11 — жёсткая связка. Обновление Kotlin требует обновления Compose Compiler (см. [таблицу совместимости](https://developer.android.com/jetpack/androidx/releases/compose-kotlin)).

---

## Структура проекта

```
android/
├── app/
│   ├── src/main/
│   │   ├── AndroidManifest.xml        ← разрешения BT, Wi-Fi, FileProvider
│   │   ├── res/
│   │   │   ├── values/strings.xml     ← только app_name
│   │   │   ├── values/themes.xml      ← тёмная тема для splash до Compose
│   │   │   ├── values/ic_launcher_background.xml
│   │   │   ├── drawable/ic_logo.xml   ← векторный логотип UREMONT (используется в PDF)
│   │   │   ├── drawable/ic_launcher_foreground.xml
│   │   │   ├── mipmap-anydpi*/        ← adaptive icon XML
│   │   │   └── xml/file_paths.xml     ← FileProvider пути для PDF (reports/)
│   │   └── java/com/uremont/bluetooth/
│   │       ├── UremontApp.kt              ← Application singleton, держит ObdConnectionManager
│   │       ├── MainActivity.kt            ← Compose UI (пейджер, шиты, навигация)
│   │       ├── DtcDatabase.kt             ← object DtcLookup: DTC-описания, URL, problemDescription
│   │       ├── ObdConnectionManager.kt    ← Bluetooth (RFCOMM) + Wi-Fi (TCP), OBD2 протокол
│   │       ├── BrandEcuHints.kt           ← 7 универс. + марочные CAN-ID, `classify` (21 группа, Subaru + др.)
│   │       ├── ClusterOdometerProbes.kt   ← UDS 22 на щиток (одометр, опытно)
│   │       ├── ObdStandardLabels.kt       ← подписи PID 1C / 51
│   │       ├── ObdVehicleInfoParse.kt     ← разбор Mode 09/01 для VehicleInfo
│   │       ├── VinWmiTable.kt             ← ~2100 WMI → подпись производителя (Wikibooks)
│   │       ├── ObdScreenViewModel.kt      ← ViewModel OBD-экрана (паритет с iOS AppViewModel)
│   │       ├── AppConfig.kt               ← map.uremont.com, лимиты сессий, Wi‑Fi/OBD/live тайминги
│   │       ├── ErrorsState.kt           ← состояние экрана DTC
│   │       ├── SessionManager.kt        ← SessionRecord + SessionRepository (канон. JSON + legacy)
│   │       ├── PdfReportGenerator.kt      ← PDF через PdfDocument + Canvas/Paint
│   │       └── DebugLogger.kt             ← Кольцевой буфер логов (800 записей, Logcat)
│   └── src/test/java/com/uremont/bluetooth/
│       └── ObdParserTest.kt              ← 60 unit-тестов (DTC, VIN, BrandEcuHints, UDS 0x19, DtcLookup/FTB)
├── build.gradle.kts              ← зависимости, SDK, Compose
├── build.gradle.kts                   ← корневые плагины (AGP, Kotlin)
├── settings.gradle.kts                ← rootProject.name = "UremontBluetooth"
├── gradle.properties                  ← JVM heap, parallel, caching, AndroidX
├── gradle/wrapper/
├── gradlew
├── proguard-rules.pro
└── whoop-1.7.0-stable.apk              ← готовая сборка 1.7.0-stable
```

---

## Архитектура

### ViewModel и UI

Бизнес-логика и состояние OBD-экрана вынесены в **`ObdScreenViewModel`** (+ `ObdUiState`, `StateFlow`). `MainActivity.kt` / `OBDScreen` остаются композицией: шиты, разрешения, пейджер, подписка на `collectAsStateWithLifecycle`. Тексты ошибок/статусов частично в `res/values/strings.xml`.

### Граф зависимостей

```
UremontApp (Application)
  └── val obdConnectionManager = ObdConnectionManager()   ← singleton на процесс

MainActivity (ComponentActivity)
  └── onCreate: достаёт obdManager из (application as UremontApp)
        └── setContent { UremontTheme { AppRoot(obdManager) } }

AppRoot(@Composable)
  └── AnimatedContent: SplashScreen → OBDScreen

OBDScreen(@Composable)
  ├── viewModel(ObdScreenViewModel) + collectAsStateWithLifecycle
  ├── rememberSaveable: savedWifiHost/Port, pager page; локальные флаги шитов
  └── HorizontalPager(3 страницы):
        ├── ConnectionPage
        ├── ErrorsPage
        └── LiveDashboardPage
```

### DTC-функции (DtcDatabase.kt)

Вынесены из `MainActivity.kt` в `object DtcLookup` (аналог `enum DtcLookup` на iOS):
- `DtcLookup.dtcInfo(code, profile, detectedMake?)` → `DtcInfo` (Toyota/Lexus по VIN или ручной марке)
- OEM-справочники: `bmwDtcInfo`, `vagDtcInfo`, `mercedesDtcInfo` + `universalDtcInfo`
- `buildProblemDescription(code, info)` — словарь `Map<String, String>` (~45 записей) + regex для P030X
- `buildUremontUrl(profile, vehicleInfo, code, info)` — `Uri.Builder`, хост/схема из `AppConfig`

### Модальные экраны

| Экран | Механизм | Содержимое |
|-------|----------|------------|
| TransportPickerContent | `ModalBottomSheet` | Выбор: Bluetooth или Wi-Fi |
| DeviceSheetContent | `ModalBottomSheet` | Список сопряжённых BT-устройств |
| WifiSheetContent | `ModalBottomSheet` | IP:порт, пресеты, инструкция |
| ManualCarPickerSheet | `ModalBottomSheet` | 34 марки → модели → год |
| SettingsSheet | `ModalBottomSheet` | Toggles + консоль |
| HistorySheet | `ModalBottomSheet` | Список SessionCard |
| DebugConsoleDialog | `Dialog` (fullscreen) | Логи OBD-команд |
| QrCodeDialog | `Dialog` (fullscreen) | QR-код URL uremont |
| AlertDialog | `AlertDialog` | «PDF готов» → Открыть / Поделиться |

---

## ObdConnectionManager — ключевые механизмы

### Bluetooth Classic (3 стратегии подключения)

```
1. InsecureSPP: createInsecureRfcommSocketToServiceRecord(SPP_UUID)
2. SecureSPP:   createRfcommSocketToServiceRecord(SPP_UUID)
3. Reflection:  device.javaClass.getMethod("createRfcommSocket", Int::class.java).invoke(device, 1)
```

Стратегия 3 — фаллбэк для китайских адаптеров, у которых некорректная SPP UUID.

### Wi-Fi TCP

- `java.net.Socket` с `connect(addr, 10_000)`.
- `tcpNoDelay = true` — отключает Nagle (критично для 2-6 байт AT-команд).
- `soTimeout` — таймаут blocking read.
- `BufferedReader` (input) + `OutputStream` (output).

### consumeAtResponse — транспортно-осведомлённый хелпер

| Транспорт | Метод | Причина |
|-----------|-------|---------|
| Wi-Fi | `readUntilPrompt(timeout)` | Ждёт `>` — чёткий маркер конца |
| Bluetooth | `drainInput(delay)` | BT не гарантирует `>` сразу; вычитываем буфер с задержкой |

### Мьютекс I/O

- `kotlinx.coroutines.sync.Mutex` → `ioMutex`.
- `pollSensor`: `ioMutex.tryLock()` — если занят, мгновенно возвращает ERROR (не блокирует UI).
- Остальные операции: `ioMutex.withLock` — ждут освобождения.

### warmupIfNeeded / postClearWarmup

- `warmupIfNeeded()` — если прошло >3500 мс с последней команды → `0100` (K-Line P3_Max keepalive).
- `postClearWarmup()` — после Mode 04 (сброс): delay 2500мс → `ATPC` → `0100` (K-Line пересоединение).

---

## Файловая система

### SessionRepository

- `SessionManager.kt` содержит `SessionRecord` (data class) + `SessionRepository` (object).
- Файл: `context.filesDir/sessions.json` (имя и лимит — `AppConfig`).
- До **100** записей, новые первыми.
- Формат: JSON-массив (`org.json`), канонические ключи как на iOS; `loadAllDetailed` + `SessionLoadOutcome` для ошибок чтения/частичного парсинга.

### PDF

- `PdfReportGenerator.generate(context, data)` → `context.filesDir/reports/uremont_report_<timestamp>.pdf`.
- Шаринг через `FileProvider` (authority: `${packageName}.fileprovider`, path: `files-path/reports/`).
- `open(context, file)` → `ACTION_VIEW` + chooser.
- `share(context, file)` → `ACTION_SEND`.

### Логотип в PDF

- `ContextCompat.getDrawable(context, R.drawable.ic_logo)` — векторный SVG-логотип.
- Рисуется в шапке PDF отчёта.

---

## Сборка

### Android Studio

1. Откройте папку `android/` в **Android Studio** (Arctic Fox или новее).
2. Дождитесь завершения Gradle Sync.
3. **Run** → выберите устройство / эмулятор → **▶**.

### CLI

```bash
cd android/
./gradlew assembleDebug          # → app/build/outputs/apk/debug/
./gradlew assembleRelease        # → release/ (нужен signing config)
./gradlew installDebug           # установить на подключённое устройство
```

### Готовый APK

`whoop-1.7.0-stable.apk` в корне `android/` — копия **debug**-сборки после `./gradlew assembleDebug` (актуализируйте командой ниже перед раздачей).

```bash
cd android && ./gradlew assembleDebug && cp app/build/outputs/apk/debug/app-debug.apk whoop-1.7.0-stable.apk
```

---

## Подключение

### Bluetooth-адаптер (классический ELM327)

1. Вставьте адаптер в OBD2-разъём, включите зажигание.
2. Сопрягите адаптер через **Настройки → Bluetooth** (PIN: `1234` или `0000`).
3. В приложении: **«Выбрать адаптер»** → **Bluetooth** → выберите из списка.
4. Дождитесь **«Подключено»** → **«Прочитать»** на экране ошибок.

### Wi-Fi адаптер (Kingbolen, ELM327 WiFi, Vgate iCar Pro)

1. Вставьте адаптер, включите зажигание.
2. Подключите телефон к Wi-Fi сети адаптера (SSID: `OBDII` / `ELM327` / `WiFi_OBDII`).
3. В приложении: **«Выбрать адаптер»** → **Wi-Fi** → IP:порт → **«Подключить»**.

### Протестировано

Планшет **9"**, **Android 14**. Список автомобилей (марка / модель / год, без VIN и индексов кузова): [`../README.md`](../README.md) § «Протестировано» и [`../CONTEXT.md`](../CONTEXT.md) §1.1. Основной заезд — **Honda CR-V 2004** (двигатель / основной ЭБУ; K-Line). Адаптеры: синий BT «свисток» (в листингах часто **PIC18F25K80** / v1.5) и красный **Wi‑Fi** ELM (**ESP8266** + ELM327).

---

## Разрешения (AndroidManifest)

| Разрешение | Android | Назначение |
|------------|---------|-----------|
| `BLUETOOTH` | ≤ 11 | Открытие BT-сокета |
| `BLUETOOTH_ADMIN` | ≤ 11 | Управление BT-адаптером |
| `ACCESS_FINE_LOCATION` | ≤ 11 | Поиск BT-устройств (обязательно) |
| `ACCESS_COARSE_LOCATION` | ≤ 11 | Поиск BT-устройств (API < 29) |
| `BLUETOOTH_CONNECT` | ≥ 12 | Подключение к BT-устройству |
| `BLUETOOTH_SCAN` | ≥ 12 | Список сопряжённых |
| `INTERNET` | все | Wi-Fi TCP + браузер UREMONT |
| `ACCESS_NETWORK_STATE` | все | Проверка интернета (QR vs URL) |

---

## Отличия от iOS-версии

| Что есть на Android, но нет на iOS |
|-------------------------------------|
| Bluetooth Classic (3 стратегии: Insecure → Secure → Reflection) |
| TransportPicker (выбор BT / Wi-Fi) |
| DeviceSheet (список BT-устройств) |
| `consumeAtResponse` с разной логикой для BT vs Wi-Fi |
| Оптимизация под планшет 9" |

| Что отсутствует на Android (техдолг) |
|-------------------------------------|
| ViewModel — вся логика в MainActivity (~2750 строк) |

| Исправлено в 1.5-stable |
|-------------------------------------|
| ~~DTC namespace~~ → `object DtcLookup` в `DtcDatabase.kt` |
| ~~Словарь в buildProblemDescription~~ → `Map<String, String>` |
| ~~Безопасное URL-кодирование~~ → `Uri.Builder` |
| ~~Персистентные AppSettings~~ → `SharedPreferences` |
| ~~Unit-тесты~~ → `ObdParserTest` (60 тестов), см. `app/src/test/...` |

---

## Цветовая схема

```
BrandBg      = #0D0D0F    BrandBlue     = #227DF5
                           BrandBlueDark = #0063E4
BrandSurface = #18181B    BrandGreen   = #34C759
BrandCard    = #242428    BrandRed     = #FF3B30
BrandBorder  = #36363C    BrandOrange  = #FF9500
BrandText    = #F0F0F5    BrandYellow  = #FCC900
BrandSubtext = #8E8E93
```

Определены как top-level `val` в `MainActivity.kt` (например `val BrandBlue = Color(0xFF227DF5)`).  
XML-тема: `Theme.UremontBluetooth` в `themes.xml` — фон/статус-бар `#0D0D0F` (splash до Compose).
