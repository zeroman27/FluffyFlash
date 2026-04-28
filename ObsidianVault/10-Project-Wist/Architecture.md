# Архитектура Wist

> Высокоуровнево: модули, платформа, важные зависимости. Детали кода — в Xcode.

## Платформа

- macOS 26.x (deployment target из проекта), Swift 5, SwiftUI.
- **App Sandbox отключён** (`ENABLE_APP_SANDBOX = NO`) — нужен `Process` + `diskutil` / `hdiutil` / `wimlib-imagex` (копирование ISO→USB — **не** rsync, см. ниже).
- **ATS:** в `App-Info.plist` (корень проекта Xcode, не в синхронизированной папке исходников) задано `NSAllowsArbitraryLoads` — часть ссылок UUP/Microsoft на загрузку идёт по **HTTP**; иначе `URLSession` блокирует загрузку. При желании позже сузить до `NSExceptionDomains` под известные CDN.

## Роли экранов и анти-дубли (UX)

С 2026-04-23 приложение переведено на **Hybrid UX**: 3 области вместо 5-шагового wizard. Primary CTA живёт только на Home.

- **Home (`HomeView`)** — адаптивный tool-screen с состояниями `.idle / .running / .done` (диктуется `EndToEndMediaPipeline.phase`). Содержит: upgrade hero (одна карточка на каждый `DriveUpgradeOffer`), форма (source toggle UUP+ISO ↔ existing ISO, build picker в sheet `FluffyBuildPickerSheet`, language/edition, список дисков multi-select), live pipeline widget (`e2e.statusLine` + `WistGlobalDownloadProgressStrip` + опционально лог writer-а в Expert mode), done card (Reveal ISO / Write another / Start new). Expert mode disclosure — 3 отдельные кнопки Download / Build / Write.
- **Library (`LibraryView`)** — сегментированный `Picker` c 4 табами: `Downloads` (UUP cache через `WistCache.listUUPFolders`), `ISOs` (сканирование `.iso` в кеше), `History` (из `WriteHistoryStore`), `Fluffy drives` (все подключённые диски с sidecar-метой + badges от `WistUSBUpgradeDetector`). Никакого CTA — только управление артефактами и история.
- **Settings (`SettingsView`)** — app language (`WistAppLanguage`), max parallel USB writes (`fluffy.maxConcurrentWrites`, 1–4), Expert mode toggle, upgrade-check toggle + интервал (`fluffy.upgradeCheckMinutes`: 15 / 60), cache paths (show / Reveal / Clear). Custom cache path — Backlog v2.
- **Единый вход в E2E** — только Home. `WorkflowBottomBar` удалён, нет дублирующихся стартеров.
- **Sidebar** — `WistArea` (home / library / settings), SF Symbols, под пунктами — динамический **upgrade pill** (показывается только когда есть `offers` и пользователь не на Home). Глобальный `WistGlobalDownloadProgressStrip` остаётся над нижним краем, независимо от области.

## Модули / слои

