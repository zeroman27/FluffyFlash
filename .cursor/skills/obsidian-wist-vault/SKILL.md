---
name: obsidian-wist-vault
description: >-
  Obsidian knowledge base for Wist: vault paths, note structure, and when
  to update Architecture, Roadmap, Backlog, and session notes after code changes.
---

# Obsidian vault (Wist)

## Где лежит vault

| Путь | Назначение |
|------|------------|
| `ObsidianVault/` | Каноническая папка vault в корне репозитория |
| `docs/vault` | Симлинк на `ObsidianVault` — удобно, если ищете «docs» |

В Obsidian: **Open folder as vault** → выберите `ObsidianVault` или `docs/vault` (только корень vault, не подпапку).

**Правки из Cursor:** файлы в `ObsidianVault/` при сохранении сразу на диске; Obsidian на macOS обычно подхватывает изменения без отдельного шага. Нет настройки в git-репозитории, которая «включала бы» Obsidian — это поведение [приложения Obsidian](https://obsidian.md).

## Настройки в репозитории

- В **`.obsidian/`** заданы: новые заметки → `00-Inbox/`, вложения → `attachments/`, шаблоны → `Templates/` (шаблон **Session** для сессий).
- Подробности: `ObsidianVault/README.md`.

## Структура заметок

- `ObsidianVault/10-Project-Wist/` — продукт: Vision, Roadmap, Architecture, Backlog, Sessions, Decisions.
- Шаблон сессии: `Templates/Session.md` (и дубликат `10-Project-Wist/Sessions/_template.md`).

## Синхронизация с разработкой

При **существенных** изменениях в приложении (фичи, архитектура, заметное поведение):

1. Обновить по смыслу [[Architecture]], [[Roadmap]], [[Backlog]] в `10-Project-Wist/`.
2. При необходимости добавить запись в `Sessions/YYYY-MM-DD.md`.

Не дублировать большие куски кода в Obsidian — краткие пункты и ссылки на модули/файлы.

Правило Cursor с тем же смыслом: `.cursor/rules/obsidian-vault-sync.mdc`.
