# Хуки — автоматические защиты

Хук — скрипт, который Claude Code запускает сам в нужный момент: получает JSON о событии на
stdin и отвечает кодом выхода (0 — пропустить; 2 + текст в stderr — заблокировать и
объяснить Claude), JSON с `"permissionDecision": "ask"` (спросить владельца) или текстом,
который добавляется Claude в контекст (SessionStart, UserPromptSubmit, additionalContext).

| Хук | Событие | Что делает |
|---|---|---|
| `session-start` | SessionStart (startup, resume, clear, compact, fork) | ветка, HEAD, число незакоммиченных файлов и раздел «Сейчас» из STATE.md; предупреждает, если STATE записан раньше, чем на прошлом коммите; набор не инициализирован — просит предложить `/kit-setup`; чистит свои снимки старше 7 дней |
| `turn-start` | UserPromptSubmit | снимок `git status` + HEAD в начале хода (для `check-docs`) и строка-напоминание: сверить запрос с «Что запускать», документы в том же шаге |
| `guard-shell` | PreToolUse: Bash, PowerShell | ssh с heredoc / `$(...)` / вложенными кавычками / кириллицей в переменной — **блок**; установки и запуск стороннего кода (npm/pip/npx/uv/docker/curl\|sh/claude mcp add…, в т.ч. внутри `bash -c "…"`) — **вопрос** (кроме полного доверия); чтение секретов (.env, ключи, токены облаков, печать переменных окружения) — **вопрос**; опасное (удаление, force-push, rebase, миграции и сброс баз, docker down -v, деплой, terraform/kubectl, службы, диски) — **вопрос** всегда; запись в CLAUDE.md и `.claude/` через оболочку — **вопрос** (разрешения и хуки — при любом доверии) |
| `pre-write` | PreToolUse: Write, Edit | в одном процессе три проверки ниже |
| ↳ `guard-cyrillic` | | кириллица в имени файла, в папках проекта, в идентификаторах (объявления, параметры, вызовы, поля, ключи JSON/YAML, переменные shell/env, маршруты, id/class в разметке) — **блок**; русский текст в строках, комментариях, докстрингах, шаблонах, тексте JSX/HTML/Vue — можно; файлы переводов в `locales/`, `i18n/`, `lang/`, `ru.json` — ключи можно |
| ↳ `guard-instructions` | | правка `CLAUDE.md`, `AGENTS.md`, `.mcp.json`, `.claude/rules\|skills\|agents\|commands\|output-styles\|plugins/` — **вопрос** (кроме полного доверия); `.claude/hooks/` и `settings*.json` — **вопрос всегда**, кроме личного `settings.local.json`, который Claude пишет целиком и только с ключами профиля (доверие из PROFILE.md, `defaultMode`, `outputStyle`); `docs/ai/` — молча |
| ↳ `rules-on-write` | | файл подходит под `paths:` правила из `.claude/rules` — текст правила добавляется в контекст (раз за сеанс на правило); иначе правила грузятся только при чтении файлов |
| `check-python` | PostToolUse: Write, Edit | `.py` после записи через `ast.parse` (кодировка — как у Python, BOM допустим); ошибка — **блок** с трассировкой |
| `check-docs` | Stop (конец ответа) | по снимку `turn-start`: в **этом ходе** изменён или закоммичен код, а `docs/ai/*.md`, `docs/ai/specs|solutions/`, `CLAUDE.md` или `.claude/rules` — нет, или у изменённых файлов нет строки `Назначение:` в первых 15 строках — **не даёт закончить** (один раз за ответ). Изменённый документ docs/ai длиннее предела (PROFILE 40, STATE 60, KNOWLEDGE 80, LESSONS 40, INDEX 60, остальные 300 строк) или не записан в `docs/ai/INDEX.md` — тоже не даёт закончить. Всё в порядке — сам ставит дату и `head:` в STATE.md. Чужие незакоммиченные файлы не считаются. Снимка нет — учитываются файлы, изменённые за последние 30 минут |
| `kit-version` | вручную | `manifest` — записать версию и отпечатки файлов набора в `.claude/starter.json`; `update-plan <новая версия>` — что заменить, добавить, удалить (`kit_hooks.py manifest …` / `kit-version.ps1 manifest …`). `session-start` раз в сутки сверяет версию с источником и сообщает о новой |
| `scan` | вручную | проверка кириллицы в готовых файлах без записи: `python3 .claude/hooks/kit_hooks.py scan <папки>` или `scan.ps1 <папки>` |

Отдельные `guard-cyrillic`, `guard-instructions`, `rules-on-write` тоже можно вызвать — для проверки.

## Две версии
- **Windows** — `*.ps1` (PowerShell 5.1 и 7), общая логика в `kit_common.ps1`; подключены в `.claude/settings.json`.
- **Linux / macOS / Git Bash** — `run.sh` + `kit_hooks.py` (нужен `python3`); подключены в
  `.claude/settings.unix.json` (`/kit-setup` подставит). Без `python3` хуки молчат и всё разрешают.

Уровень доверия хуки берут из `CLAUDE_TRUST_LEVEL` (`env` в settings.json; личный
`settings.local.json` со значением `full` отключает вопросы про установки и правку правил
и скиллов; вопросы про опасное, секреты, разрешения и хуки остаются).

## Тесты
```bash
python3 .claude/hooks/tests/run_tests.py            # обе версии (PowerShell — если найден)
python3 .claude/hooks/tests/run_tests.py --impl py  # только Python;  -v — подробности
```
Windows: `py -3 .claude\hooks\tests\run_tests.py`. ~850 случаев (`tests/cases.json`: ожидаемый
ответ allow / ask / block) и ~30 сценариев с временными git-репозиториями на каждую версию;
расхождение версий — тоже ошибка. Итог — «всё в порядке». Известное ограничение: фрагмент
Edit изнутри многострочной строки без контекста может выглядеть как код.

## Проверить хук вручную
```bash
# Linux/macOS
printf '{"tool_input":{"command":"npm i left-pad"}}' | bash .claude/hooks/run.sh guard-shell; echo "exit=$?"
printf '{"tool_input":{"file_path":"/tmp/x.ts","content":"const ИМЯ = 1"}}' | bash .claude/hooks/run.sh guard-cyrillic; echo "exit=$?"
```
```powershell
# Windows
'{"tool_input":{"command":"npm i left-pad"}}' | powershell -NoProfile -ExecutionPolicy Bypass -File .claude\hooks\guard-shell.ps1; $LASTEXITCODE
```
Ожидается: первый выводит JSON с `"ask"`, второй — exit 2 и сообщение о кириллице.

## Отключить или изменить
Убрать хук — удалить его запись из `hooks` в `.claude/settings.json` (`settings.local.json`
хуки не отключает — они складываются). Изменить проверку — править `kit_common.ps1` и
`kit_hooks.py` одинаково, добавить случай в `tests/cases.json` и прогнать тесты.
