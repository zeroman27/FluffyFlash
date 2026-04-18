# Бэклог

Используйте теги: `#feature` `#bug` `#tech-debt` `#research`.

## Входящие

- #feature Локальный выбор `.iso` и расширенная проверка целостности (хеш и т.д.).
- #feature UI: отдельная строка прогресса/лога на каждую активную задачу записи USB (сейчас общий журнал).
- #tech-debt Рефактор: `DiskManager` через общий раннер процессов (опционально).
- #tech-debt Один общий `hdiutil attach` при параллельной записи одного ISO на несколько USB.
- #research Сравнение путей: только Microsoft CDN vs UUP-only.

## В работе

- См. раздел «Дальше» в [[Roadmap]] (релиз GitHub).

## Готово (последнее)

- **UI / производительность Source:** кэш `displayedBuilds`, debounce строки поиска, `MistOpenSection` + плоские строки списка; убраны `thinMaterial` / `ultraThinMaterial` из карточек, hero, сайдбара и нижней панели (`WistChrome`, `RootView`, `WorkflowBottomBar`). Детали — [[Sessions/2026-04-16]].
- **Локализация:** EN в коде, `Localizable.xcstrings`, локали es / zh-Hans / hi / ar / fr / he; бандл `l10n_bundle.json` + генераторы в `Scripts/` (см. [[Architecture]], [[Sessions/2026-04-18]]).
- Запись загрузочной USB: нативное копирование (`WindowsISOFileCopy`), split `install.wim` через `wimlib-imagex`, журнал + Copy log (в т.ч. `lastError`).
- Phase 1: `NavigationSplitView`, `DiskManager`, отключение Sandbox.
- Встраивание CrystalFetch: `Downloader` + UUPDump + UI загрузки UUP в кэш.
- `ProcessRunner`, `THIRD_PARTY.md`.
- **E2E:** `EndToEndMediaPipeline`, кнопка Run all, `WorkflowBottomBar`, степпер шагов в `RootView`.
- **USB:** мультивыбор, параллельная запись с лимитом, `Wist.meta.json`, определение точки монтирования через `diskutil`.
- **UX:** primary-кнопки `.borderedProminent` на ключевых действиях (загрузка, языки, сборка ISO, запись).

---

[[Roadmap]] · [[Sessions/_template|Шаблон сессии]]
