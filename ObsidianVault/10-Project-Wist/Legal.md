# Legal (лицензии, монетизация, GitHub)

> Не юридическая консультация. Цель заметки — инвентаризация и практический чеклист комплаенса для релизов Wist/Fluffy Flash.

## 1) Базовая лицензия проекта

- **Wist / Fluffy Flash — Apache License 2.0** (см. `LICENSE`, `FluffyFlash/LICENSE`).
- **Что это даёт**:
  - можно **монетизировать** (продажа, подписка, донаты) и **распространять проприетарные сборки**;
  - можно держать часть кода закрытой (если появятся приватные модули) — Apache-2.0 это допускает;
  - обязательства: сохранять копию лицензии, атрибуции; отмечать изменённые файлы при распространении производных исходников.

## 2) Инвентарь third-party (на 2026‑04‑27)

### 2.1 Скопированный исходный код (в репозитории)

- **CrystalFetch (Apache-2.0)**  
  Файлы: `FluffyFlash/Fluffy Flash/ThirdParty/CrystalFetch/**`  
  Источник: `https://github.com/TuringSoftware/CrystalFetch`  
  Требования: сохранять Apache‑хедеры/атрибуции; при наличии upstream `NOTICE` — переносить релевантное (если будем бандлить NOTICE в дистрибутив).

- **UUP converter `convert.sh` (MIT License)**  
  Указано в `FluffyFlash/THIRD_PARTY.md`: `Fluffy Flash/ThirdParty/UUPConverter/convert.sh`  
  Upstream: `https://git.uupdump.net/uup-dump/converter`  
  Лицензия upstream: MIT (см. `converter/LICENSE`).

### 2.2 Встроенные CLI в `.app` (в релизах / опционально)

В релизных сборках (или у мейнтейнеров) в `Resources/Tools/bin` могут оказаться:

- **aria2c** — GPL‑2.0‑or‑later  
- **cabextract** — GPL‑3.0‑or‑later  
- **wimlib-imagex (wimlib)** — GPL‑3.0‑or‑later  
- **chntpw** — GPL‑2.0 (пакет может включать части под LGPL для библиотек)  
- **mist** (mist-cli) — MIT  
- **mkisofs** — сейчас берётся из Homebrew `cdrtools` (в Homebrew формула помечена как **CDDL‑1.0**)

Истина для нашей сборки: `FluffyFlash/Scripts/bundle-mac-cli-tools.sh` (устанавливает `aria2`, `cabextract`, `wimlib`, `cdrtools`, `mist-cli`, `chntpw`).

## 3) Монетизация: что можно / что нельзя (в рамках лицензий)

### 3.1 Можно (безопасные сценарии)

- **Продавать приложение** (Apache‑2.0 это разрешает).
- **Брать деньги за сборки/дистрибуцию/поддержку/подписку**.
- **Бандлить MIT/Apache компоненты** (CrystalFetch, uup-dump converter, mist-cli) — при условии сохранения license/attribution.
- **Использовать GPL‑инструменты как отдельные программы** (запуск отдельным процессом), при условии выполнения требований GPL к их распространению.

### 3.2 Триггеры обязательств (важно для bundled CLI)

Если мы **распространяем** `.app`, внутри которого лежат GPL‑бинарники (aria2/cabextract/wimlib/chntpw), то для каждого такого инструмента нужно:

- включить **текст лицензии** (COPYING/GPL) и **copyright notices**;
- предоставить **соответствующий исходный код** (corresponding source) *для этой версии*, которую мы распространяем, либо валидную письменную оффер‑модель (обычно проще и надёжнее — отдавать исходники рядом ссылкой/архивом);
- при наличии патчей — также исходники наших модификаций.

При этом наличие GPL‑бинарника рядом в бандле **не обязано** автоматически «заражать» лицензию нашего Swift‑приложения, если это **отдельные программы**, а не линковка/встраивание библиотек в наш бинарь. Но комплаенс по GPL‑частям обязателен.

## 4) GitHub / “насколько открывать код”

### 4.1 Публикация исходников Wist под Apache‑2.0

- Мы **можем** выложить весь код на GitHub под Apache‑2.0 (это уже сделано на уровне `LICENSE`).
- Мы **не обязаны** открывать что‑то сверх того, что мы и так публикуем, *если* не используем strong‑copyleft в виде линковки библиотек в наш бинарь.

### 4.2 Если мы бандлим GPL‑инструменты в релизах

