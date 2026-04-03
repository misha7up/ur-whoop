# CONTEXT.md — UREMONT WHOOP: технический контекст проекта

> Этот файл обновляется после каждого существенного изменения продукта.  
> Служит быстрым источником контекста для AI-ассистента **и** подробным онбордингом для нового разработчика.  
> Последнее обновление: 2026-04-03 (README/CONTEXT: зеркало `blendique/ur-whoop`, актуальные тесты и архитектура Android; Subaru/Porsche/`mergeMakeHints` — см. `ECU_COVERAGE.md`)

---

## 1. Что это за проект

**UREMONT WHOOP** — мобильное приложение для OBD2-диагностики автомобиля через ELM327-адаптер.  
Два **нативных** клиента с единой функциональностью и визуальным стилем:


| Платформа   | Язык / UI                | Транспорт                           | Версия       |
| ----------- | ------------------------ | ----------------------------------- | ------------ |
| **Android** | Kotlin / Jetpack Compose | Bluetooth Classic (SPP) + Wi-Fi TCP | 1.7.0-stable |
| **iOS**     | Swift / SwiftUI          | только Wi-Fi TCP                    | 1.7.0-stable |



| Репозиторий                                                               | URL                                         |
| ------------------------------------------------------------------------- | ------------------------------------------- |
| Основной (история коммитов)                                               | `https://github.com/misha7up/uremont-whoop` |
| Снимок текущего дерева **одним коммитом**, без истории (тестовая раздача) | `https://github.com/blendique/ur-whoop`     |


**Целевая аудитория:** автовладельцы, мастера СТО, автоподборщики и все, кто хочет понять состояние авто без дорогого оборудования.

### 1.0. Продукт в экосистеме UREMONT (бизнес-контекст)

**UREMONT WHOOP** — не «отдельная утилита», а **точка входа в экосистему UREMONT**. Продуктовая логика строится так:

1. **Регистрация и вход.** Пользователю для полноценного доступа к диагностике предполагается **авторизация в системе UREMONT** (логин). Это связывает приложение с аккаунтом, историей и сервисами платформы.
2. **Ценность «за регистрацию».** После регистрации пользователь получает **функциональность уровня платного OBD-сканера** (чтение кодов, расширенный опрос блоков, отчёты, live-параметры и т.д.) **без отдельной платы за софт** — по сути, **бесплатный для пользователя** диагностический слой в обмен на вовлечение в экосистему.
3. **Рост и узнаваемость.** Приложение увеличивает **число регистраций** и **узнаваемость бренда UREMONT** среди автовладельцев; каждый установивший WHOOP — потенциальный постоянный пользователь платформы.
4. **Лояльность и предложения.** Авторизованный пользователь попадает в **программы лояльности** и воронки **акций и сервисных предложений** UREMONT (ремонт, сервисы, партнёры) — диагностика становится естественным первым шагом к заказу услуг.
5. **Монетизация и сервис.** Кнопка **«Узнать стоимость ремонта»** ведёт на `**map.uremont.com`** — агрегатор автосервисов и мост между симптомом в приложении и записью в СТО.

Итого: **мобильный OBD-клиент как «магнит» на регистрацию** + **бесплатный по смыслу для юзера уровень диагностики** + **удержание через лояльность и офферы** + **переход в карту сервисов**. Техническая реализация авторизации в этом репозитории может наращиваться по мере подключения к бэкенду UREMONT; в документации зафиксирована **целевая продуктовая модель**.

### 1.1. Протестировано (железо, ОС, автомобиль)


| Площадка    | Окружение                       |
| ----------- | ------------------------------- |
| **Android** | Планшет **9"**, **Android 14**  |
| **iOS**     | **iPhone 16 Pro**, **iOS 26.4** |


**Автомобили для ориентира регрессии** — в документации указываются только **марка, модель и модельный год** (без VIN и без заводских индексов кузова/шасси вроде Wxxx):


| Марка         | Модель  | Год       | Заметка                                                                                                                                                                                                                                    |
| ------------- | ------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Honda         | CR-V    | 2004      | **K-Line / ISO 9141**; опрашивался **двигатель / основной ЭБУ**. Блоки ABS, SRS, TCM, BCM в приложении идут через **ATSH по CAN**; на этой машине они **в ту же OBD2-сессию обычно не попадали**. Основной заезд для BT и Wi‑Fi адаптеров. |
| Ford          | Focus   | 2011–2012 | CAN; TCM и доп. блоки, декодирование года                                                                                                                                                                                                  |
| Audi          | A7      | 2013      | CAN; несколько ЭБУ, сверка отчёта                                                                                                                                                                                                          |
| Mercedes-Benz | G-Class | —         | CAN; краевые случаи года, DTC и имён ЭБУ (логи)                                                                                                                                                                                            |
| Infiniti      | Q50     | —         | CAN; платформа Nissan, доп. блоки (логи/UI)                                                                                                                                                                                                |


Весь **заявленный функционал** на доступных блоках **работает**; полноту «других ЭБУ» на конкретной машине определяет шина и поддержка блоками Mode 03 / UDS.

**Адаптеры:**

