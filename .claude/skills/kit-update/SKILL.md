---
name: kit-update
description: "Обновить набор claude-starter в проекте до новой версии — по уведомлению хука «вышла новая версия набора» после «да» владельца или по просьбе «обнови набор». Скачать новую версию, заменить только файлы набора, которые владелец не менял, изменённые — показать и спросить, документы проекта не трогать, проверить и закоммитить."
---

# Обновление набора

Документы проекта (`docs/ai/*`) и код не трогать. Всё обратимо: коммит до и после.

1. Источник и версия — `.claude/starter.json` (`source`, `version`). Нет файла → спросить
   владельца ссылку на набор. Незакоммиченные изменения → сначала коммит.
2. Скачать новую версию в `_starter_new/`: `git clone --depth 1 <source> _starter_new`
   (нет git — архив `<source>/archive/refs/heads/main.zip`); `source` — папка → скопировать.
   Прочитать `_starter_new/CHANGELOG.md` — что изменилось между версиями.
3. План: `python3 .claude/hooks/kit_hooks.py update-plan _starter_new`
   (Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File .claude\hooks\kit-version.ps1 update-plan _starter_new`).
   Показать владельцу сжато: версия, что нового (из CHANGELOG), сколько файлов заменится,
   какие файлы он менял сам. Получить «да».
4. Применить: «добавить» и «заменить» — скопировать; «изменён владельцем» — показать разницу,
   по каждому спросить (взять новый / оставить свой / объединить); «удалить» — удалить.
   Вручную сверить и перенести нужное: блок набора в `CLAUDE.md` (между маркерами
   `claude-starter`, текст владельца не трогать), хуки и разрешения в `.claude/settings.json`
   (свои правила владельца не удалять; ОС не Windows — из `settings.unix.json`), `.mcp.json`.
   Новые шаблоны `docs/ai`, которых нет в проекте, — добавить; существующие не менять.
5. Отпечатки: `python3 .claude/hooks/kit_hooks.py manifest _starter_new <source>`
   (Windows: `... kit-version.ps1 manifest _starter_new <source>`). Удалить `_starter_new/`.
6. Проверить: тесты хуков (`python3 .claude/hooks/tests/run_tests.py`, Windows `py -3 …`).
   Коммит `chore: набор claude-starter <версия>`. Отчёт владельцу в 2–3 строки: версия, что
   нового, что осталось на его решение.