- Код приложения **может оставаться Apache‑2.0**, но:
  - мы должны рядом с релизом дать **Third‑Party Notices** + **исходники** (или чёткий способ их получить) для GPL‑инструментов;
  - в идеале — отдельный архив/репозиторий `w1st-third-party-sources` с pinned версиями.

### 4.3 Практическая рекомендация по GitHub-структуре

- `LICENSE` (Apache‑2.0) — уже есть.
- `FluffyFlash/THIRD_PARTY.md` — **release‑ready** инвентарь: что бандлим + обязательства + где upstream/source.
- Для релизов: `FluffyFlash/THIRD_PARTY_NOTICES.txt` и source‑bundle как release asset.
- Скрипт подготовки артефактов релиза (notices + версии + исходники): `FluffyFlash/Scripts/build_third_party_sources_bundle.sh`.

## 5) Риски / спорные места

### 5.1 `cdrtools` / `mkisofs`

В Homebrew `cdrtools` помечен как **CDDL‑1.0**. Исторически вокруг `cdrtools/mkisofs` есть спор о смешении CDDL/GPL в бинарных дистрибутивах (разные дистрибутивы Linux уходили на `cdrkit`/`genisoimage`).

**Рекомендация для снижения риска:**  
перестать бандлить `mkisofs` из `cdrtools`, перейти на:

- `genisoimage` из **cdrkit (GPL‑2.0)**, или
- другой ISO-генератор с понятной лицензией/комплаенсом.

## 6) Чеклист перед публичным релизом (.app)

- [ ] Зафиксировать точный список bundled tools (имена + версии + откуда взято).
- [ ] Для каждого third‑party: лицензия, ссылка на upstream, копия license-текста в дистрибутиве.
- [ ] Для **GPL‑tools**: приложить **исходники именно тех версий**, которые реально лежат в релизе (или валидный оффер) + наши патчи (если есть).
- [ ] Подготовить `Third‑Party Notices` экран/раздел в приложении или файл в `.app` (минимум — в дистрибутиве рядом).
- [ ] Пройтись по `FluffyFlash/THIRD_PARTY.md` и убедиться, что он соответствует фактическому содержимому релиза.
- [ ] Сгенерировать артефакты: `FluffyFlash/THIRD_PARTY_NOTICES.txt` + `third-party-sources.tar.gz` (через `Scripts/build_third_party_sources_bundle.sh`) и приложить к GitHub Release.

## 7) Как мы “обезопасиваемся” юридически (политика)

### 7.1 Политика third‑party intake

Каждая новая/обновлённая third‑party часть должна быть “заклёпана” сразу:

- `FluffyFlash/THIRD_PARTY.md` (что, откуда, лицензия, зачем, как выполняем обязательства)
- `FluffyFlash/THIRD_PARTY_NOTICES.txt` (если компонент распространяется в релизе)
- `Scripts/build_third_party_sources_bundle.sh` (чтобы sources/manifest собирались автоматически)
- эта заметка `Legal.md` (инвентарь + риски + чеклист)

### 7.2 Разделение “build-time” vs “redistributed”

- **Build-time only** (только для сборки, не поставляется пользователю): обычно достаточно фикса в `THIRD_PARTY.md`.
- **Redistributed** (внутри `.app` / в релизных пакетах): обязательны notices + соответствующие исходники для copyleft (GPL и т.п.).

### 7.3 Что именно мы делаем для GPL bundled tools

Поскольку мы шипим `aria2c/cabextract/wimlib/chntpw` внутри `.app`, мы для каждого релиза:

- прикладываем `FluffyFlash/THIRD_PARTY_NOTICES.txt`;
- прикладываем source‑bundle и манифест:
  - `FluffyFlash/ReleaseArtifacts/third-party/manifest.json`
  - `FluffyFlash/ReleaseArtifacts/third-party/source-sha256.txt`
  - `FluffyFlash/ReleaseArtifacts/third-party/third-party-sources.tar.gz`

Это снижает риск “несоответствия версий” и ускоряет ответы на комплаенс‑вопросы.

### 7.4 Дисклеймеры и брендинг

- Мы не аффилированы с Microsoft/Apple; пользователю нужна валидная лицензия ОС.
- Не используем чужие торговые марки в виде “продуктовых названий” без дисклеймера (Windows®/Apple® и т.п.).

---

Связанные заметки: [[Architecture]], [[Roadmap]], [[Backlog]].

