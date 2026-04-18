# Дорожная карта

## Сейчас (текущий фокус)

- [x] **Запись USB:** `eraseDisk` (FAT32) → `hdiutil attach` ISO → проверки размеров/места → **`WindowsISOFileCopy`** (FileManager, без rsync) → `wimlib-imagex split` → опционально **`Wist.meta.json`** → отмонтирование ISO → `sync` → `eject`. Точка монтирования USB берётся из `diskutil` (не жёстко `/Volumes/WINSETUP`).
- [x] **Выбор локального `.iso`** на экране «Создание USB».
- [x] **Экран Downloads** — статус UUP, кэш, **Build ISO** через встроенный `convert.sh` (uup-dump/converter), лог, путь к `.iso`.
- [x] **ISO из UUP внутри приложения:** бандл `ThirdParty/UUPConverter/convert.sh` + Homebrew-зависимости (см. README).
- [x] **Остановка загрузки UUP** — кнопка Stop + отмена задач в `Downloader`.
- [x] **E2E цепочка** — `EndToEndMediaPipeline`: UUP → ISO → запись на один или несколько USB; главная кнопка **Run all** в нижней панели (`WorkflowBottomBar`).
- [x] **UX маршрута** — общий степпер в detail (`MistPipelineNumbered`), нижний CTA-бар, мультивыбор USB на экране Create USB.
- [x] **Метаданные на флешке** — чтение при `DiskManager.refresh`, карточка Wist drives + **Update to selected build** (ISO из кэша или полная цепочка).
- [x] **Параллельная запись** — ограниченный параллелизм (TaskGroup), отдельные mount ISO на задачу (компромисс по нагрузке).
- [x] **Производительность экрана Source** — кэш отфильтрованного списка + debounce поиска в `DownloadISOViewModel`; плоские строки/карточки и отказ от SwiftUI Material в общем chrome (`WistChrome`, `RootView`, `WorkflowBottomBar`); см. [[Sessions/2026-04-16]].

## Дальше

- [ ] Подготовка релиза на GitHub (релизные артефакты, описание, возможно notarization позже).
- [x] **Полный охват строк в каталоге:** `l10n_bundle.json` (автоперевод) + таблица `T` для ручных правок → `build_localizable_xcstrings.py` → `Localizable.xcstrings`. При необходимости улучшить формулировки отдельно по языкам (не блокер релиза).
- [ ] Опционально: отмена долгой конвертации ISO (сейчас только остановка скачивания).
- [ ] Опционально: отдельный лог/прогресс по каждой задаче записи в UI (`MistProProgress` по строкам).

## Потом / идеи

- Опционально: каталог ESD/Microsoft (как второй путь к образу).
- Polling или уведомления при подключении USB.
- Один общий mount ISO при параллельной записи на несколько носителей (см. [[Architecture]]).

## Релизы / вехи

| Веха | Ориентир | Статус |
|------|----------|--------|
| Phase 1: UI + `DiskManager` + без Sandbox | — | Готово |
| Интеграция UUPDump + Downloader (CrystalFetch) | — | Готово |
| MVP: загрузочная USB из ISO | — | Готово |
| MVP: один ISO из UUP в приложении | — | Готово |
| UX: степпер + нижний CTA + E2E Run all | — | Готово |
| Локализация: `Localizable.xcstrings`, 7 языков (en + es, zh-Hans, hi, ar, fr, he), скрипт регенерации | — | Готово |
| Метаданные USB + обнаружение носителя | — | Готово |

---

Ссылки: [[Vision]] · [[Backlog]] · [[Architecture]] · [[Sessions/2026-04-14|Сессия 2026-04-14]] · [[Sessions/2026-04-15|Сессия 2026-04-15]] · [[Sessions/2026-04-16|Сессия 2026-04-16]] · [[Sessions/2026-04-18|Сессия 2026-04-18]]
