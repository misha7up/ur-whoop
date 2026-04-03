# UREMONT WHOOP — OBD2 Диагностика (Android + iOS)

Мобильное приложение для диагностики автомобиля через ELM327-адаптер.  
Два нативных клиента — **Android** (Kotlin/Jetpack Compose) и **iOS** (Swift/SwiftUI) — с единой функциональностью и визуальным стилем.

**Экосистема UREMONT:** 

WHOOP — одна из точек входа: целевая схема — **авторизация** для доступа к диагностике, **рост регистраций**, узнаваемости и вирального трафика. Вовлечение в **лояльность** и предложения платформы; пользователь за регистрацию получает **уровень возможностей близкий к платному Car Scanner**, по сути **без отдельной платы за приложение**. Подробно и по шагам — **§1.0** в [`CONTEXT.md`](CONTEXT.md).

> **Подробный технический контекст**: [`CONTEXT.md`](CONTEXT.md) — архитектура, различия платформ, OBD2-протокол, таймауты, известные ограничения.  
> **Покрытие ЭБУ по маркам**: [`ECU_COVERAGE.md`](ECU_COVERAGE.md) — полный список опрашиваемых блоков, CAN-адреса, одометр UDS.

---

## Протестировано

**Автомобили, на которых сверяли поведение приложения** (только марка / модель / модельный год, без VIN и без заводских индексов кузова):

| Марка | Модель | Год | Заметка |
|-------|--------|-----|---------|
| Honda | CR-V | 2004 | K-Line; основной регресс BT/Wi‑Fi; опрашивались **двигатель и основной ЭБУ**. Опрос ABS/SRS/TCM/BCM в приложении рассчитан на **CAN**; на этой машине в ту же OBD2-сессию, как правило, не выходили прочие блоки. |
| Ford | Focus | 2011–2012 | CAN; коробка и доп. блоки, декодирование года |
| Audi | A7 | 2013 | CAN; несколько ЭБУ, сверка с отчётом |
| Mercedes-Benz | G-Class | — | CAN; сложные сценарии года, DTC и имён ЭБУ (по логам) |
| Infiniti | Q50 | — | CAN; Nissan-платформа, доп. блоки (логи и интерфейс) |

**Весь заявленный функционал** на проверенных конфигурациях **работает** в пределах доступных по шине блоков; сценарий «другие ЭБУ» на **CAN** имеет смысл расширять отдельно.

**Адаптеры ELM327:**

- **Синий Bluetooth «свисток»** (дешёвый китайский мини): в объявлениях чаще всего указывают **Microchip PIC18F25K80** и прошивку **v1.5**;
- **Красный Wi‑Fi** ELM327: проверено по **TCP**; распространённая схема — модуль **ESP8266** (или аналог) как Wi‑Fi↔UART мост к прошивке, эмулирующей **ELM327**.

Подробнее — раздел **1.1** в [`CONTEXT.md`](CONTEXT.md).

