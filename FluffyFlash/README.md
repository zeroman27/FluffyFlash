# Wist

macOS (SwiftUI) — загрузка UUP через [UUPDump](https://uupdump.net), запись загрузочной Windows USB (FAT32 + `wimlib-imagex split`).

## Требования

- Xcode 16+ / macOS 26+ (см. deployment target в проекте).
- **Запись USB:** `wimlib-imagex` в PATH или `Resources/Tools/wimlib-imagex` в бандле.

```bash
brew install wimlib
```

- **UUP → ISO и запись USB:** в собранном `.app` лежат **встроенные** CLI и `.dylib` (`Contents/Resources/` и `Resources/lib`). Конечному пользователю **ничего не ставить**.
- **Сборка в Xcode:** фаза **«Bundle Embedded CLI Tools»** ставит пакеты через Homebrew и копирует бинарники в `Wist/Tools/bin`, а `.dylib` — в **`EmbeddedCLI/lib`** (вне папки исходников, иначе Xcode сам добавляет их в линковку приложения). Фаза **«Embed Tools dylibs»** копирует библиотеки в `Contents/lib` внутри `.app`. Нужны [Homebrew](https://brew.sh) и сеть при первой установке пакетов. `WIST_SKIP_TOOL_BUNDLE=1` — пропустить фазу и положить файлы вручную.

```bash
# Ручной запуск того же скрипта (необязательно — делает и Xcode)
./Scripts/bundle-mac-cli-tools.sh
```

## Сборка

Откройте `Wist.xcodeproj`, схема **Wist**, Run.

### Подпись и Bundle Identifier

Чтобы привязать приложение к **своему Apple ID / команде** и задать **Bundle ID** (и тестовые идентификаторы), следуйте [docs/Signing.md](docs/Signing.md). В коде Bundle ID не захардкожен — всё настраивается в Xcode.

## Лицензии

Исходный код Wist распространяется под **Apache License 2.0** (см. `LICENSE`). Фрагменты из [CrystalFetch](https://github.com/TuringSoftware/CrystalFetch) помечены в заголовках файлов; см. `THIRD_PARTY.md`.

## Безопасность

- App Sandbox отключён (нужны `diskutil`, `hdiutil`, `rsync`, внешние URL).
- В `App-Info.plist` включён `NSAllowsArbitraryLoads` — часть ссылок Microsoft на загрузку идёт по HTTP.