| Область | Файлы / папки | Роль |
|---------|----------------|------|
| Оболочка | `Fluffy Flash/RootView`, `WistApp`, `TransparentTitleBarConfigurator`, `FluffyDesignSystem` | **`ZStack`**: **`WistShellWindowBackdrop`** — обои **`BackgroundWaves`** (`Assets.xcassets`) + vignette. Слева **3 области** (`WistArea`: Home / Library / Settings) + баннер **`FluffyBanner`**, SF Symbols для областей. Динамический **upgrade pill** под sidebar-меню (из `WistUSBUpgradeDetector.offers`). Правая контент-колонка — `HomeView` / `LibraryView` / `SettingsView` (switch по `area`). Глобальный **`WistGlobalDownloadProgressStrip`** над нижним краем контента. Окно: прозрачный title bar + **`fullSizeContentView`**. `FluffyStep`, `FluffyDoneView`, `FluffyActionsSheet`, `WorkflowBottomBar`, `CreateUSBView`, `DownloadsView`, `DownloadISOView`, `WistWorkflowChrome` — удалены. |
| Home | `HomeView` | Адаптивный экран с состояниями `.idle / .running / .done`. Idle: source toggle (UUP→ISO ↔ existing ISO), build picker sheet (`FluffyBuildPickerSheet` поверх `DownloadISOViewModel`), language/edition, drive multi-select, Flash CTA с N drives. Upgrade hero — карточки из `WistUSBUpgradeDetector.offers` (1-click upgrade → `runFullPipeline` с предвыбранной сборкой или `writeExistingISOToDrives` если ISO есть в кеше). Running: `e2e.statusLine` + прогресс + опциональный лог writer-а в Expert mode. Done: Reveal ISO / Write another / Start new. Expert mode disclosure — 3 кнопки Download / Build / Write для ручного запуска отдельных этапов. После каждого завершения вызывается `WriteHistoryStore.record(...)`. |
| Library | `LibraryView`, `WriteHistoryStore` | `Picker.segmented` табы: Downloads (UUP cache, `WistCache.listUUPFolders`), ISOs (сканирование `.iso`), History (`WriteHistoryStore` из `~/Library/Application Support/FluffyFlash/write-history.json`, max 200 записей), Fluffy drives (все диски с sidecar-метой + badges). Reveal / Build ISO / Delete / Write another — без Flash CTA. |
| Settings | `SettingsView` | App language (`WistAppLanguage`), max parallel USB writes `fluffy.maxConcurrentWrites` (1–4), Expert mode `fluffy.expertMode`, Upgrade check enabled `fluffy.upgradeCheckEnabled` + interval `fluffy.upgradeCheckMinutes` (15/60), cache path (show / Reveal / Recalculate / Clear). |
| Upgrade detection | `WistUSBUpgradeDetector`, `WistUSBMetadata` | `@MainActor ObservableObject` подключается к `DiskManager` через `attach(to:)`. Группирует диски по `(arch, language, editionToken)`, кеш в `UserDefaults` с TTL из `upgradeCheckMinutes`, сеть — `UUPDumpAPI.fetchBuilds`. Публикует `[DriveUpgradeOffer]` (drive, currentMeta, latestBuild, isNewer). HomeView показывает только `isNewer == true`; Library/Fluffy drives — все, с бейджем up-to-date. |
| E2E оркестрация | `EndToEndMediaPipeline` | Состояния: загрузка UUP → `convert.sh` → ISO → запись на один или несколько USB (параллель с лимитом concurrency, по умолчанию до 3, настраивается в Settings). Использует `DownloadISOViewModel` + `USBWriterViewModel`. `writeExistingISOToDrives(isoPath:devices:)` — для сценария «ISO в кеше». |
| Метаданные носителя | `WistUSBMetadata` | JSON **`FluffyFlash.meta.json`** в корне тома после split, до `sync`/`eject` (старые флешки: **`Wist.meta.json`** / **`WinForge.meta.json`** — читаются для совместимости); поля: build, arch, language, edition, `writtenAt`, опционально путь к ISO. |
| Диски | `DiskManager` | `@MainActor`. `diskutil list/info -plist`, фильтр внешних съёмных дисков; после списка — скан `/Volumes` + чтение sidecar JSON, сопоставление с whole-disk id через `MountPoint` из `diskutil info`. Публикует `drives: [RemovableDriveInfo]` с `wistSidecarMeta`. |
| Загрузка / каталог UUP | `DownloadISOViewModel`, `UUPDumpAPI`, `UUPBuildFilters` | `DownloadISOViewModel` (`@MainActor ObservableObject`) — actor-обёртка над `UUPDumpAPI`, публикует `allBuilds` / `displayedBuilds`, фильтры, выбор сборки, прогресс загрузки и конвертации. Переиспользуется HomeView для build picker sheet и Library для Downloads таба. |
| Загрузки / кэш | `WistCache`, `UUPCacheMetadata`, `UUPISOConverter` | После успешной загрузки UUP в папку кэша пишется **`Wist.cache.json`** (название сборки, номер билда, дата, язык, редакция); таблица Library → Downloads показывает человекочитаемую колонку Build. `convertUUPFolderToISO(uupDirectory:destinationFolder:)` переносит ISO в выбранную папку через `relocateISOIfNeeded`. |
| PATH для CLI | `HostToolPaths` | Расширение `PATH` для GUI-приложения при вызове `convert.sh`. |
| Запись USB | `USBWriterViewModel` | FAT32 (`eraseDisk`), **точка монтирования тома** определяется по `diskutil info -plist` для `diskXs1/s2` (не фиксированный `/Volumes/WINSETUP` — важно для нескольких флешек). Монтирование ISO, копирование дерева, `wimlib-imagex split`, мета-JSON `FluffyFlash.meta.json`, `sync`, `eject`. Несколько задач на разных `deviceIdentifier` идут параллельно в `runUSBWritesWithConcurrencyLimit`. |
| Копирование ISO→USB | `WindowsISOFileCopy` | Обход тома и `FileManager.copyItem` (без openrsync); пропуск `install.wim`/`install.esd`, `boot.catalog`, `.DS_Store`. |
| Проверки перед копией | `ISOFat32Precheck`, `VolumeBytes` | Лимит ~4 ГиБ на файл, `find` для перекрёстной проверки, оценка свободного места (`du`/`statfs`). |
| Утилиты | `BundledToolLocator`, `HdiutilAttach` | Поиск `wimlib-imagex`, монтирование ISO через `hdiutil`. |
| Фильтры UUP | `UUPBuildFilters.swift` | Продукт / канал / архитектура (строки UI на EN + локализация), сортировка новее выше. |
| UI chrome | `WistChrome.swift`, `WistTheme+Premium.swift`, `WistSurfaceModifiers.swift` | Токены (`WistTheme` + premium canvas/neon/CTA), `MistDetailCanvas` (mesh-фон), компоненты секций, модификаторы glass/neumorphic. Material — точечно (сайдбар, нижняя панель), не на весь скролл списка. |
| Сторонний код | `ThirdParty/CrystalFetch/` | `Downloader`, клиент UUPDump, модели JSON (Apache-2.0). |
| Legal / лицензии | `10-Project-Wist/Legal.md` | Инвентарь third‑party, монетизация, требования GPL при бандлинге CLI, рекомендации по GitHub. |
| Процессы | `ProcessRunner` | Асинхронный `Process` + отмена. |