**Репозитории:** основной — [`misha7up/uremont-whoop`](https://github.com/misha7up/uremont-whoop); снимок текущего дерева **одним коммитом** (без истории) для тестовой раздачи — [`blendique/ur-whoop`](https://github.com/blendique/ur-whoop).

---

## Возможности

* **Экран подключения** — Wi-Fi ELM327 (Android + BT Classic): VIN, WMI-марка, CalID/CVN (Mode 09), тип OBD и топлива (Mode 01), имена ЭБУ двигателя и (на CAN) КПП, **опытно** одометр щитка (UDS 0x22, **21 марочная группа** в `BrandEcuHints` — 20 именованных + `OTHER`, включая Subaru; все топ-15 РФ и китайские бренды), пробег PID 0x21/0x31 (не полный одометр), мониторы готовности
* **Экран ошибок** — подтверждённые DTC (Mode 03), ожидающие DTC (Mode 07), постоянные PDTC (Mode 0A), снимок параметров Freeze Frame (Mode 02), опрос доп. ЭБУ по CAN (**ATSH**): **7 универсальных** адресов + марочный набор по группе марки (число блоков зависит от марки, максимум порядка **21** с учётом Subaru и VAG; таблицы в [`ECU_COVERAGE.md`](ECU_COVERAGE.md)); **UDS 0x19 fallback** — если блок не поддерживает стандартный Mode 03, автоматически пробуется UDS ReadDTCInformation; экспорт отчёта в PDF
* **Live Dashboard** — 29 параметров в реальном времени (RPM, скорость, температуры, топливные тримы, O₂-датчики, MAF, MAP, напряжение и др.)
* **Стоимость ремонта** — кнопка «Узнать стоимость ремонта» ведёт в экосистему UREMONT: `https://map.uremont.com/?ai=` в браузере; без интернета — QR-код
* **История диагностик** — каждое сканирование сохраняется локально (до 100 записей)
* **PDF-отчёт** — генерация отчёта A4 с возможностью открыть или поделиться
* **Консоль отладки** — in-memory логи OBD2-команд и соединения (800 записей)
* **Универсальная совместимость** — любой автомобиль с OBD2 (1996+); протокол определяется автоматически

---

## Структура репозитория

```
uremont-whoop/
├── README.md              ← этот файл (общий обзор)
├── CONTEXT.md             ← подробный технический контекст + кросс-платформенные различия
├── ECU_COVERAGE.md        ← покрытие ЭБУ по маркам: CAN-адреса, одометр UDS
├── .gitignore
│
├── android/               ← Android-приложение (Kotlin / Jetpack Compose)
│   ├── README.md          ← Android-специфичная документация и архитектура
│   ├── app/src/main/java/com/uremont/bluetooth/
│   │   ├── UremontApp.kt, MainActivity.kt, ObdScreenViewModel.kt, ObdConnectionManager.kt
│   │   ├── AppConfig.kt, SessionManager.kt, PdfReportGenerator.kt, DebugLogger.kt
│   ├── app/src/main/res/  ← drawables, themes, strings, FileProvider
│   ├── app/src/test/java/com/uremont/bluetooth/ObdParserTest.kt  ← 60 unit-тестов
│   ├── build.gradle.kts, settings.gradle.kts, gradle.properties
│   └── whoop-1.7.0-stable.apk
│
└── ios/                   ← iOS-приложение (Swift / SwiftUI)
    ├── README.md          ← iOS-специфичная документация и архитектура
    ├── project.yml        ← XcodeGen конфигурация (.xcodeproj НЕ в git)
    ├── UremontWhoop/
    │   ├── UremontWhoopApp.swift, Info.plist, Assets.xcassets/
    │   ├── ViewModels/AppViewModel.swift
    │   ├── Models/BrandConfig.swift, SessionRecord.swift
    │   ├── OBD/ (ObdConnectionManager.swift, DebugLogger.swift)
    │   ├── PDF/PdfReportGenerator.swift
    │   ├── DTC/DtcDatabase.swift (enum DtcLookup)
    │   └── Views/ (Theme, Splash, MainTabView, Pages, Components, Sheets)
    └── UremontWhoopTests/ (ObdParserTests, DtcDatabaseTests)
```

---

## Навигация (одинакова на обеих платформах)

Три экрана переключаются свайпом влево/вправо:

```
[Подключение] ──swipe──> [Ошибки] ──swipe──> [Live Dashboard]
```

Кнопки по углам: История (верхний левый), Настройки (верхний правый).

---

## Различия между платформами

| Аспект | Android | iOS |
|--------|---------|-----|
| **Версия** | 1.7.0-stable | 1.7.0-stable |
| **Bluetooth** | Да (Classic SPP/RFCOMM, 3 стратегии) | Нет (только Wi-Fi) |
| **Wi-Fi TCP** | `java.net.Socket` | `NWConnection` (Network.framework) |
| **Архитектура** | Compose UI в `MainActivity` + `ObdScreenViewModel` | MVVM: `AppViewModel` + `OBDScreen` |
| **UI Framework** | Jetpack Compose (Material3) | SwiftUI |
| **PDF** | `PdfDocument` + `Canvas` + `FileProvider` | `UIGraphicsPDFRenderer` + `QuickLook` |
| **QR-коды** | ZXing | CoreImage `CIQRCodeGenerator` |
| **Concurrency** | Kotlin Coroutines + `Mutex` | Swift async/await + `AsyncMutex` |
| **Хранение сессий** | JSON в `filesDir` (канон. формат как на iOS) | JSON в `Application Support` |
| **Настройки** | `SharedPreferences` (персистируются) | `UserDefaults` (персистируются) |
| **Unit-тесты** | 60 (`ObdParserTest`) | 46 (`ObdParserTests` + `DtcDatabaseTests`) |
| **DTC-код** | `object DtcLookup` в `DtcDatabase.kt` | `enum DtcLookup` в `DtcDatabase.swift` |
| **Min версия** | Android 7.0 (API 24) | iOS 16.0 |
| **Сборка** | Gradle / Android Studio | XcodeGen + Xcode |

> Подробное сравнение — см. [`CONTEXT.md`](CONTEXT.md), раздел «Кросс-платформенные различия».

---

## OBD2 команды (общие для обеих платформ)

| Команда | Режим | Описание |
|---------|-------|----------|
| ATZ | AT | Сброс ELM327 |
| ATE0 | AT | Выключить эхо |
| ATL0 | AT | Выключить linefeeds |
| ATH0 | AT | Выключить CAN-заголовки |
| ATS0 | AT | Выключить пробелы в HEX |
| ATSP0 | AT | Автовыбор протокола |
| 0100 | Mode 01 | Прогрев: определение протокола (до 9 сек на K-Line) |
| ATSH [addr] | AT | Установить CAN-заголовок (7B0/7D0/7E1/7E2/7E3/7E4 + марочные) |
| 0902 | Mode 09 | VIN |
| 090A | Mode 09 | Имя ЭБУ |
| 0101 | Mode 01 | Мониторы готовности |
| 01xx | Mode 01 | Live Data PIDs (29 параметров) |
| 03 | Mode 03 | Подтверждённые DTC |
| 04 | Mode 04 | Сброс DTC + MIL |
| 07 | Mode 07 | Ожидающие DTC |
| 0A | Mode 0A | Постоянные DTC (PDTC) |
| 02xx00 | Mode 02 | Freeze Frame |
| ATD | AT | Сброс ATSH к дефолтам |
| ATPC | AT | Закрыть ECU-сессию (Protocol Close) |

---

## Быстрый старт

### Android
См. [`android/README.md`](android/README.md) — сборка через Android Studio / Gradle.

### iOS
См. [`ios/README.md`](ios/README.md) — сборка через XcodeGen + Xcode.
