# Стартовые наборы по типам проектов (проверено 17.09.2026, перед установкой — compat-check)

Обозначения: `P:имя` = `/plugin install имя@claude-plugins-official` (владелец вводит в Claude Code;
без интерактива: `claude plugin install имя@claude-plugins-official`) · `C:имя` = сначала
`/plugin marketplace add anthropics/claude-plugins-community`, затем `/plugin install имя@claude-community`
(сторонние, прошли автопроверку — читать код) · `S:автор/репо` = `npx skills add автор/репо` (+ `--skill имя`)
· MCP: `claude mcp add --transport http имя url` (удалённый) или `claude mcp add имя -- команда`.
Б — бесплатно · Б* — бесплатный уровень, дальше платно · $ — платный тариф.
`@<версия>` — подставить версию, найденную в `compat-check` (не `latest`).

## Базовый набор — для любого проекта
| Что | Тип | Установка | Цена | Зачем |
|---|---|---|---|---|
| commit-commands | плагин | `P:commit-commands` | Б | коммит, push, PR одной командой |
| security-guidance | плагин | `P:security-guidance` | Б | предупреждения о небезопасных правках, обзор diff |
| code-review | плагин | `P:code-review` | Б | ревью изменений несколькими агентами |
| LSP языка | плагин | таблица ниже | Б | ошибки типов сразу после правки, переходы по коду |
| Context7 | MCP | уже в `.mcp.json` набора (`https://mcp.context7.com/mcp`); ключ — context7.com/dashboard | Б* | свежая документация библиотек нужной версии |
| Playwright | плагин/MCP | `P:playwright` или `claude mcp add playwright -- npx @playwright/mcp@<версия>` | Б | проверка страниц, формы, скриншоты (`ui-checker`) |
| chrome-devtools-mcp | плагин/MCP | `P:chrome-devtools-mcp` | Б | консоль, сеть, производительность, Lighthouse |
| github | плагин/MCP | `P:github` | Б | issues, PR, поиск по коду (нужен `gh` или токен) |
| document-skills | скиллы | `/plugin marketplace add anthropics/skills` → `/plugin install document-skills@anthropic-agent-skills` | Б | docx/pdf/pptx/xlsx |
| claude-md-management | плагин | `P:claude-md-management` | Б | следит за здоровьем CLAUDE.md |
| Тесты | библиотеки | `npm i -D vitest @playwright/test` · `pip install pytest pytest-playwright` | Б | проверки, которые Claude запускает сам |

LSP (сначала поставить программу языкового сервера, плагин её не ставит):
TypeScript `P:typescript-lsp` + `npm i -g typescript-language-server typescript` · Python `P:pyright-lsp` + `npm i -g pyright` ·
PHP `P:php-lsp` + `npm i -g intelephense` · Go `P:gopls-lsp` + `go install golang.org/x/tools/gopls@<версия>` ·
Rust `P:rust-analyzer-lsp` + `rustup component add rust-analyzer` · Java `P:jdtls-lsp` · Kotlin `P:kotlin-lsp` ·
Swift `P:swift-lsp` · Ruby `P:ruby-lsp` + `gem install ruby-lsp` · C/C++ `P:clangd-lsp` · C# `P:csharp-lsp` · Lua `P:lua-lsp`.
Источник: https://code.claude.com/docs/en/discover-plugins#code-intelligence

## 1. Веб-приложение / сайт на JS (Next.js, React, Vue)
`P:typescript-lsp` · `P:vercel` (деплой) · `P:supabase` или `P:neon` / `P:prisma` (база) · `P:figma` (дизайн → код) ·
скиллы: `S:vercel-labs/next-skills`, `S:vercel-labs/agent-skills --skill vercel-react-best-practices`,
`S:shadcn-ui/ui`, `S:saadeghi/daisyui` · `P:modern-web-guidance` · `P:sentry`, `P:posthog`, `P:auth0`, `P:resend` (Б*).
Vue/Nuxt и Tailwind — официальных скиллов не найдено: Context7.

## 2. Python backend / API (FastAPI, Django) + Postgres
`P:pyright-lsp` · `S:fastapi/fastapi` · `S:vintasoftware/django-ai-plugins --skill django-expert` ·
Postgres только чтение: `claude mcp add --transport stdio db -- npx -y @bytebase/dbhub --dsn "postgresql://readonly:…"` ·
`P:neon` / `P:supabase` / `P:prisma` · `P:logfire` (наблюдаемость) · `pip install pytest ruff sqlalchemy`.

