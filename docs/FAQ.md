# FAQ / Troubleshooting

## DMG “rejected / Insufficient Context” в `spctl --type open`

Это часто неинформативная проверка для DMG. Правильная проверка:

- `xcrun stapler validate <dmg>`
- смонтировать DMG и проверить `.app` внутри: `spctl -a -vv --type execute "<Volume>/FluffyFlash.app"`

## “Bad CPU type in executable” при сборке ISO / загрузке installers / IPSW (Intel Macs)

Это означает, что приложение пытается запустить CLI‑инструмент **не той архитектуры** (например, `arm64` на Intel `x86_64`).

Проверка:

- `file "/Applications/FluffyFlash.app/Contents/Resources/aria2c"`
- `file "/Applications/FluffyFlash.app/Contents/Resources/wimlib-imagex"`
- `file "/Applications/FluffyFlash.app/Contents/Resources/mist" 2>/dev/null || true`

Если внутри `.app` лежат `arm64` бинарники, ISO/Installers/IPSW на Intel работать не будут. Поддержка Intel планируется отдельно (и требует правильной упаковки toolchain).

## Где лежат bundled инструменты

В релизных сборках инструменты могут лежать в:

- `FluffyFlash.app/Contents/Resources/Tools/bin` (предпочтительно)
- или быть “плоско” в `FluffyFlash.app/Contents/Resources/<tool>`
- библиотеки для них — обычно в `FluffyFlash.app/Contents/lib`

Подробности для разработчиков: [`FluffyFlash/README.md`](../FluffyFlash/README.md).

