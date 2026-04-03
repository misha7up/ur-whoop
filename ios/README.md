# UREMONT WHOOP — iOS

iOS-приложение для OBD2-диагностики через ELM327-адаптер по **Wi-Fi TCP**.  
Стек: **Swift / SwiftUI**. На iOS **Bluetooth Classic (SPP) не поддерживается** — используется только подключение по Wi-Fi к адаптеру.

> Для общего контекста проекта (оба платформы) смотри [`../CONTEXT.md`](../CONTEXT.md).

---

## Стек

| Компонент | Версия / заметки |
|-----------|------------------|
| Swift | 5.9+ |
| SwiftUI | iOS 16+ (deployment target) |
| Combine | `ObservableObject` для `ObdConnectionManager` и `AppViewModel` |
| Network.framework | `NWConnection`, TCP с `tcpNoDelay` |
| CoreImage | QR-коды (`CIQRCodeGenerator`) |
| UIGraphicsPDFRenderer | PDF A4 (595×842pt) |
| QuickLook | Предпросмотр PDF-отчёта |
| XcodeGen | `.xcodeproj` из `project.yml`, не хранится в git |
| Bundle ID | `com.uremont.UremontWhoop` |
| Marketing Version | 1.7.0-stable |

---

## Структура проекта

```
ios/
├── project.yml                        ← XcodeGen конфигурация
├── UremontWhoop.xcodeproj             ← генерируется через xcodegen, НЕ в git
├── UremontWhoop/
│   ├── UremontWhoopApp.swift          ← @main: создаёт ObdConnectionManager, тёмная тема
│   ├── Info.plist                     ← Разрешения, launch screen, capabilities
│   ├── Assets.xcassets/               ← SVG-логотип UREMONT (UremontLogo), AppIcon
│   ├── Models/
│   │   ├── BrandConfig.swift          ← URL карты, лимиты, Wi‑Fi/live тайминги (зеркало AppConfig)
│   │   └── SessionRecord.swift        ← SessionRecord + SessionRepository (канон. JSON + legacy)
│   ├── ViewModels/
│   │   └── AppViewModel.swift         ← @MainActor ObservableObject — вся бизнес-логика
│   ├── OBD/
│   │   ├── ObdConnectionManager.swift ← Wi-Fi TCP (NWConnection), ELM327, OBD2 протокол
│   │   ├── BrandEcuHints.swift        ← 7 универс. + марочные CAN-ID, `classify` (21 группа, Subaru + др.)
│   │   ├── ClusterOdometerProbes.swift ← UDS 22 на щиток (одометр, опытно), паритет с Android
│   │   ├── ObdStandardLabels.swift    ← подписи PID 1C / 51
│   │   ├── ObdVehicleInfoParse.swift  ← разбор Mode 09/01 для VehicleInfo
│   │   ├── VinWmiTable.swift          ← ~2100 WMI → подпись производителя (Wikibooks)
│   │   └── DebugLogger.swift          ← Кольцевой буфер логов (800 записей, os_log)
│   ├── PDF/
│   │   └── PdfReportGenerator.swift   ← Отчёт A4 через UIGraphicsPDFRenderer
│   ├── DTC/
│   │   └── DtcDatabase.swift          ← enum DtcLookup: описания DTC, ALL_MAKES, URL UREMONT
│   └── Views/
│       ├── Theme.swift                ← enum Brand — цвета и типографика
│       ├── SplashScreen.swift         ← Стартовый экран с логотипом и прогрессом (~2.7 сек)
│       ├── MainTabView.swift          ← AppRoot + OBDScreen (свайп-пейджер 3 страницы)
│       ├── ConnectionPage.swift       ← Подключение, профиль, VehicleInfo, readiness
│       ├── ErrorsPage.swift           ← DTC, freeze frame, другие ЭБУ, кнопка PDF
│       ├── LiveDashboardPage.swift    ← Live PID в LazyVGrid (SensorCard)
│       ├── Components/
│       │   ├── SharedComponents.swift ← WhoopButton, ClearButton, StatusCard, PageHeader,
│       │   │                             ProfileChip, PageDots, AppSettings, isTablet()
│       │   └── DtcErrorCard.swift     ← Карточка ошибки + NetworkChecker + QR при офлайне
│       └── Sheets/
│           ├── WifiSheet.swift        ← IP:порт, пресеты адаптеров, инструкция подключения
│           ├── SettingsSheet.swift     ← Настройки (toggles) + DebugConsoleView
│           ├── HistorySheet.swift      ← История диагностик (SessionCard)
│           └── ManualCarPickerSheet.swift ← Ручной выбор марки/модели/года (34 марки)
└── UremontWhoopTests/
    ├── ObdParserTests.swift           ← 33 теста (парсеры OBD + UDS 0x19)
    └── DtcDatabaseTests.swift         ← 13 тестов DTC-базы и URL
```

---

## Архитектура (MVVM)

### Граф зависимостей