## 3. PHP (Laravel, WordPress)
`P:php-lsp` · Laravel Boost: `composer require laravel/boost --dev` → `php artisan boost:install` (MCP + скиллы) ·
`S:laravel/boost` · `P:build-with-wordpress` (Automattic) · сторонние: `C:wordpress-mcp`, `C:laraclaude`.

## 4. Мобильные (React Native/Expo, Flutter)
`P:expo` или `S:expo/skills` · Flutter: `/plugin marketplace add flutter/agent-plugins` → `/plugin install dart-flutter@dart-flutter`,
`npx skills add flutter/agent-plugins --skill '*'` · `P:swift-lsp`, `P:kotlin-lsp` · `P:revenuecat`, `P:firebase`, `P:supabase`.

## 5. Данные / аналитика / ETL
`P:duckdb-skills` · `P:data-engineering` (Astronomer) · `C:dbt-engineer` · `P:bigquery-data-analytics` / `P:clickhouse` /
`P:snowflake-cortex-code` · document-skills (xlsx) · `pip install pandas polars duckdb openpyxl`.

## 6. SEO / маркетинг
`P:firecrawl` (обход и извлечение, Б*) · `P:exa`, `P:tavily` (поиск через API, Б*) · `chrome-devtools-mcp` (Lighthouse, Web Vitals) ·
сторонние: `C:search-console-mcp`, `C:claude-seo`, `C:web-vitals-auditor` · `P:posthog`.
Российские источники (Яндекс Вебмастер, Метрика, Wordstat, Search API) — через официальные API, см. reference в проекте.

## 7. Финансы / счета / внутренние инструменты
document-skills (xlsx/pdf/docx) · `P:stripe` или `claude mcp add --transport http stripe https://mcp.stripe.com/` (записи — только с подтверждением) ·
`P:carbone-skill` (шаблонные PDF/DOCX/XLSX, Б*) · `npm i exceljs pdf-lib` · `pip install openpyxl pdfplumber`.

## 8. Медицина / CRM с персональными данными
`P:security-guidance`, `P:claude-security` · `P:semgrep` / `P:aikido` / `P:sonarqube` (Б*) · `P:auth0` / `P:workos` (вход, роли, журнал) ·
`P:vanta` ($, соответствие) · база — только read-only DSN; в код Claude не давать запись в хранилище с данными пациентов.
Российский закон о персональных данных (152-ФЗ) — уточнять требования в ТЗ.

## 9. Творческие сайты (анимация, 3D, видео, фото)
`S:greensock/gsap-skills` (официально) · `S:cloudai-x/threejs-skills` (сторонний) · `S:remotion-dev/skills --skill remotion-best-practices` ·
`P:hyperframes` (HTML→видео) · `P:frontend-design`, `P:superdesign` · `P:cloudinary`, `P:runway-api`, `P:canva` (Б*/$) ·
`npm i sharp fluent-ffmpeg` + системный `ffmpeg`.

## 10. DevOps / серверы
`P:terraform` · `P:datadog` / `P:grafana-mcp` / `P:newrelic` (Б*) · `P:pagerduty` ($) · сторонние: `C:docker-and-kubernetes-devkit`,
`C:k8s-skills`, `C:docker-image-scan`, `C:vps-ops` · `P:railway`, `P:render`, `P:cloudflare`, `P:aws-core` · `P:mcp-tunnels` ·
SSH — встроенный Bash Claude Code (`ssh`/`scp`), отдельный SSH-MCP не нужен.

## Другие проверенные MCP-адреса
Notion `https://mcp.notion.com/mcp` · Linear `https://mcp.linear.app/mcp` · Atlassian `https://mcp.atlassian.com/v2/mcp` ·
Sentry `https://mcp.sentry.dev/mcp` · Vercel `https://mcp.vercel.com` · Neon `https://mcp.neon.tech/mcp` ·
Supabase `https://mcp.supabase.com/mcp?project_ref=<ref>&read_only=true` · Figma `https://mcp.figma.com/mcp` · Slack — только `P:slack`.

Пометки: имена в каталоге могут отличаться от названий продуктов (например `chrome-devtools-mcp`); `C:` — сторонние,
проверять код; тарифы Figma и Slack не подтверждены — уточнять.
