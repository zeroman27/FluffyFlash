# Skills для проекта Wist

## Сравнение без дублирования

| Навык | Что даёт | Когда открывать |
|--------|-----------|-----------------|
| **wist-xcode** | Проект, `xcodebuild`, скрипты, подпись | Сборка, пути, CI |
| **obsidian-wist-vault** | Vault, Roadmap, Architecture, сессии | После существенных изменений продукта |
| **swiftui-pro** | Ревью SwiftUI: API, навигация, данные, **HIG**, a11y, перф | Пишем или ревьюим SwiftUI-код |
| **swift-concurrency-pro** | async/await, actors, Sendable | Асинхронность и изоляция |
| **swift-testing-pro** | Swift Testing | Тесты |
| **ui-ux-pro-max** | Скрипт `search.py`: дизайн-системы, стили, палитры, домены UX, **`--stack swiftui`** | Нужны **подбор стиля/палитры/гайдов по стеку**, чеклисты «профессионального» UI (часть правил — **веб**, см. ниже) |
| **ui-design-brain** | **60+ смысловых компонентов** ([components.md](ui-design-brain/components.md)): когда какой паттерн, раскладки, состояния, анти-паттерны | Проектируем **состав экрана** и поведение (не синтаксис Swift) |

### Как skills не конкурируют

- **ui-design-brain** отвечает на вопрос *«из каких смысловых блоков собрать экран и какие у них правила»* (таблица vs карточка, модальный сценарий, пустое состояние). Реализация — только через **SwiftUI** по **swiftui-pro**.
- **ui-ux-pro-max** отвечает на вопрос *«какая визуальная система / поиск по базе стилей / stack guidelines»*. Для кода на SwiftUI использовать флаг **`--stack swiftui`**, а не дефолт `html-tailwind`.
- Чеклист в конце **ui-ux-pro-max/SKILL.md** (emoji вместо иконок, `cursor-pointer`, брейкпоинты 375px…) заточен под **веб**. Для **macOS** применять смысл (контраст, фокус, hover), а не CSS-конкретику.
- **swiftui-pro** уже покрывает **Apple HIG** и типичные ошибки вью — не копируйте те же формулировки в новые правила; при споре приоритет у **swiftui-pro** для кода.

## Локальные папки (репозиторий)

| Папка | Происхождение |
|-------|----------------|
| `wist-xcode`, `obsidian-wist-vault` | Проектные |
| `ui-ux-pro-max` | [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) (данные + скрипты) |
| `ui-design-brain` | [carmahhawwari/ui-design-brain](https://github.com/carmahhawwari/ui-design-brain) — `components.md` + `LICENSE.txt`; **SKILL.md** адаптирован под Wist (macOS SwiftUI) |

## Установлено с GitHub (MIT) — Paul Hudson / сообщество

Источник: [Swift Agent Skills](https://github.com/twostraws/swift-agent-skills).

| Папка | Репозиторий |
|-------|----------------|
| `swiftui-pro` | [twostraws/swiftui-agent-skill](https://github.com/twostraws/swiftui-agent-skill) |
| `swift-concurrency-pro` | [twostraws/Swift-Concurrency-Agent-Skill](https://github.com/twostraws/Swift-Concurrency-Agent-Skill) |
| `swift-testing-pro` | [twostraws/Swift-Testing-Agent-Skill](https://github.com/twostraws/Swift-Testing-Agent-Skill) |

В текстах скиллов иногда упоминается iOS — проект **macOS**; правила применимы к SwiftUI на Mac.

**Обновление:** заменить каталог соответствующего skill свежим клоном или `git pull` в клоне и скопировать папку.

**Заметка:** внутри `swiftui-pro` может дублироваться вложенная копия (`skills/swiftui-pro/`) — артефакт апстрима; на работу Cursor это обычно не влияет.