```
UremontWhoopApp (@main)
  └── создаёт ObdConnectionManager (ObservableObject, @StateObject)
        └── передаёт как .environmentObject в AppRoot

AppRoot (View)
  └── SplashScreen → OBDScreen

OBDScreen (View)
  ├── создаёт AppViewModel(@StateObject) ← получает ObdConnectionManager через init
  ├── UI-стейт: showSettings, showHistory, showWifiSheet, currentPage...
  └── Передаёт @Published свойства vm в дочерние View как параметры/binding
        ├── ConnectionPage (статус, профиль, VehicleInfo, readiness)
        ├── ErrorsPage (errorsState, DTC-карточки, PDF)
        ├── LiveDashboardPage (sensorReadings, isMonitoring)
        └── Sheets (Settings, History, Wifi, ManualCarPicker)
```

### AppViewModel — ответственности

| Группа | Свойства / методы |
|--------|------------------|
| Подключение | `connectionStatus`, `isConnected`, `isConnecting`, `connectWifi()`, `toggleConnection()` |
| Профиль | `carProfile` (Auto/Manual), `vehicleInfo`, `readinessMonitors` |
| Диагностика | `errorsState` (Idle/Loading/Result), `readErrors()`, `clearErrors()` |
| Мониторинг | `sensorReadings`, `isMonitoring`, `pollSensors()` |
| История | `sessions`, `saveSession()`, `loadSessions()` |
| Настройки | `freezeFrameEnabled`, `otherEcusEnabled` (делегируют в AppSettings/UserDefaults) |
| PDF | `exportPdf()` → PdfReportGenerator |
| Wi-Fi | `savedWifiHost`, `savedWifiPort` |

### OBDScreen — только UI-стейт

`showSettings`, `showHistory`, `showManualPicker`, `showWifiSheet`, `showPdfAlert`, `pdfPreviewURL`, `currentPage`.

---

## Ключевые механизмы

### ObdConnectionManager

- **NWConnection** — TCP без TLS, `tcpNoDelay = true` (критично для коротких AT-команд).
- **AsyncMutex** — NSLock + CheckedContinuation: `tryLock()` для pollSensor, `withLock` для остальных.
- **ContinuationGuard** — one-shot `@unchecked Sendable` для безопасного resumption из нескольких NWConnection callbacks.
- **ReadState** — `@unchecked Sendable` обёртка `Data` буфера + `ContinuationGuard`.
- **readUntilPrompt** — чтение ответов ELM327 до символа `>` (pump-паттерн с `ContinuationGuard`).
- **drainInput** — пауза 50мс между командами (1.5-stable). Pump убран: NWConnection `receive()` нельзя отменить, «висящий» обработчик крал данные.
- **warmupIfNeeded** — при паузе >3.5 сек → `0100` (K-Line P3_Max keepalive).
- **postClearWarmup** — после Mode 04: delay 2.5с → `ATPC` → `0100`.
- **decodeVinYear** — 30-летний цикл VIN разрешается через 7-ю позицию (цифра → 2010-2039, буква → 1980-2009).

### DtcDatabase (enum DtcLookup)

- **Namespace** — все функции как `static` в `enum DtcLookup` (нет инстанса).
- **dtcInfo(code, profile, detectedMake?)** — OEM (BMW/VAG/Mercedes) → Toyota/Lexus по VIN или ручной марке → универсальная таблица.
- **buildProblemDescription** — словарь `[String: String]` (~45 записей) + regex `P030[1-9]`.
- **buildUremontUrl** — `URLComponents`, хост/схема из `BrandConfig`.

### SessionRepository

- Файл: `Application Support/<bundleId>/sessions.json` (имя и лимит — `BrandConfig`).
- До 100 записей, FIFO. `NSLock`.
- Запись: `JSONEncoder` (канон: `timestamp` в мс, длинные ключи). Чтение: поэлементный разбор массива + `JSONDecoder` (legacy iOS секунды, legacy Android короткие ключи).
- `save(record:)`, `loadAll()`, `clear()`.

### PdfReportGenerator

- Singleton (`PdfReportGenerator.shared`).
- `UIGraphicsPDFRenderer`, A4 595×842pt.
- Файл: `tmp/reports/uremont_report_<timestamp>.pdf`.
- `share(from:file:)` → `UIActivityViewController`.

### Проверка интернета

- **NetworkChecker** — singleton `NWPathMonitor` на фоновой очереди.
- Используется в `DtcErrorCard`: без интернета → QR-код вместо URL.

---

## Сборка

**Требования:** macOS 13+ (Ventura), Xcode 15+, iOS 16.0 deployment target, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

### Быстрый старт

```bash
# 1. Установить XcodeGen (один раз)
brew install xcodegen

# 2. Сгенерировать .xcodeproj
cd ios/
xcodegen generate

# 3. Открыть в Xcode
open UremontWhoop.xcodeproj
```

4. В Xcode: **Signing & Capabilities** → выберите свой Team (Apple ID → Personal Team).
5. Выберите устройство (iPhone или симулятор) → **Cmd + R**.

> **Важно:** `.xcodeproj` генерируется из `project.yml` и **не хранится в git**. При добавлении файлов/таргетов — обновите `project.yml` и пересоберите: `xcodegen generate`.

