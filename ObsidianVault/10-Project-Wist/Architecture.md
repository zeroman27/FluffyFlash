# Архитектура Wist

> Высокоуровнево: модули, платформа, важные зависимости. Детали кода — в Xcode.

## Платформа

- macOS 26.x (deployment target из проекта), Swift 5, SwiftUI.
- **App Sandbox отключён** (`ENABLE_APP_SANDBOX = NO`) — нужен `Process` + `diskutil` / `hdiutil` / `wimlib-imagex` (копирование ISO→USB — **не** rsync, см. ниже).
- **ATS:** в `App-Info.plist` (корень проекта Xcode, не в синхронизированной папке исходников) задано `NSAllowsArbitraryLoads` — часть ссылок UUP/Microsoft на загрузку идёт по **HTTP**; иначе `URLSession` блокирует загрузку. При желании позже сузить до `NSExceptionDomains` под известные CDN.

## Модули / слои

| Область | Файлы / папки | Роль |
|---------|----------------|------|
| Оболочка | `RootView`, `WorkflowBottomBar`, `WistApp` | `NavigationSplitView`: **Download ISO**, **Downloads**, **Create USB** (в коде и каталоге — EN; см. ниже про l10n). В detail — степпер `MistPipelineNumbered` (**Source → Cache & ISO → Media**); снизу — **Run all** (цепочка E2E). Сайдбар и нижняя панель — **без SwiftUI Material** (плоские заливки `WistTheme`), чтобы снизить нагрузку на glass/`NSHostingView` на macOS. |
| E2E оркестрация | `EndToEndMediaPipeline` | Состояния: загрузка UUP → `convert.sh` → ISO → запись на один или несколько USB (параллель с лимитом concurrency, по умолчанию до 3). Использует `DownloadISOViewModel` + `USBWriterViewModel`. |
| Метаданные носителя | `WistUSBMetadata` | JSON **`Wist.meta.json`** в корне тома после split, до `sync`/`eject` (старые флешки: **`WinForge.meta.json`** — читается для совместимости); поля: build, arch, language, edition, `writtenAt`, опционально путь к ISO. |
| Диски | `DiskManager` | `diskutil list/info -plist`, фильтр внешних съёмных дисков; после списка — скан `/Volumes` + чтение sidecar JSON, сопоставление с whole-disk id через `MountPoint` из `diskutil info`. |
| Загрузка образа | `DownloadISOView`, `DownloadISOViewModel` | Каталог сборок (UUP): фильтры, список с подтверждением выбора → загрузка языков/редакций → скачивание UUP. Подзаголовок объясняет, что `.iso` собирается на шаге **Downloads**. Режим **Full flow to USB** на том же экране: выбор USB + **Run full pipeline** (нижняя панель **Run all** на этом шаге скрыта). **Производительность Source:** `displayedBuilds` — кэш в модели + пересчёт при смене фильтров; **поиск** — debounce ~280 ms; длинный список — `MistOpenSection` + строки `UUPBuildRow` с плоским фоном (не Material). Карточки секций на экране используют общий стиль `MistSectionCard` — тоже без Material (см. `WistChrome`). |
| Загрузки / кэш | `DownloadsView`, `WistCache`, `UUPCacheMetadata` | Статус UUP, кэш, **Build ISO** (`UUPISOConverter` + `ThirdParty/UUPConverter/convert.sh`). После успешной загрузки UUP в папку кэша пишется **`Wist.cache.json`** (название сборки, номер билда, дата из каталога, язык, редакция) — таблица на экране **Downloads** показывает человекочитаемую колонку **Build**; для папок `*-iso-build` метаданные подтягиваются из соседней папки с тем же UUID. |
| PATH для CLI | `HostToolPaths` | Расширение `PATH` для GUI-приложения при вызове `convert.sh`. |
| Запись USB | `CreateUSBView`, `USBWriterViewModel` | FAT32 (`eraseDisk`), **точка монтирования тома** определяется по `diskutil info -plist` для `diskXs1/s2` (не фиксированный `/Volumes/WINSETUP` — важно для нескольких флешек). Монтирование ISO, копирование дерева, `wimlib-imagex split`, опционально мета-JSON, `sync`, `eject`. Несколько задач на разных `deviceIdentifier` могут идти параллельно; общий лог по-прежнему один поток (для отдельных логов по задачам — возможный долг). |
| Копирование ISO→USB | `WindowsISOFileCopy` | Обход тома и `FileManager.copyItem` (без openrsync); пропуск `install.wim`/`install.esd`, `boot.catalog`, `.DS_Store`. |
| Проверки перед копией | `ISOFat32Precheck`, `VolumeBytes` | Лимит ~4 ГиБ на файл, `find` для перекрёстной проверки, оценка свободного места (`du`/`statfs`). |
| Утилиты | `BundledToolLocator`, `HdiutilAttach` | Поиск `wimlib-imagex`, монтирование ISO через `hdiutil`. |
| Фильтры UUP | `UUPBuildFilters.swift` | Продукт / канал / архитектура (строки UI на EN + локализация), сортировка новее выше. |
| UI chrome | `WistChrome.swift` | Токены темы, `MistSectionCard` / `MistOpenSection`, `MistDetailCanvas`, `MistPageHeader`, `MistHeroBackground` — оформление без системного «стекла» (Material), чтобы не раздувать слои и AttributeGraph на больших списках. |
| Сторонний код | `ThirdParty/CrystalFetch/` | `Downloader`, клиент UUPDump, модели JSON (Apache-2.0). |
| Процессы | `ProcessRunner` | Асинхронный `Process` + отмена. |

## Локализация (i18n)

- **Исходный язык в коде:** английский; комментарии и идентификаторы — только EN.
- **String Catalog:** `Localizable.xcstrings` (~202 ключа по состоянию на 2026‑04), `developmentRegion` = `en`.
- **Локали в проекте:** `en`, `es`, `zh-Hans`, `hi`, `ar`, `fr`, `he` (иврит и арабский — RTL через систему).
- **API:** `String(localized:)`, `String(format: String(localized:), …)` для подстановок.
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
- При **параллельной** записи на несколько USB с **одним** ISO каждый `writeWindowsInstaller` делает свой `hdiutil attach` — выше нагрузка на диск; возможный рефакторинг: один mount ISO и копирование на несколько томов по очереди или с координацией.
- Отмена долгой конвертации ISO (сейчас есть отмена загрузки UUP).
