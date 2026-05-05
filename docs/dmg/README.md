# DMG background (drag-to-Applications)

| File | Size | Notes |
|------|------|--------|
| [`background.png`](background.png) | сейчас **1024×681** (логотип + стрелка) | Скрипт пересэмплит под **660×439** px при `WINW=660`. Иконки **~18% / ~81%**; подправка: `DMG_ICON_APP_X`, `DMG_ICON_APPS_X`, `DMG_ICON_Y`. |

**Типичные «канвасы» из интернета (pt):** **540×380** или **660×440** — это **размер окна Finder в пунктах**, не обязательно пиксели PNG. У нас по умолчанию **ширина 660 pt**, высота контента **≈439 pt** + полоса заголовка → внешне **660×467**. Можно: `DMG_WINDOW_WIDTH=540 ./Scripts/build_dmg.sh` (внутренняя высота пересчитается из aspect картинки).

**Экспорт из Figma:** кадр с пропорциями как у **1320×878**; проверка: `sips -g pixelWidth -g pixelHeight file.png`.

**Стрелка «перетащи в Applications»:** встроить в **сам фон** (`create-dmg` не рисует стрелку между иконками — только позиционирует `.app` и ярлык **Applications**).

## Matching the Finder window (целиком в окне, без «зума»)

Finder часто кладёт фон так, что **1 px картинки ≈ 1 pt области контента**. Тогда PNG **1320 px** шириной в окне **~660 pt** выглядит **вдвое увеличенным** (видна только часть кадра).

Скрипт [`FluffyFlash/Scripts/build_dmg.sh`](../../FluffyFlash/Scripts/build_dmg.sh) по умолчанию (`DMG_BG_PIXEL_MODE=window`):

1. Считает **INNER_H** = высота контента в pt при ширине **WINW** и aspect исходника.
2. Ресемплит фон в **`WINW × INNER_H` пикселей** (например **660×439**), выставляет **72 dpi** подсказку.
3. Задаёт высоту окна **`INNER_H + DMG_TITLEBAR_PT`** (по умолчанию +**28** pt под title bar).

Старый режим «Retina @2x картинка»: `DMG_BG_PIXEL_MODE=retina2x ./Scripts/build_dmg.sh` (как раньше `WINW×2` по ширине).

Ширина окна: `DMG_WINDOW_WIDTH=540 ./Scripts/build_dmg.sh`. Иконки: координаты как у примеров create-dmg для **660×400**, масштаб по **OUTER_H**.

## Automated build (repository script)

From the **`FluffyFlash`** directory (after adjusting `FLUFFYFLASH_APP` if your `.app` lives elsewhere):

```bash
brew install create-dmg   # once
export FLUFFYFLASH_APP="$HOME/path/to/FluffyFlash.app"   # optional
./Scripts/build_dmg.sh
```

Output: **`FluffyFlash/ReleaseArtifacts/FluffyFlash.dmg`** (that folder is gitignored — copy the DMG elsewhere for distribution).

## Manual `create-dmg` example

```bash
brew install create-dmg

create-dmg \
  --volname "Fluffy Flash" \
  --background "docs/dmg/background.png" \
  --window-size 512 341 \
  --icon-size 96 \
  --app-drop-link 380 170 \
  --icon "FluffyFlash.app" 140 170 \
  "FluffyFlash-0.1.0.dmg" \
  "/path/to/staging-folder-containing-app"
```

Coordinates (`--icon`, `--app-drop-link`) place the **app** on the left and the **Applications** link on the right; tweak until they sit in the clear central band of your art.

## Notarization

Build the DMG **after** the `.app` is signed (and stapled if you distribute outside the Mac App Store). Submit the **`.dmg`** (or a zip of the app — either works) with `notarytool`; then staple the **DMG** if Apple documents staple for that artifact type, or staple the **`.app`** before sealing inside the DMG — follow your release checklist in [`RELEASING.md`](../RELEASING.md).