1. **Синий мини Bluetooth «свисток»** (китайский бюджетный ELM327)
  - В магазинах обычно пишут чип **PIC18F25K80** и **ELM327 v1.5** — так устроены более «честные» клоны. Для проверки можно смотреть ответы `ATI` **/** `AT@1` в консоли отладки приложения.
2. **Красный Wi‑Fi ELM327**
  - Проверено подключение по **Wi‑Fi TCP**. Типичная аппаратная схема: **ESP8266** (реже ESP32) как TCP-сервер и мост UART ↔ прошивка уровня **ELM327** (часто тот же класс PIC/клона, что и в BT-версиях).

Список адаптеров и автомобиля — **не исчерпывающий**; ориентир для регрессии и онбординга.

---

## 2. Структура репозитория

```
uremont-whoop/
├── README.md                  ← общий обзор обоих платформ
├── CONTEXT.md                 ← этот файл (онбординг + контекст)
├── ECU_COVERAGE.md            ← полный список опрашиваемых ECU-блоков по маркам
├── scripts/
│   └── generate_vin_wmi_table.py   ← генерация VinWmiTable из Wikibooks (WMI)
├── .gitignore
│
├── android/                   ← Android-приложение
│   ├── README.md
│   ├── app/src/main/
│   │   ├── AndroidManifest.xml
│   │   ├── res/               ← drawables, strings, themes, FileProvider paths
│   │   └── java/com/uremont/bluetooth/
│   │       ├── UremontApp.kt              ← Application singleton
│   │       ├── MainActivity.kt            ← Compose UI (OBDScreen + страницы/шиты)
│   │       ├── ObdScreenViewModel.kt      ← состояние/сценарии OBD (паритет с iOS AppViewModel)
│   │       ├── AppConfig.kt               ← URL карты, лимиты сессий, дефолты Wi‑Fi, тайминги OBD/live
│   │       ├── ErrorsState.kt             ← Idle/Loading/Result DTC-экрана
│   │       ├── DtcDatabase.kt             ← object DtcLookup: DTC-описания, URL, problemDescription
│   │       ├── ObdConnectionManager.kt    ← BT + Wi-Fi транспорт, OBD2 протокол
│   │       ├── BrandEcuHints.kt           ← марочные CAN-ID + `classify` (21 группа: VAG/Toyota/Subaru/Honda/Ford/… + OTHER)
│   │       ├── ClusterOdometerProbes.kt   ← UDS 22 на комбинации приборов (одометр, опытно)
│   │       ├── ObdStandardLabels.kt       ← подписи PID 1C / 51 (SAE)
│   │       ├── ObdVehicleInfoParse.kt     ← разбор Mode 09/01 для расширенного VehicleInfo
│   │       ├── VinWmiTable.kt             ← ~2103 WMI → подпись производителя (Wikibooks)
│   │       ├── SessionManager.kt          ← SessionRecord + SessionRepository (канон. JSON + legacy)
│   │       ├── PdfReportGenerator.kt      ← PDF через PdfDocument + Canvas
│   │       └── DebugLogger.kt             ← кольцевой буфер логов
│   ├── app/src/test/java/com/uremont/bluetooth/
│   │   └── ObdParserTest.kt              ← 60 unit-тестов (DTC, VIN, BrandEcuHints, UDS 0x19, DtcLookup/FTB)
│   ├── build.gradle.kts / settings.gradle.kts / gradle.properties
│   └── whoop-1.7.0-stable.apk
│
└── ios/                       ← iOS-приложение
    ├── README.md
    ├── project.yml                ← XcodeGen конфигурация
    ├── UremontWhoop.xcodeproj     ← генерируется xcodegen, НЕ в git
    ├── UremontWhoop/
    │   ├── UremontWhoopApp.swift          ← @main, создаёт ObdConnectionManager
    │   ├── Info.plist
    │   ├── Assets.xcassets/               ← SVG-логотип (UremontLogo), AppIcon
    │   ├── Models/BrandConfig.swift       ← URL карты, лимиты, дефолты Wi‑Fi, тайминги (зеркало AppConfig)
    │   ├── Models/SessionRecord.swift     ← SessionRecord + SessionRepository (канон. JSON + legacy)
    │   ├── ViewModels/AppViewModel.swift  ← @MainActor ObservableObject
    │   ├── OBD/
    │   │   ├── ObdConnectionManager.swift ← Wi-Fi TCP (NWConnection), ELM327
    │   │   ├── BrandEcuHints.swift        ← марочные CAN-ID + `classify` (21 группа: VAG/Toyota/Subaru/Honda/Ford/… + OTHER)
    │   │   ├── ClusterOdometerProbes.swift ← UDS 22 на щиток (+Ford), паритет с Android
    │   │   ├── ObdStandardLabels.swift    ← PID 1C / 51
    │   │   ├── ObdVehicleInfoParse.swift  ← разбор ответов Mode 09/01
    │   │   ├── VinWmiTable.swift          ← ~2103 WMI → подпись производителя (Wikibooks)
    │   │   └── DebugLogger.swift
    │   ├── PDF/PdfReportGenerator.swift   ← UIGraphicsPDFRenderer
    │   ├── DTC/DtcDatabase.swift          ← enum DtcLookup namespace
    │   └── Views/
    │       ├── Theme.swift, SplashScreen.swift, MainTabView.swift
    │       ├── ConnectionPage.swift, ErrorsPage.swift, LiveDashboardPage.swift
    │       ├── Components/ (SharedComponents.swift, DtcErrorCard.swift)
    │       └── Sheets/ (WifiSheet, SettingsSheet, HistorySheet, ManualCarPickerSheet)
    └── UremontWhoopTests/
        ├── ObdParserTests.swift
        └── DtcDatabaseTests.swift
```

---

## 3. Кросс-платформенные различия (КЛЮЧЕВОЙ РАЗДЕЛ)

### 3.1 Архитектура и структура кода


| Аспект                        | Android                                                                                                         | iOS                                                              |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| **Архитектура**               | Compose UI в `MainActivity` + `ObdScreenViewModel` (OBD-сценарии и стейт экранов, паритет с iOS `AppViewModel`) | MVVM: `AppViewModel` + экраны SwiftUI                            |
| **DTC-функции**               | `object DtcLookup` в отдельном файле `DtcDatabase.kt`                                                           | `enum DtcLookup` namespace в отдельном файле `DtcDatabase.swift` |
| `**buildProblemDescription`** | Словарь `Map<String, String>` (~45 записей) + regex для P030X                                                   | Словарь `[String: String]` (~45 записей) + regex для P030X       |
| `**buildUremontUrl**`         | `Uri.Builder` + `appendQueryParameter` (безопасное кодирование)                                                 | `URLComponents` + `URLQueryItem` (безопасное кодирование)        |
| **Навигация (пейджер)**       | `HorizontalPager` (Compose Foundation)                                                                          | `TabView(.page(indexDisplayMode: .never))`                       |
| **Настройки**                 | `AppSettings` — `**SharedPreferences`** (персистируются)                                                        | `AppSettings` — `**UserDefaults**` (персистируются)              |
| **Wi-Fi host/port**           | `rememberSaveable` (переживает recomposition, НЕ перезапуск)                                                    | `@Published` в `AppViewModel` (только в памяти)                  |
| **Unit-тесты**                | 60 тестов (`ObdParserTest`: DTC, VIN, BrandEcuHints, UDS 0x19, DtcLookup/FTB)                                   | 46 тестов (`ObdParserTests` 33 + `DtcDatabaseTests` 13)          |


### 3.2 Транспорт и подключение


| Аспект                  | Android                                                    | iOS                                                   |
| ----------------------- | ---------------------------------------------------------- | ----------------------------------------------------- |
| **Bluetooth Classic**   | Да (3 стратегии: InsecureSPP → SecureSPP → Reflection-ch1) | Нет (iOS запрещает SPP для неаксессуаров)             |
| **Wi-Fi TCP**           | `java.net.Socket` + `BufferedReader`/`OutputStream`        | `NWConnection` (Network.framework)                    |
| **TCP_NODELAY**         | `socket.tcpNoDelay = true`                                 | `tcp.noDelay = true` на `NWProtocolTCP.Options`       |
| **Таймаут подключения** | `socket.connect(addr, 10_000)`                             | 10 сек через `DispatchQueue.asyncAfter`               |
| **Чтение ответов**      | Blocking `readLine()` с `soTimeout`                        | Async `NWConnection.receive` с `ContinuationGuard`    |
| `**consumeAtResponse`** | Wi-Fi: `readUntilPrompt`, BT: `drainInput`                 | Только `readUntilPrompt` (нет BT)                     |
| **Мьютекс I/O**         | `kotlinx.coroutines.sync.Mutex`                            | Кастомный `AsyncMutex` (NSLock + CheckedContinuation) |
| **pollSensor**          | `ioMutex.tryLock()` — мгновенный ERROR                     | `asyncMutex.tryLock()` — мгновенный ERROR             |
| **Остальные операции**  | `ioMutex.withLock` — ждёт                                  | `asyncMutex.withLock` — ждёт                          |


### 3.3 UI-фреймворк и шиты


| Аспект                | Android                                          | iOS                                           |
| --------------------- | ------------------------------------------------ | --------------------------------------------- |
| **UI**                | Jetpack Compose (Material3)                      | SwiftUI                                       |
| **Тема**              | `UremontTheme` + `darkColorScheme(...)`          | `.preferredColorScheme(.dark)` + `enum Brand` |
| **Sheets**            | `ModalBottomSheet` (Material3)                   | `.sheet` + `.presentationDetents`             |
| **Splash**            | `AnimatedContent` → `SplashScreen` → `OBDScreen` | `@State` + `if showSplash`                    |
| **PDF-просмотр**      | `ACTION_VIEW` intent + chooser                   | `QuickLook` preview                           |
| **PDF-шаринг**        | `ACTION_SEND` через `FileProvider`               | `UIActivityViewController`                    |
| **QR-код**            | ZXing `QRCodeWriter`                             | CoreImage `CIQRCodeGenerator`                 |
| **Интернет-проверка** | `ConnectivityManager.getNetworkCapabilities()`   | `NWPathMonitor` singleton                     |

---

## 4. Технический стек

### Android


| Компонент        | Версия                  | Заметки                                   |
| ---------------- | ----------------------- | ----------------------------------------- |
| Kotlin           | 1.9.23                  | НЕ 2.0 — `kotlin.plugin.compose` не нужен |
| Compose BOM      | 2024.04.00              |                                           |
| Compose Compiler | 1.5.11                  | Строго привязан к Kotlin 1.9.23           |
| Min SDK          | 24 (Android 7.0)        |                                           |
| Target SDK       | 34 (Android 14)         |                                           |
| AGP              | 8.3.2                   |                                           |
| Gradle           | 8.7                     |                                           |
| JVM target       | 17                      |                                           |
| ZXing Core       | 3.5.3                   | QR-коды                                   |
| Coroutines       | 1.8.1                   |                                           |
| applicationId    | `com.uremont.bluetooth` |                                           |


### iOS


| Компонент             | Версия                     | Заметки                                                        |
| --------------------- | -------------------------- | -------------------------------------------------------------- |
| Swift                 | 5.9+                       |                                                                |
| SwiftUI               | iOS 16+                    | `TabView(.page)` для навигации                                 |
| Combine               | —                          | `ObservableObject` для `ObdConnectionManager` и `AppViewModel` |
| Network.framework     | —                          | TCP с `NWConnection` (noDelay)                                 |
| CoreImage             | —                          | QR-коды (`CIQRCodeGenerator`)                                  |
| UIGraphicsPDFRenderer | —                          | PDF A4                                                         |
| QuickLook             | —                          | Предпросмотр PDF-отчёта                                        |
| XcodeGen              | —                          | `.xcodeproj` из `project.yml`, не в git                        |
| Bundle ID             | `com.uremont.UremontWhoop` |                                                                |
| Marketing Version     | 1.7.0-stable               | Build 7                                                        |


---

## 5. Архитектура

### 5.1 Экраны (3 страницы, свайп)

```
PAGE_CONNECTION (0) ──swipe──> PAGE_ERRORS (1) ──swipe──> PAGE_DASHBOARD (2)
```

Индикатор: кастомные **PageDots** (`ПОДКЛЮЧЕНИЕ` / `ОШИБКИ` / `ДАТЧИКИ`).  
Кнопки по углам: История (верхний левый), Настройки (верхний правый).

### 5.2 Управление состоянием

**iOS (MVVM):**

```
UremontWhoopApp
  └── AppRoot (создаёт ObdConnectionManager как @StateObject)
        └── OBDScreen (создаёт AppViewModel как @StateObject)
              ├── AppViewModel: подключение, DTC, мониторинг, история, PDF
              └── OBDScreen: showSettings, showHistory, currentPage и т.д.
```

**Android (monolith):**

```
UremontApp (Application) — держит ObdConnectionManager
  └── MainActivity (ComponentActivity)
        └── OBDScreen(@Composable) — всё в mutableStateOf / rememberSaveable
```

### 5.3 Жизненный цикл подключения

1. Пользователь выбирает адаптер: Wi-Fi IP:порт (обе платформы) или BT-устройство (Android)
2. TCP/RFCOMM подключение с `tcpNoDelay`, таймаут 10 сек
3. Инициализация ELM327: `ATZ → ATE0 → ATL0 → ATH0 → ATS0 → ATSP0 → 0100` (warmup 9 сек)
4. Чтение VehicleInfo (Mode 09: VIN/02, маска/00, CalID/03, CVN/04, опц. 01/05–09, ECU/0A; при CAN — имя ЭБУ КПП `ATSH 7E1`+090A; Mode 01: OBD 1C, топливо 51, 21/31, **Fuel Status 03, Warm-ups 30, Time cleared 4E**) + ReadinessMonitors (Mode 01/01)
5. Пользователь запускает «Прочитать»: Mode 03 + 07 + **0A** (permanent PDTC, часто пусто на EU), опционально Freeze Frame (02, **включая DTC-триггер PID 02, LTF, Voltage, Fuel Status**) и другие ЭБУ (ATSH + **Mode 03 + 07 + 0A**; если Mode 03 не поддерживается — **UDS 0x19 02 FF fallback**)
6. Пользователь запускает Live мониторинг: цикл опроса 29 PID (Mode 01)

### 5.4 Модальные экраны (Sheets / Dialogs)


| Экран                     | Триггер                               | Содержимое                                      |
| ------------------------- | ------------------------------------- | ----------------------------------------------- |
| WifiSheet                 | Кнопка «Выбрать адаптер» → Wi-Fi      | IP:порт, пресеты адаптеров, инструкция          |
| DeviceSheet (Android)     | Кнопка «Выбрать адаптер» → Bluetooth  | Список сопряжённых BT-устройств                 |
| TransportPicker (Android) | Кнопка «Выбрать адаптер»              | Выбор: Bluetooth или Wi-Fi                      |
| ManualCarPickerSheet      | Переключение профиля на Manual        | 34 марки → модели → год                         |
| SettingsSheet             | Кнопка ⚙ (верхний правый угол)        | Freeze Frame on/off, другие ЭБУ on/off, консоль |
| HistorySheet              | Кнопка 📋 (верхний левый угол)        | Список SessionCard                              |
| DebugConsole              | Внутри SettingsSheet                  | Логи OBD-команд, копировать/очистить            |
| QrCodeDialog              | DtcErrorCard при отсутствии интернета | QR-код с URL uremont                            |
| PDF Alert                 | После генерации PDF                   | Открыть / Поделиться                            |


---

## 6. ObdConnectionManager — ключевые детали

### Инициализация ELM327

```
ATZ   → delay(2000) → consumeAtResponse(3000)   ← сброс чипа
ATE0  → delay(300)  → consumeAtResponse()        ← эхо выкл
ATL0  → delay(300)  → consumeAtResponse()        ← linefeeds выкл
ATH0  → delay(300)  → consumeAtResponse()        ← CAN-заголовки выкл
ATS0  → delay(300)  → consumeAtResponse()        ← пробелы выкл
ATSP0 → delay(300)  → consumeAtResponse()        ← автопротокол
0100  → readUntilPrompt(9000)                     ← обязательный прогрев (K-Line может до 9 сек)
```

### Таймауты


| Параметр               | Значение | Назначение                             |
| ---------------------- | -------- | -------------------------------------- |
| CONNECT_TIMEOUT_SEC    | 10       | Таймаут TCP/BT подключения             |
| READ_TIMEOUT_MS        | 12000    | DTC/clear (покрывает K-Line re-init)   |
| SENSOR_TIMEOUT_WIFI_MS | 800      | Live PID по Wi-Fi                      |
| SENSOR_TIMEOUT_BT_MS   | 1500     | Live PID по Bluetooth (только Android) |
| Warmup threshold       | 3500     | K-Line P3_Max keepalive                |


### Concurrency


| Платформа | Механизм                             | pollSensor                     | Остальные            |
| --------- | ------------------------------------ | ------------------------------ | -------------------- |
| Android   | `kotlinx.coroutines.sync.Mutex`      | `tryLock()` → мгновенный ERROR | `withLock` (ожидает) |
| iOS       | `AsyncMutex` (NSLock + continuation) | `tryLock()` → мгновенный ERROR | `withLock` (ожидает) |


**iOS-специфичные механизмы:**

- **ContinuationGuard** — one-shot `@unchecked Sendable` guard для безопасного resumption `CheckedContinuation` из нескольких NWConnection callbacks (timeout vs data).
- **ReadState** — `@unchecked Sendable` обёртка для `Data` буфера + `ContinuationGuard`.
- **pollingToken** — `"\(isMonitoring)-\(isConnected)"`, используется в `.task(id:)` для автоматической отмены/перезапуска цикла опроса сенсоров.
- **drainInput** — пауза 50мс между командами (1.5-stable). Ранее использовался pump с `connection.receive()`, но NWConnection не поддерживает отмену отдельного `receive()` — «висящий» обработчик крал данные следующего `readUntilPrompt`, из-за чего ВСЕ OBD-ответы возвращались пустыми.

**Android-специфичные механизмы:**

- **3 стратегии Bluetooth:** InsecureSPP → SecureSPP → Reflection-ch1 (фаллбэк для китайских адаптеров).
- **consumeAtResponse()** — транспортно-осведомлённый хелпер: Wi-Fi → `readUntilPrompt`, BT → `drainInput`.
- **Blocking I/O** на `Dispatchers.IO` с `soTimeout` (в отличие от async на iOS).

### Другие блоки (CAN ATSH)

Базовый список (всегда, 7 блоков):

```
7B0 → ABS / Тормоза
7D0 → SRS / Подушки безопасности
7E1 → Коробка передач (TCM)
7E2 → Доп. силовой (гибрид / дизель / 2-й ECM)
7E3 → Раздаточная коробка / 4WD
7E4 → Кузов (BCM)
```

Полный перечень всех CAN-адресов по маркам — `[ECU_COVERAGE.md](ECU_COVERAGE.md)`.

По `VehicleInfo.detectedMake` + VIN (`BrandEcuHints` / `BrandEcuHints.swift`) добавляются марочные адреса **без дубликатов** `txHeader`. Марка из **ручного профиля** (`CarProfile.manual`) подмешивается через `mergeMakeHints`: при пустом WMI, но выбранной вручную Toyota, всё равно попадают toyota-спеки (в т.ч. **EPS `7A0`**).

Поддерживаемые марочные группы (21 шт., 20 именованных + **OTHER**): **VAG** (в т.ч. Porsche по строке марки), **Toyota, Subaru, Honda, Ford, Mercedes, Renault, PSA, GM, Hyundai/Kia, Mazda, Nissan, Mitsubishi, BMW/Mini, Jaguar/LR, Lada, Changan, Chery, Haval/GWM, Geely** + OTHER.


| Марка                            | Доп. ATSH (CAN-адреса блоков)                                                                                                                                                               | Доп. всего |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| VAG (VW/Audi/Skoda/Seat/Porsche) | `710` шлюз, `714` приборы, `7B6` ABS/ESP, `712` рулевое, `713` тормоза, `715` подушки, `716` SWM, `752` EPB, `70A` Park Assist, `750` Lane Assist, `757` ACC, `765` TPMS, `770` HVAC        | 13         |
| Toyota / Lexus                   | `750` body/gw, `7C0` приборы, `7A0` EPS, `740` фары, `780` SRS, `788` Smart Key, `790` TPMS, `792` Parking/Sonar                                                                            | 8          |
| Honda / Acura                    | `760` приборы, `7A0` EPS, `7C0` body/MICU, `770` HVAC                                                                                                                                       | 4          |
| Ford / Lincoln / Mercury         | `720` IPC, `743` TCM, `724` BCM, `726` APIM, `732` доп., `736` RCM/SRS, `760` PDC, `764` ABS/ESP, `770` HVAC, `7A0` EPS, `7A4` ACC                                                          | 11         |
| Mercedes-Benz                    | `720` IC, `740` SAM пер., `741` SAM зад., `743` EZS, `7A0` EPS, `7D2` ESP, `760` PDC, `770` HVAC                                                                                            | 8          |
| Renault / Dacia / Alpine         | `770` TDB, `742` UCH, `760` EPS, `771` HVAC, `762` parking, `764` ABS/ESP                                                                                                                   | 6          |
| PSA (Peugeot/Citroen/Opel)       | `752` BSI, `753`/`740`/`742` доп., `764` ABS/ESP, `760` EPS, `770` HVAC                                                                                                                     | 7          |
| GM (Chevrolet/Buick/Cadillac)    | `724` IPC, `728`/`244` доп., `7D2` SDM, `7A6` Park Assist                                                                                                                                   | 5          |
| Hyundai / Kia / Genesis          | `7A0` комб., `7A2` доп., `7A6` TPMS, `770`/`771` BCM, `794` Smart Key, `7C6` доп., `7D4` EPB                                                                                                | 8          |
| Mazda                            | `720` приборы, `730`/`731` доп., `7A0` EPS, `764` DSC, `742` BCM                                                                                                                            | 6          |
| Mitsubishi                       | `750` body/gw, `7C0` комб., `760` EPS, `770` HVAC, `790` TPMS                                                                                                                               | 5          |
| Nissan / Infiniti                | `743`/`744` комб., `740` BCM, `746` EPS, `747` ABS/VDC, `760` body, `765` HVAC, `772` TPMS, `7B2` ACC/радар, `793` доп.                                                                     | 10         |
| BMW / Mini                       | `600`/`601` KOMBI, `602` EGS/АКПП, `612` DME/DDE, `630` шлюз, `640` CAS, `6B0` DSC, `6C0` FRM                                                                                               | 8          |
| Jaguar / Land Rover              | `7C4` приборка, `736`/`737` доп., `740` BCM, `764` ABS, `770` HVAC                                                                                                                          | 6          |
| Lada                             | `712`/`714`/`715`/`720` приборы, `740` BCM, `760` EPS, `770` HVAC, `7B2` ABS (Bosch)                                                                                                        | 8          |
| Changan                          | `720` IPC, `740` BCM, `770` HVAC, `760` EPS, `714` доп.                                                                                                                                     | 5          |
| Chery (Omoda/Jaecoo/Exeed)       | `720` IPC, `740` BCM, `770` HVAC, `760` EPS, `714` доп.                                                                                                                                     | 5          |
| Haval / GWM (Tank/Wey/Ora)       | `720` IPC, `740` BCM, `770` HVAC, `760` EPS, `714` доп.                                                                                                                                     | 5          |
| Geely (Lynk & Co / Zeekr)        | `720` IPC, `740` BCM, `770` HVAC, `760` EPS, `714` доп.                                                                                                                                     | 5          |
| Subaru                           | `744` BIU, `746` EPS, `747` ABS/VDC, `7C0` приборы, `740` BCM, `750` gw, `7A0` EPS зап., `760` автосвет, `770` HVAC, `780` TPMS, `787` EyeSight, `788` ключ, `792` парковка, `7B6` ABS доп. | 14         |


После опроса: `ATD` → `ATE0/ATL0/ATH0/ATS0` → `0100` warmup (восстановление K-Line).

**PID 0x31 (Mode 01)** в карточке авто — *не* полный пробег с щитка: по SAE это дистанция с **последнего сброса DTC** в сканере, максимум 65535 км (2 байта). **Полный одометр** в OBD-II **не стандартизован**; универсально читаются VIN, CalID/CVN, тип OBD/топлива, имена ЭБУ (двигатель; на CAN — попытка КПП по 7E1).

**Одометр щитка (экспериментально, обе платформы):** при `ATDP` = CAN/ISO 15765 и **любой распознанной марочной группе** (`BrandEcuHints.classify` по WMI/`detectedMake`) выполняется цепочка **UDS ReadDataByIdentifier (0x22)** с `ATSH` на типовые адреса комбинации приборов — таблица в `ClusterOdometerProbes` / `ClusterOdometerProbes.swift`. Поддерживаются **все 21 группа** `VehicleBrandGroup` (включая **Subaru**). Ручная марка в профиле **не** участвует в `classify` (в отличие от списка доп. ЭБУ через `mergeMakeHints`). DID зависят от марки/платформы; после прогона — `restoreElmAfterAtsh`. Значение может отсутствовать или не совпадать с щитком; в UI/PDF выводится примечание с CAN-ID и hex-запросом.

### UNIVERSAL_PIDS (29 штук)

RPM, Speed, Engine Load, TPS, Runtime, Coolant, IAT, Ambient, Oil Temp, MAP, MAF, Baro, Fuel Level, Fuel Pressure, STF1/LTF1/STF2/LTF2, Voltage, Ignition Advance, Catalyst Temp B1S1/B2S1, O2 B1S1/B2, EGR, Absolute Load, A/F Ratio, Time with MIL on, **Engine Fuel Rate** (PID 5E, л/ч).

---

## 7. DTC-база и URL-генератор

### DTC-справочник


| Платформа | Где определены                         | Формат                   |
| --------- | -------------------------------------- | ------------------------ |
| iOS       | `enum DtcLookup` в `DtcDatabase.swift` | Static-функции + словарь |
| Android   | `object DtcLookup` в `DtcDatabase.kt`  | Функции + словарь        |


### Приоритет описаний: dtcInfo(code, profile, detectedMake?)

1. Профиль `Manual` с маркой → OEM-функция (BMW / VAG / Mercedes)
2. Toyota / Lexus: марка в ручном профиле **или** `detectedMake` из VIN (строка WMI вроде `Toyota car` / `Toyota MPV/SUV` — JDM `JT*`… Crown, Caldina и т.д.) → таблица `toyotaLexusDtcInfo` (VVT-i, A/F банк 2, старт и т.д.)
3. Универсальная таблица: ~110+ кодов (P/B/C/U), в т.ч. уже размеченные Toyota-куски (C1201, P1135, P1300) для всех марок
4. Неизвестный код → заглушка «Код неисправности …» + рекомендация сервисной диагностики

Коды вида `**P0420-17`** (UDS 0x19, суффикс FTB) при поиске в таблицах и в `problemDescriptions` приводятся к базовому `**P0420**` (`baseDtcCode` / `DtcLookup.baseDtcCode`).

### buildUremontUrl()

Формат: `https://map.uremont.com/?ai=[URL-encoded строка]`  
Строка: `"[марка] [год] [описание проблемы]"`  
Приоритет: VehicleInfo (из ЭБУ) > CarProfile.Manual > "автомобиль"

### decodeDtc — парсинг hex в код ошибки

Первый nibble (2 бита) → категория: `00=P, 01=C, 10=B, 11=U`.  
Пример: `0133` → `P0133` (O2 sensor B1S1).

### QR-код


| Платформа | Библиотека                    |
| --------- | ----------------------------- |
| Android   | ZXing `QRCodeWriter`          |
| iOS       | CoreImage `CIQRCodeGenerator` |


Показывается только при отсутствии интернета (проверка через NetworkChecker / ConnectivityManager).

---

## 8. UI — общие принципы

### Цветовая схема (идентична на обеих платформах)

```
Bg       = #0D0D0F     Blue     = #227DF5
                        BlueDark = #0063E4
Surface  = #18181B     Green   = #34C759
Card     = #242428     Red     = #FF3B30
Border   = #36363C     Orange  = #FF9500
Text     = #F0F0F5     Yellow  = #FCC900
Subtext  = #8E8E93
```

iOS: `enum Brand` в `Theme.swift`  
Android: top-level `val` в `MainActivity.kt` (BrandBlue, BrandBg и т.д.)

### Ключевые компоненты


| Компонент         | Назначение                                   | Android            | iOS                            |
| ----------------- | -------------------------------------------- | ------------------ | ------------------------------ |
| SplashScreen      | Логотип UREMONT, прогресс-бар, ~2.7 сек      | `@Composable`      | `struct SplashScreen: View`    |
| ConnectionPage    | Статус, профиль авто, VehicleInfo, Readiness | `@Composable`      | `struct ConnectionPage: View`  |
| ErrorsPage        | DTC-карточки, Freeze Frame, блоки ECU, PDF   | `@Composable`      | `struct ErrorsPage: View`      |
| LiveDashboardPage | Сетка SensorCard с live-данными              | `LazyVerticalGrid` | `LazyVGrid`                    |
| DtcErrorCard      | Одна ошибка: описание, severity, URL/QR      | `@Composable`      | `struct DtcErrorCard: View`    |
| SettingsSheet     | Toggles + консоль отладки                    | `ModalBottomSheet` | `.sheet(.presentationDetents)` |
| HistorySheet      | Список SessionCard                           | `ModalBottomSheet` | `.sheet(.presentationDetents)` |
| WifiSheet         | IP:порт, пресеты, инструкция                 | `ModalBottomSheet` | `.sheet(.large)`               |
| PageDots          | Индикатор текущей страницы                   | `Row` + `Box`      | `HStack` + `Circle`            |


---

## 9. История сессий и PDF

### SessionRecord


| Поле           | Тип                                                     | Описание                                                              |
| -------------- | ------------------------------------------------------- | --------------------------------------------------------------------- |
| id             | String/UUID                                             | Уникальный идентификатор                                              |
| timestamp      | Long (Android, мс) / `TimeInterval` (iOS, сек в памяти) | В **JSON** — миллисекунды Unix, ключ `timestamp` (плюс чтение legacy) |
| vehicleName    | String                                                  | Марка + модель или VIN                                                |
| vin            | String?                                                 | VIN (если считан)                                                     |
| mainDtcs       | [String]                                                | Подтверждённые коды (Mode 03)                                         |
| pendingDtcs    | [String]                                                | Ожидающие коды (Mode 07)                                              |
| permanentDtcs  | [String]                                                | Постоянные PDTC (Mode 0A)                                             |
| hasFreezeFrame | Bool                                                    | Был ли Freeze Frame                                                   |
| otherEcuErrors | Dict/Map                                                | Ошибки из ABS/SRS/TCM/BCM и марочных блоков                           |


- Максимум **100** записей (`AppConfig` / `BrandConfig`), новые первыми, FIFO.
- Канонический JSON на обеих платформах: длинные ключи (`vehicleName`, `mainDtcs`, `otherEcuErrors` как объект и т.д.).
- Чтение legacy: Android — короткие ключи (`ts`, `vn`, `md`…); iOS — `timestamp` в секундах (старые файлы) и Android-short keys.
- JSON-файл: Android — `filesDir/sessions.json`, iOS — `Application Support/<bundleId>/sessions.json`.
- `SessionRepository.loadAllDetailed` (Android) возвращает диагностику (I/O, parse, частичные записи); пользователю — Toast через строки `R.string.session_history_`*.
- Потокобезопасность: iOS — `NSLock`; Android — однопоточный UI + запись из корутин (без глобальной блокировки объекта).

### PDF-отчёт (A4, 595×842pt)

1. Тёмная шапка с логотипом UREMONT и названием авто
2. Информация об автомобиле (VIN, марка, пробег)
3. Мониторы готовности (2 колонки, зелёный/красный)
4. Подтверждённые DTC — Mode 03 (карточки с severity-полосой: красная/жёлтая/серая)
5. Ожидающие DTC — Mode 07
6. Постоянные PDTC — Mode 0A
7. Freeze Frame (сетка 2×N)
8. Блоки управления (марочные + универсальные)
9. Footer на каждой странице


| Платформа | API                                      | Шаринг                         |
| --------- | ---------------------------------------- | ------------------------------ |
| Android   | `PdfDocument` + `Canvas`/`Paint`         | `FileProvider` + `ACTION_SEND` |
| iOS       | `UIGraphicsPDFRenderer` + `UIBezierPath` | `UIActivityViewController`     |


---

## 10. Настройки (AppSettings)

```
freezeFrameEnabled: Bool = false   // Mode 02, +3-5 сек к сканированию
otherEcusEnabled:   Bool = true    // ATSH ABS/SRS/TCM/BCM, +15-20 сек
```


| Платформа | Персистентность | Механизм                                                  |
| --------- | --------------- | --------------------------------------------------------- |
| iOS       | Да              | `UserDefaults` (didSet на свойствах)                      |
| Android   | Да              | `SharedPreferences` (load/save в `AppSettings.Companion`) |


### NetworkChecker (проверка интернета)


| Платформа | Механизм                                       |
| --------- | ---------------------------------------------- |
| iOS       | `NWPathMonitor` singleton                      |
| Android   | `ConnectivityManager.getNetworkCapabilities()` |


### DebugLogger

- Singleton кольцевой буфер на **800** записей (обе платформы).
- Логирует: все OBD2-команды (`>> CMD`, `<< response`), подключения, ошибки.
- UI: Консоль отладки в SettingsSheet. Кнопки: Скопировать, Очистить, Закрыть.
- Android: дублирует в Logcat (`Log.d`/`Log.w`/`Log.e`).
- iOS: дублирует в `os_log`.

---

## 11. Сборка и деплой

### Android

```bash
cd android/
./gradlew assembleDebug          # → app/build/outputs/apk/debug/app-debug.apk
./gradlew assembleRelease        # → app/build/outputs/apk/release/ (нужен signing config)
# Актуальный артефакт для раздачи из корня android/:
cp app/build/outputs/apk/debug/app-debug.apk whoop-1.7.0-stable.apk
```

Или: открыть `android/` в Android Studio → Run.

### iOS

```bash
cd ios/
brew install xcodegen            # один раз
xcodegen generate                # создаёт .xcodeproj из project.yml
open UremontWhoop.xcodeproj      # → Signing → Team → Run (Cmd+R)
```

> `.xcodeproj` НЕ в git. При изменении файлов/таргетов — обновить `project.yml` и `xcodegen generate`.

### Git: локальные хуки

Папка `**.githooks/**` в `**.gitignore**` — в репозиторий и на GitHub не попадает. При необходимости создайте у себя скрипты (например `commit-msg`), затем: `git config core.hooksPath .githooks` и `chmod +x .githooks/commit-msg`.

---

## 12. Известные ограничения и решения


| Проблема                                                               | Платформа  | Решение                                                                                                                                                                                                                                                                                                                                |
| ---------------------------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| K-Line 5-baud init (старые авто до 2004)                               | Обе        | Warmup `0100` с таймаутом 9 сек                                                                                                                                                                                                                                                                                                        |
| TCP `available()` = 0 на Wi-Fi                                         | Android    | `soTimeout` + blocking read                                                                                                                                                                                                                                                                                                            |
| NWConnection buffered reads                                            | iOS        | `readUntilPrompt` с `ContinuationGuard`; `drainInput` — только delay (1.5-stable: pump с `receive()` крал данные)                                                                                                                                                                                                                      |
| K-Line P3_Max timeout (пауза >3.5 с)                                   | Обе        | `warmupIfNeeded()` → `0100`                                                                                                                                                                                                                                                                                                            |
| Mode 04 убивает K-Line сессию                                          | Обе        | `postClearWarmup()`: delay 2.5с → ATPC → 0100                                                                                                                                                                                                                                                                                          |
| ATSH на K-Line меняет заголовки                                        | Обе        | `ATD` + re-init после `readOtherEcuDtcs`                                                                                                                                                                                                                                                                                               |
| iOS не поддерживает BT Classic (SPP)                                   | iOS        | Только Wi-Fi TCP                                                                                                                                                                                                                                                                                                                       |
| VIN Year 30-year cycle (две интерпретации одного символа)              | Обе        | `decodeVinYear`: NA — WMI начинается с цифры 1–5: 7-я позиция цифра → «новый» 30-летний цикл, иначе «старый»; RoW — из двух лет выбирается ближе к текущему календарному. **WDB** Mercedes: 10-й символ не кодирует год → `nil`. 10-й символ VIN по SAE не равен «маркетинговому» году модели.                                         |
| Карточка «данные авто» — лишняя высота / подписи не видны              | Обе        | Android: фиксированная ширина подписи в `VehicleInfoRow`; iOS: без `minHeight: geo` внутри `ScrollView` на Connect                                                                                                                                                                                                                     |
| Карточка «данные авто» — смысл параметра напротив значения             | Обе        | Тот же порядок и формулировки, что `drawVehicleInfoSection` в PDF; тонкие разделители между строками; подпись 11pt / значение 12 semibold                                                                                                                                                                                              |
| «Сохранённые» ошибки vs сканер по блокам                               | Обе        | **Mode 03** на каждом адресе = подтверждённые DTC в памяти ЭБУ (аналог «stored» в OBD-II). **Mode 0A** — отдельный список permanent PDTC (чаще USA). История (`SessionRecord`) хранит main + pending + **permanent** + `otherEcuErrors`. Полная история DTC как у дилерского сканера (UDS **0x19** и т.д.) в приложении не реализована |
| КПП Ford: только мусор в 090A или нет ответа 7E1                       | Часть авто | Доп. опрос **743** в `BrandEcuHints` для Ford; WMI **X9F** (РФ) в списке Ford. Ошибки КПП — `readOtherEcuDtcs` при включённых «Других блоках»                                                                                                                                                                                          |
| Имя ЭБУ (090A), мусор при multi-ECU multi-frame                        | Обе        | Парсер ограничивает чтение до следующего маркера `490A`; `isPlausibleEcuName` отсекает остаточный мусор                                                                                                                                                                                                                                |
| Китайские BT-адаптеры без SPP UUID                                     | Android    | Reflection-ch1 как 3-я стратегия подключения                                                                                                                                                                                                                                                                                           |
| VIN «пустой» при непустом ответе `0902` (формат `014 0:… 1:…`)         | Обе        | Нормализация: разрез по `\s+\d{1,2}:` до склейки hex; не использовать regex `[0-9]+:` после удаления всех пробелов                                                                                                                                                                                                                     |
| WMI → «марка» в UI                                                     | Обе        | `VinWmiTable` (~2103 кода): парсинг Wikibooks *World Manufacturer Identifier*; официальный полный список SAE J1044 — платная подписка                                                                                                                                                                                                  |
| «Пробег» в UI ≠ одометр приборки                                       | Обе        | PID **0x31** — только с последнего **clear DTC** (max 65535 км); полный пробег в OBD2 стандарте не задаётся                                                                                                                                                                                                                            |
| «Одометр щитка (опытно)» в UI/PDF                                      | Обе        | Марочные UDS **22** + эвристики парсинга; сверять с приборкой; на K-Line не выполняется                                                                                                                                                                                                                                                |
| Долгое чтение VehicleInfo                                              | Обе        | Доп. запросы Mode 09/01 + `ATDP` + при CAN — UDS-пробы щитка, затем `ATSH 7E1`/090A и восстановление адаптера (~15–40 с на медленных ЭБУ)                                                                                                                                                                                              |
| PID 0x21 / 0x31 (пробег MIL / после сброса) теряется в «шумном» ответе | Обе        | Поиск первого `4121`/`4131` + 4 hex через regex, не `indexOf` по одному смещению                                                                                                                                                                                                                                                       |
| ABS/SRS/BCM: `NO DATA` или `7F 03 11` при ATSH 7B0/7D0/7E2/7E3/7E4     | Часть авто | Mode 03 поддерживается не всеми блоками. Добавлен UDS 0x19 fallback: если Mode 03 не ответил, автоматически пробуется `10 03` (Extended Session) + `19 02 FF` (ReadDTCByStatusMask). Работает только на CAN.                                                                                                                           |
| Парсинг DTC на K-Line давал P3500 вместо P0135                         | Honda 2004 | Фикс: на non-CAN протоколах (ISO 9141, KWP) первый байт после маркера — не count, а сразу DTC; `isCanProtocol` по ATDP                                                                                                                                                                                                                 |
| Mitsubishi JMB/JMY VIN попадал в Mazda вместо Mitsubishi               | JMB-VIN    | Фикс: `isLikelyMazda` → `JM1`/`JM3`/`JMZ` (3-символьные); `isLikelyMitsubishi` → `JMB`/`JMY` вместо `JM` (2-символьных)                                                                                                                                                                                                                |
| LVR WMI дублировался в Ford и Changan                                  | LVR-VIN    | Фикс: убран `LVR` из `CHANGAN_WMI` (это Ford Changan JV, классифицируется как Ford)                                                                                                                                                                                                                                                    |


---

## 13. OBD2 команды (справочник)


| Команда     | Режим    | Описание                                                                |
| ----------- | -------- | ----------------------------------------------------------------------- |
| ATZ         | AT       | Сброс ELM327                                                            |
| ATE0        | AT       | Выключить эхо                                                           |
| ATL0        | AT       | Выключить linefeeds                                                     |
| ATH0        | AT       | Выключить CAN-заголовки                                                 |
| ATS0        | AT       | Выключить пробелы в HEX                                                 |
| ATSP0       | AT       | Автовыбор протокола                                                     |
| ATSH [addr] | AT       | Установить CAN-заголовок (для других ЭБУ)                               |
| ATD         | AT       | Сброс ATSH к дефолтам                                                   |
| ATPC        | AT       | Закрыть ECU-сессию (Protocol Close)                                     |
| 0100        | Mode 01  | Supported PIDs + прогрев                                                |
| 0101        | Mode 01  | Мониторы готовности                                                     |
| 0103        | Mode 01  | Fuel System Status (Open/Closed Loop)                                   |
| 0130        | Mode 01  | Warm-ups since DTC cleared                                              |
| 014E        | Mode 01  | Time since DTC cleared (мин)                                            |
| 01xx        | Mode 01  | Live Data (29 PID, включая 015E Fuel Rate)                              |
| 0202        | Mode 02  | DTC, вызвавший Freeze Frame                                             |
| 02xx00      | Mode 02  | Freeze Frame данные (+ LTF, Voltage, Fuel Status)                       |
| 03          | Mode 03  | Подтверждённые DTC (multi-ECU: каждый фрейм раздельно + CAN count byte) |
| 04          | Mode 04  | Сброс DTC + MIL                                                         |
| 07          | Mode 07  | Ожидающие DTC (также на допблоках через ATSH)                           |
| 0A          | Mode 0A  | Permanent DTC (PDTC, также на допблоках через ATSH)                     |
| 0900        | Mode 09  | Поддерживаемые PID 01–20 (битовая маска)                                |
| 0902        | Mode 09  | VIN                                                                     |
| 0903        | Mode 09  | Calibration ID                                                          |
| 0904        | Mode 09  | CVN                                                                     |
| 090A        | Mode 09  | Имя ЭБУ                                                                 |
| 10 03       | UDS      | DiagnosticSessionControl — Extended Session (prelude для 0x19/0x22)     |
| 19 02 FF    | UDS 0x19 | ReadDTCByStatusMask — все DTC (fallback при Mode 03 = NO DATA)          |
| 22 XX XX    | UDS 0x22 | ReadDataByIdentifier — одометр щитка (экспериментально)                 |
| 011C        | Mode 01  | Тип OBD (CARB/EOBD/…)                                                   |
| 0151        | Mode 01  | Тип топлива                                                             |


---

*Обновляй этот файл при каждом существенном изменении: новая фича, фикс архитектуры, новые ограничения.*