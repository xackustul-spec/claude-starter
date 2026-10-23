---
name: kit-update
description: "/kit-update или «обнови набор»: обновить claude-starter в проекте до свежей версии, не трогая документы и правила проекта."
---

# Обновление набора

Документы проекта (`docs/ai/*`) и код не трогать. Всё обратимо: коммит до и после. Windows: вместо
`python3 .claude/hooks/kit_hooks.py` — `powershell -NoProfile -ExecutionPolicy Bypass -File .claude\hooks\kit-version.ps1`.

0. Начало: `.claude/starter.lock` (`{"mode": "update", "начато": "<дата и время>"}`; час) — хук не спрашивает
   про файлы набора, которые владелец не менял. Удалить в шаге 6. Вопросы — только про файлы, которые
   владелец менял сам (шаг 4), один раз списком.
1. Источник и версия — `.claude/starter.json` (`source`, `version`); нет файла — источник
   `https://github.com/xackustul-spec/claude-starter`. Незакоммиченное — сначала коммит.
2. `git clone --depth 1 <source> _starter_new` (нет git — архив `<source>/archive/refs/heads/main.zip`;
   `source` — папка → скопировать). CHANGELOG читать только записи новее текущей версии.
3. План: `python3 .claude/hooks/kit_hooks.py update-plan _starter_new`. Владельцу сжато: версия, что нового,
   сколько файлов заменится, какие он менял сам.
4. Применить: «добавить» и «заменить» — скопировать; «изменён владельцем» — показать разницу, спросить
   (новый / свой / объединить); «удалить» — удалить. Сверить вручную: `CLAUDE.md` — заменить целиком
   (правила проекта живут в `.claude/rules/project.md`, его не трогать), хуки в `.claude/settings.json`
   (ОС не Windows — из `settings.unix.json`; правила владельца не удалять), `.mcp.json`. Новые шаблоны
   `docs/ai` добавить, существующие не менять. `.gitignore` не заменять — дописать недостающие строки из
   `gitignore.starter`.
5. Отпечатки: `python3 .claude/hooks/kit_hooks.py manifest _starter_new <source из starter.json>` (никогда не «.»).
   Удалить `_starter_new/`.
6. Удалить `.claude/starter.lock`. Полный прогон тестов не делать (долго; он для выпуска набора) — после
   `/clear` в начале сеанса должна быть строка `[claude-starter] Старт сеанса`. Коммит
   `chore: набор claude-starter <версия>`. Отчёт в 2–3 строки: версия, что нового, что ждёт его решения.