### Unit-тесты

```bash
# Из Xcode: Product → Test (Cmd + U)
# Или CLI:
xcodegen generate
xcodebuild test -project UremontWhoop.xcodeproj -scheme UremontWhoop -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4'
```

Тесты покрывают: `decodeDtc`, `parseHexBytes`, `parseVin`, `decodeVinMake`, `decodeVinYear`, `parseUdsDtcResponse` / `parseUdsDtcRecords`, `dtcInfo` (в т.ч. суффикс FTB), `buildProblemDescription`, `buildUremontUrl`.

---

## project.yml (XcodeGen)

| Параметр | Значение |
|----------|----------|
| Deployment target | iOS 16.0 |
| Xcode minimum | 16.0 |
| Development language | ru |
| Bundle ID (app) | com.uremont.UremontWhoop |
| Bundle ID (tests) | com.uremont.UremontWhoopTests |
| Marketing Version | 1.7.0-stable |
| Build | 7 |
| GENERATE_INFOPLIST_FILE | NO (app), YES (tests) |
| Signing | Automatic, DEVELOPMENT_TEAM пустой (задаётся в Xcode) |

---

## Подключение Wi-Fi адаптера

1. Вставьте адаптер в OBD2-разъём, включите зажигание.
2. Подключите iPhone к Wi-Fi сети адаптера (типичные SSID: **OBDII**, **ELM327**, **WiFi_OBDII**).
3. В приложении: **«Выбрать адаптер»** → укажите **IP:порт** → **«Подключить»**.
4. Пресеты адаптеров: Vgate iCar Pro (192.168.0.10:35000), Kingbolen (192.168.0.10:35000), OBDLink (192.168.0.10:35000).

### Протестировано

**iPhone 16 Pro**, **iOS 26.4**. Список автомобилей (марка / модель / год, без VIN и индексов кузова): [`../README.md`](../README.md) § «Протестировано» и [`../CONTEXT.md`](../CONTEXT.md) §1.1. На iOS основной заезд — **Honda CR-V 2004** (двигатель/ЭБУ по Wi‑Fi ELM). Красный **Wi‑Fi** ELM327 (TCP, **ESP8266** как мост). Синий BT «свисток» на iOS не используется (нет Classic SPP).

---

## Разрешения (Info.plist)

| Ключ | Назначение |
|------|------------|
| `NSLocalNetworkUsageDescription` | Диалог доступа к локальной сети для TCP к ELM327 по Wi-Fi |
| `UIRequiredDeviceCapabilities` (`wifi`) | Требование Wi-Fi на устройстве (App Store фильтрация) |
| `ITSAppUsesNonExemptEncryption` (`false`) | Только встроенное шифрование — упрощение экспортной декларации |
| `UILaunchScreen` → `UIColorName: LaunchBg` | Фон стартового экрана до появления SwiftUI |
| `UIRequiresFullScreen` | true — не поддерживает split view |
| `UISupportedInterfaceOrientations` | Только портретная ориентация |

Разрешений Bluetooth **не требуется** — Classic SPP на iOS для OBD2-сценария не используется.

---

## Отличия от Android-версии

| Что есть на iOS, но нет на Android |
|-------------------------------------|
| `AppViewModel` (MVVM) — бизнес-логика вынесена из View |
| ~~`decodeVinYear`~~ — теперь на обеих платформах (Android + iOS) |

| Что синхронизировано / исправлено в 1.5-stable |
|-------------------------------------|
| DTC namespace — теперь `object DtcLookup` в `DtcDatabase.kt` (Android) |
| Словарь в `buildProblemDescription` — `Map<String, String>` (Android) |
| Безопасное URL-кодирование — `Uri.Builder` (Android) |
| Персистентные `AppSettings` — `SharedPreferences` (Android) |
| Unit-тесты — Android 60 (`ObdParserTest`), iOS 46 (`ObdParserTests` + `DtcDatabaseTests`) |
| fix `drainInput` — pump крал данные через NWConnection `receive()` |
| PDF логотип (SVG пре-рендер в bitmap) + блок «Двигатель / ЭБУ» |

| Что есть на Android, но нет на iOS |
|-------------------------------------|
| Bluetooth Classic (3 стратегии: Insecure → Secure → Reflection) |
| Выбор транспорта (BT / Wi-Fi) в TransportPicker |
| DeviceSheet (список BT-устройств) |

---

## Цветовая схема (Brand)

```
BrandBg      = #0D0D0F    BrandBlue     = #227DF5
                           BrandBlueDark = #0063E4
BrandSurface = #18181B    BrandGreen   = #34C759
BrandCard    = #242428    BrandRed     = #FF3B30
BrandBorder  = #36363C    BrandOrange  = #FF9500
BrandText    = #F0F0F5    BrandYellow  = #FCC900
BrandSubtext = #8E8E93
```

Определены в `Theme.swift` как `enum Brand` — статические `Color`.  
Комментарий в коде: «Exact match to Android».
