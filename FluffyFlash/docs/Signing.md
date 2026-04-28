# Подпись, Bundle Identifier и метаданные

В Swift-коде Bundle ID **нигде не зашит** — он задаётся в настройках таргетов Xcode (`PRODUCT_BUNDLE_IDENTIFIER`). Достаточно один раз настроить проект под ваш Apple ID / команду.

## 1. Что вы задаёте сами

| Поле | Где в Xcode | Заметки |
|------|-------------|---------|
| **Team** (команда разработчика) | Target **Wist** → *Signing & Capabilities* → **Team** | Нужен Apple ID с программой Developer (бесплатно для личной подписи) или платный аккаунт для распространения. |
| **Bundle Identifier** (приложение) | Тот же экран, поле **Bundle Identifier** | Обратный DNS: `com.вашдомен.Wist` (латиница, без пробелов). Должен быть **уникальным** в экосистеме Apple для публикации. |
| **Тестовые таргеты** | Targets **WistTests**, **WistUITests** → *Signing* | Свои Bundle ID, **отличные** от основного приложения. Текущая схема в репозитории: суффиксы `WistTests` и `WistUITests` к тому же префиксу (например `com.вашдомен.WistTests`). |

После выбора **Team** с включённым **Automatically manage signing** Xcode сам создаст/привяжет provisioning profiles (для локального запуска на своём Mac этого достаточно).

**Team ID** (строка вида `A1B2C3D4E5`) можно посмотреть на [developer.apple.com](https://developer.apple.com/account) → *Membership details*, либо он появится в проекте как `DEVELOPMENT_TEAM` после сохранения настроек.

## 2. Версии и copyright (при желании)

В **Build Settings** таргета **Wist**:

| Ключ | Назначение |
|------|------------|
| **Marketing Version** (`MARKETING_VERSION`) | Версия для пользователя (например `1.0`). |
| **Current Project Version** (`CURRENT_PROJECT_VERSION`) | Сборка (целое число, растёт при каждой загрузке в TestFlight/App Store). |
| **Info.plist Values** → *Human Readable Copyright* | Соответствует `INFOPLIST_KEY_NSHumanReadableCopyright` — строка вида `Copyright © 2026 Ваше имя`. |

Сейчас copyright в настройках пустой; для публичного релиза лучше заполнить.

## 3. Где это лежит в файлах

Если правите не через UI, смотрите `WinMist/Wist.xcodeproj/project.pbxproj`:

- `PRODUCT_BUNDLE_IDENTIFIER` — для каждого из трёх таргетов (Debug/Release);
- при сохранении подписи Xcode добавит **`DEVELOPMENT_TEAM`**;
- `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `INFOPLIST_KEY_*` — в секциях *XCBuildConfiguration*.

`App-Info.plist` содержит только ATS; основной `Info.plist` для приложения **генерируется** (`GENERATE_INFOPLIST_FILE = YES`), идентификатор подставляется из `PRODUCT_BUNDLE_IDENTIFIER`.

## 4. Распространение (не только «Run» на своём Mac)

- **Нотаризация и выкладка наружу** — нужен **платный** Apple Developer Program, корректный **Developer ID** / продуктовая подпись и, при необходимости, записи в App Store Connect.
- Для **TestFlight** / **Mac App Store** Bundle ID должен совпадать с зарегистрированным **App ID** в [Identifiers](https://developer.apple.com/account/resources/identifiers/list).

## 5. Репозиторий и чужие машины

Идентификаторы и Team часто **личные**. После настройки у вас в `project.pbxproj` может появиться `DEVELOPMENT_TEAM`. Если делитесь кодом публично — либо оставляйте нейтральные placeholder’ы и документируйте шаги (этот файл), либо используйте локальный незакоммиченный override (например `xcconfig` в `.gitignore`) — по желанию можно вынести позже.
