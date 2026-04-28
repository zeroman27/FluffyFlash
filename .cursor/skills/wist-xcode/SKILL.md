---
name: wist-xcode
description: >-
  Wist macOS app: where the Xcode project lives, schemes, build scripts,
  EmbeddedCLI bundling, and SwiftUI source layout. Use for Xcode, xcodebuild,
  or native macOS development in this repo.
---

# Wist — Xcode и структура

## Где проект

- **Проект Xcode**: `FluffyFlash/Fluffy Flash.xcodeproj` (относительно корня репозитория; каталог `FluffyFlash/` — корень Xcode рядом с `ObsidianVault`).
- **Схема**: `FluffyFlash` (macOS application; отображаемое имя в системе — **Fluffy Flash**).
- Исходники синхронизируются через **File System Synchronized Groups** — папка `FluffyFlash/Fluffy Flash/` целиком в таргете.

## Сборка из терминала

```bash
cd FluffyFlash
xcodebuild -project "Fluffy Flash.xcodeproj" -scheme FluffyFlash -configuration Debug -destination 'platform=macOS' build
```

Пропуск упаковки CLI-инструментов (если нужно ускорить сборку):

```bash
WIST_SKIP_TOOL_BUNDLE=1 xcodebuild ...
```

## Скрипты и артефакты

- `FluffyFlash/Scripts/bundle-mac-cli-tools.sh` — фаза **Bundle Embedded CLI Tools** (PATH: `/opt/homebrew/bin`, `/usr/local/bin`).
- `FluffyFlash/EmbeddedCLI/lib` — копируется в приложение фазой **Embed Tools dylibs** (`Contents/lib` и зеркало в Resources).

## Тесты

- Юнит: таргет `WistTests`, папка `WinMist/WistTests/`.
- UI: `WistUITests`, папка `WinMist/WistUITests/`.

## Не создавать «новый проект» в Xcode

Репозиторий уже содержит валидный `.xcodeproj`. На новом Mac достаточно установить Xcode, открыть `Wist.xcodeproj` и собрать. Дублировать проект с нуля не нужно.

## Подпись и Bundle ID

Подробно: `FluffyFlash/docs/Signing.md`. Идентификаторы задаются в таргетах (**Signing & Capabilities**), в Swift не дублируются. Три разных `PRODUCT_BUNDLE_IDENTIFIER`: приложение, `FluffyFlashTests`, `FluffyFlashUITests`.