## Локализация (i18n)

- **Исходный язык в коде:** английский; комментарии и идентификаторы — только EN.
- **String Catalog:** `Localizable.xcstrings` (~232 ключа по состоянию на 2026‑04), `developmentRegion` = `en`.
- **Локали в проекте:** `en`, `es`, `zh-Hans`, `hi`, `ar`, `fr`, `he` (иврит и арабский — RTL через систему).
- **API:** `Text("…")` / `LocalizedStringKey` и `Label("…", …)` подхватывают **`.environment(\.locale, …)`** (переключатель языка в `RootView`). Обычный **`String(localized:)`** без явного `locale:` ориентируется на **системную** локаль — для строк, собираемых в коде как `String`, передавать **`locale`** из `@Environment(\.locale)` (см. `RootView`, `WorkflowBottomBar`).
- **Поток переводов:** машинный бандл `Scripts/l10n_bundle.json` генерируется **`Scripts/build_bundle_translatepy.py`** (translatepy, чекпоинты в `l10n_bundle.partial.json`, таймаут на запрос, при пустом ответе — подстановка EN). Ручные правки и точечные переопределения — в таблице **`T`** внутри **`Scripts/build_localizable_xcstrings.py`** (она перекрывает бандл по совпадающим ключам). Регенерация каталога: `python3 Scripts/build_localizable_xcstrings.py` из каталога `Wist` с исходниками; затем закоммитить обновлённый `.xcstrings`.

## Внешние системы

- **[uupdump.net](https://uupdump.net)** JSON API — список сборок, языки, редакции, пакет файлов.
- **HTTPS** — загрузка кусков UUP (resume через `URLSession`).
- **Локально:** `/usr/sbin/diskutil`, `/usr/bin/hdiutil`, `/usr/bin/du`, `/usr/bin/find`, `wimlib-imagex` (Homebrew или `Resources/Tools/` в бандле).

## Решения (ADR)

- [[Decisions/001-sandbox-and-third-party|001 — Sandbox и CrystalFetch]]

## Документация и Cursor

- Заметки проекта в Obsidian: **`ObsidianVault`** в корне репозитория; симлинк **`docs/vault`** указывает на тот же каталог (удобно, если ожидается путь вида `docs/…`). См. **`ObsidianVault/README.md`** — как открыть vault, папки `00-Inbox`, `Templates`, `attachments`, настройки `.obsidian/`.
- Навыки ассистента в **`.cursor/skills/`**: `wist-xcode`, `obsidian-wist-vault`, `ui-ux-pro-max`; с GitHub (Paul Hudson, MIT): **`swiftui-pro`**, **`swift-concurrency-pro`**, **`swift-testing-pro`** — см. `.cursor/skills/README.md`.
- Подпись Apple / Bundle ID: **`Wist/docs/Signing.md`** (настройка под личный или командный аккаунт).

## Открытые вопросы

- Подпись и **Disable Library Validation** для встроенных бинарей (как в CrystalFetch README), если кладём `wimlib-imagex` в бандл.
- Legal: bundled tools (GPL) + риск `cdrtools/mkisofs` → предпочтительно заменить на `genisoimage`/cdrkit или другой ISO builder (см. [[Legal]]).
- При **параллельной** записи на несколько USB с **одним** ISO каждый `writeWindowsInstaller` делает свой `hdiutil attach` — выше нагрузка на диск; возможный рефакторинг: один mount ISO и копирование на несколько томов по очереди или с координацией.
- Отмена долгой конвертации ISO (сейчас есть отмена загрузки UUP).
