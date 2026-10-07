# Назначение: общие функции хуков claude-starter для Windows (PowerShell 5.1 и 7);
# подключается каждым хуком через `. "$PSScriptRoot\kit_common.ps1"`.
# Логика повторяет kit_hooks.py (Linux/macOS): те же проверки, сообщения и коды выхода.
$ErrorActionPreference = 'SilentlyContinue'
try {
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$script:CYR = '[Ѐ-ӿ]'
$script:W = '[\wЀ-ӿ$]*'
$script:CodeExt = @('.ts','.tsx','.js','.jsx','.mjs','.cjs','.vue','.svelte','.py','.php','.go','.rs','.java','.kt','.rb','.cs','.swift','.dart','.sh','.bash','.ps1','.sql','.yaml','.yml','.toml','.json','.prisma','.env','.conf','.html','.htm','.css','.scss','.less','.graphql','.gql')
$script:HeaderExt = @('.ts','.tsx','.js','.jsx','.mjs','.cjs','.vue','.svelte','.py','.php','.go','.rs','.java','.kt','.rb','.cs','.swift','.dart','.sh','.bash','.ps1','.sql')
$script:SpecialNames = '^(Dockerfile|Caddyfile|Makefile|compose.*\.ya?ml|docker-compose.*\.ya?ml)$'
$script:Generated = '(^|/)(node_modules|dist|build|\.next|out|coverage|vendor|__pycache__|migrations|\.venv|venv|target)/|\.min\.|\.lock$|lock\.json$|\.generated\.'
$script:CLike = @('.ts','.tsx','.js','.jsx','.mjs','.cjs','.vue','.svelte','.php','.go','.rs','.java','.kt','.cs','.swift','.dart','.sql','.prisma','.css','.scss','.less','.graphql','.gql')
$script:JsLike = @('.ts','.tsx','.js','.jsx','.mjs','.cjs','.vue','.svelte')
$script:Markup = @('.tsx','.jsx','.vue','.svelte','.html','.htm','.php')
$script:HashComment = @('.py','.sh','.bash','.ps1','.yaml','.yml','.toml','.env','.conf','.rb','.graphql','.gql')

# Ввод и вывод — байтами в UTF-8: не зависит от кодовой страницы консоли (в хуке её может не быть).
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-Out([string]$text) {
    try { $b = $script:Utf8.GetBytes($text + "`n"); $st = [Console]::OpenStandardOutput(); $st.Write($b, 0, $b.Length); $st.Flush() }
    catch { Write-Output $text }
}
function Write-Err([string]$text) {
    try { $b = $script:Utf8.GetBytes($text + "`n"); $st = [Console]::OpenStandardError(); $st.Write($b, 0, $b.Length); $st.Flush() }
    catch { [Console]::Error.WriteLine($text) }
}
function Read-HookInput {
    try {
        $reader = New-Object System.IO.StreamReader -ArgumentList ([Console]::OpenStandardInput()), $script:Utf8
        $raw = $reader.ReadToEnd().TrimStart([char]0xFEFF)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $script:Data = ($raw | ConvertFrom-Json)
        return $script:Data
    } catch { return $null }
}
# «Спросить» — не окно разрешения (оно висит часами без владельца), а отказ с просьбой спросить словами.
$script:ChatAskSuffix = ' Окно разрешения не открывать: спроси владельца словами одной строкой — что именно и зачем — и закончи ход. Его «да» следующим сообщением откроет этот вызов.'
$script:OkRe = '^\W*(да|ок|окей|ok|давай|делай|разрешаю|можно|подтверждаю|согласен|yes|go|продолжай|выполняй)\W*$'
function Test-TurnOk {
    try {
        $sf = Get-StateFile $script:Data 'turn'
        if (-not (Test-Path -LiteralPath $sf)) { return $false }
        $snap = (Get-Content -LiteralPath $sf -Raw -Encoding UTF8) | ConvertFrom-Json
        return ((Get-Prop $snap 'ok') -eq $true)
    } catch { return $false }
}
function Get-Prop($obj, $name) {
    if ($null -eq $obj) { return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($null -eq $p) { return $null }
    return $p.Value
}
function Out-Ask([string]$reason) {
    if (Test-TurnOk) { return }
    $o = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = ($reason + $script:ChatAskSuffix) } }
    Write-Out ($o | ConvertTo-Json -Depth 5 -Compress)
    exit 0
}
function Out-Deny([string]$reason) {
    $o = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason } }
    Write-Out ($o | ConvertTo-Json -Depth 5 -Compress)
    exit 0
}
function Out-Block([string[]]$lines) {
    Write-Err ($lines -join "`n")
    exit 2
}
function Sort-Ordinal($items) {
    $a = [string[]]@($items | Where-Object { $null -ne $_ })
    [Array]::Sort($a, [StringComparer]::Ordinal)
    return ,$a
}
$script:CheckRe = 'провер|перепровер|ошибк|\bбаг|тест|сда[юёе]м?\b|сдавай|приним|принят|убедись|ревизи|аудит|всё\s+ли|все\s+ли|перед\s+(выкладк|депло|боев)|на\s+боевой|выкладыва|деплой|качеств'
$script:CheckHint = 'Набор: владелец просит проверку — на этот ход полный порядок: проверка кода субагентом change-verifier (Opus), экраны — ui-checker и замер вёрстки на четырёх ширинах, копия — пара снимков и счёт; итог таблицей «что проверено · результат · что исправлено». Не ясно, что именно и где проверять, — один вопрос «проверить на ошибки? где?» и ждать.'
function Test-KitFull { return (([string]$env:CLAUDE_KIT_MODE).Trim().ToLowerInvariant() -eq 'full') }
function Test-FastTurn($snap) { if (Test-KitFull) { return $false }; return (-not ((Get-Prop $snap 'check') -eq $true)) }
function Test-TrustFull { return (([string]$env:CLAUDE_TRUST_LEVEL).Trim().ToLowerInvariant() -eq 'full') }
function Get-ProjectDir($data) {
    $d = [string]$env:CLAUDE_PROJECT_DIR
    if ([string]::IsNullOrWhiteSpace($d)) { $d = [string](Get-Prop $data 'cwd') }
    if ([string]::IsNullOrWhiteSpace($d)) { $d = (Get-Location).Path }
    return $d
}
function Get-StateFile($data, [string]$kind) {
    $base = [string](Get-Prop $data 'scratchpad_dir')
    if ([string]::IsNullOrWhiteSpace($base)) { $base = Join-Path ([System.IO.Path]::GetTempPath()) 'claude-starter' }
    try { New-Item -ItemType Directory -Force -Path $base | Out-Null } catch { $base = [System.IO.Path]::GetTempPath() }
    $sid = [string](Get-Prop $data 'session_id'); if ([string]::IsNullOrWhiteSpace($sid)) { $sid = 'nosession' }
    $sid = [regex]::Replace($sid, '[^\w.-]', '_')
    return (Join-Path $base ("starter-" + $sid + "." + $kind + ".json"))
}
function Get-RelPath([string]$path, [string]$root) {
    $p = $path -replace '\\', '/'
    $r = ($root -replace '\\', '/').TrimEnd('/')
    if ($p.TrimEnd('/').ToLowerInvariant() -eq $r.ToLowerInvariant()) { return '' }  # сама папка проекта — внутри
    if ($p.ToLowerInvariant().StartsWith($r.ToLowerInvariant() + '/')) { return $p.Substring($r.Length + 1) }
    return $null
}
function Invoke-Git([string]$root, [string[]]$gitArgs) {
    try {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
        $out = & git -C $root -c core.quotepath=off @gitArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return (($out | ForEach-Object { [string]$_ }) -join "`n")
    } catch { return $null }
}
function Get-FileExt([string]$leaf) {
    if ($leaf -match '^\.env(\..*)?$') { return '.env' }
    return [System.IO.Path]::GetExtension($leaf).ToLowerInvariant()
}

# ---------------------------------------------------------------- guard-shell
# Pre — начало команды: добавлены кавычки и обратные кавычки (bash -c "...", eval "...", `...`)
$script:Pre = '(^|[\s;|&(''"`])'
$script:GitF = 'git\s+(?:(?:-[cC]\s+\S+|--[\w-]+(?:=\S*)?|-[a-zA-Z])\s+)*'
$script:InteractiveRe = '(^|[;|&(]\s*|^\s*(sudo\s+)?)(vim?|nvim|nano|less|more|top|htop|Read-Host|pause|git\s+commit(?![^|;&]*(-m|-F|--message|--file))\b|git\s+rebase\s+-i|npm\s+init(?![^|;&]*-y)|npx\s+create-[\w-]+(?![^|;&]*(-y|--yes))|ssh(\.exe)?\s+(-\S+\s+)*[\w.@-]+\s*($|[;|&)])|python3?\s*($|[;|&)])|node\s*($|[;|&)])|psql(?![^|;&]*(-c|-f|<))\b)'
$script:SshRe = '(^|[\s;|&(])ssh(\.exe)?\s'
$script:InstallRe = $script:Pre + '(npm|pnpm|yarn|bun)\s+(i|install|add|ci|create|exec|dlx|x|update|upgrade|up)\b' +
    '|' + $script:Pre + 'yarn\s*($|[;&|])' +
    '|\b(npx|bunx)\s+(-y\s+|--yes\s+|-p\s+\S+\s+)?(?!(skills\s+find|prisma|tsc|eslint|prettier|vitest|jest|playwright|next|vite|tailwindcss|drizzle-kit|nodemon|ts-node|tsx)(\s|$))\S' +
    '|\buvx\s|pipx\s+(run|install)|pip3?\s+install|python3?\s+-m\s+pip\s+install|\buv\s+(pip\s+install|add|sync|tool\s+(install|run))|poetry\s+(add|install|update)|pipenv\s+(install|update|sync)|conda\s+(install|create|update)' +
    '|apt(-get)?\s+(-\S+\s+)*install|dnf\s+install|yum\s+install|snap\s+install|winget\s+install|choco\s+install|brew\s+(install|tap|upgrade)|scoop\s+install|pacman\s+-S|apk\s+add|zypper\s+(in|install)|nix-shell|nix\s+(shell|run|profile\s+install)|pkg\s+install' +
    '|cargo\s+(add|install)|\bgo\s+((get|install)\s|mod\s+download\b)|\bgo\s+run\s+\S+@|gem\s+install|bundle\s+(install|update)|composer\s+(require|global|install|update)|dotnet\s+(add\s+package|tool\s+install|restore)' +
    '|deno\s+(install|add|run\s+https?://)|\bmake\s+install\b|cmake\s+--install|setup\.py\s+install' +
    '|claude\s+(mcp\s+add(-json)?|plugins?\s+(install|marketplace\s+add)|install)|/plugin\s+(install|marketplace)' +
    '|docker(\s+|-)(pull|compose\s+(pull|up|build)|run|build)\b' +
    '|(curl|wget|Invoke-WebRequest|iwr|irm|Invoke-RestMethod)\b[^|\n]*\|\s*(sudo\s+)?(ba|z|da|k)?sh\b' +
    '|(curl|wget|Invoke-WebRequest|iwr|irm|Invoke-RestMethod)\b[^|\n]*\|\s*(python3?|node|pwsh|powershell|perl|ruby)\b' +
    '|(curl|wget|irm|iwr)\b[^|\n]*[;&]{1,2}[^|\n]*\b(ba|z|da|k)?sh\s+(-\S+\s+)*\S+\.(sh|bash)\b' +
    '|\|\s*(sudo\s+)?(ba|z|da|k)?sh\b\s*(-s\b|$|[;&|])' +
    '|Invoke-WebRequest|\biwr\b|Invoke-Expression|\biex\b|Install-Module|Install-Package|\birm\b[^|;&]*-OutFile'
$script:DangerRe = 'docker(\s+|-)compose\s+down[^|;&]*\s(-v|--volumes)\b|docker(\s+|-)(compose\s+)?(volume\s+(rm|prune)|system\s+prune|container\s+(prune|rm|kill)|image\s+prune|rm\b|rmi|kill\b)' +
    '|' + $script:Pre + 'rm\s+(?:(?:-[a-zA-Z]+|--\w+|[^\s|;&-]\S*)\s+)*(-[a-zA-Z]*[rRf][a-zA-Z]*|--recursive|--force)\b' +
    '|' + $script:Pre + '(ri|rd|del|erase)\s+(-r\b|-Recurse|/[sq])|rmdir\s+/s|Remove-Item\b[^|;&]*(-Recurse|-Force|\s-r\b)|\bClear-Content\b' +
    '|find\b[^|;&]*\s(-delete\b|-exec\s+rm\b)|xargs\s+(-\S+\s+)*rm\b|\bshred\b|rsync\b[^|;&]*--delete' +
    '|(^|[\s;|&(''"])(DROP\s+(TABLE|DATABASE|SCHEMA|INDEX)|TRUNCATE\s+(TABLE\s+)?\w+|DELETE\s+FROM|ALTER\s+TABLE\s+\w+\s+DROP)\b' +
    '|\bflush(all|db)\b|\.drop(Database|Collection)?\(\)|db\.\w+\.drop\(' +
    '|prisma\s+(migrate\s+(reset|deploy|dev)|db\s+push)|drizzle-kit\s+(push|drop|migrate)|(alembic|flask\s+db|manage\.py)\s+(downgrade|migrate|upgrade|flush)\b' +
    '|rails\s+db:(drop|reset|migrate|rollback|purge|schema:load)|artisan\s+(migrate|db:wipe)|typeorm\s+schema:(drop|sync)|knex\s+migrate:rollback|sequelize\s+db:migrate:undo' +
    '|' + $script:GitF + '(push\b[^|;&]*?\s(--force|--delete|-d\b|-[a-zA-Z]*f[a-zA-Z]*(?=\s|$)|\+\w|:\w)|reset\s+--hard|clean\s+-[a-z]*f|checkout\s+--\s|checkout\s+\.|restore\s(?![^|;&]*--staged)|branch\s+(?-i:-D)|stash\s+(drop|clear)|filter-branch|filter-repo|rebase\b|commit\s+[^|;&]*--amend|tag\s+(-d|--delete)|reflog\s+expire|gc\s+[^|;&]*--prune|update-ref\s+-d|worktree\s+remove\s+[^|;&]*(--force|-f\b)|config\s+[^|;&]*alias\.)' +
    '|(terraform|tofu)\s+(destroy|apply)|pulumi\s+(destroy|up)|cdk\s+(deploy|destroy)|helm\s+(uninstall|delete|upgrade|install|rollback)|kubectl\s+(delete|apply|scale|rollout\s+(restart|undo)|drain|cordon)' +
    '|gh\s+(repo\s+delete|release\s+delete|pr\s+merge|api\s+[^|;&]*(-X|--method)\s+DELETE)' +
    '|systemctl\s+(stop|disable|restart)\s|\bservice\s+\S+\s+(stop|restart)\b|\b(Stop|Restart)-(Service|Computer)\b|Set-Service\b[^|;&]*Disabled' +
    '|\b(Format-Volume|Clear-Disk|Remove-Partition|Initialize-Disk)\b|\bdiskpart\b|\breg\s+delete\b|Remove-ItemProperty\b[^|;&]*HK(LM|CU)' +
    '|\bshutdown\b|\breboot\b|\bmkfs|\bdd\s+[^|;&]*\b(if|of)=|\btruncate\s+(-s|--size)|^\s*(:\s*)?>{1,2}\s*\S+\s*$|(^|[\s;&|])>\s*\S+\.(db|sqlite3?|mdb|accdb|env)\b' +
    '|\b(chmod|chown|chgrp)\s+(-[a-zA-Z]*R|--recursive)|crontab\s+-r\b|iptables\s+(-F|--flush)|ufw\s+disable' +
    '|\b(vercel|netlify|wrangler|railway|serverless|sls|sam|kamal|firebase|amplify)\s+(deploy|publish|up|release)\b|\b(vercel|netlify)\b[^|;&]*--prod\b|(^|[\s;|&(])vercel\s*$|render\s+deploys?\s+create|\b(fly|flyctl)\s+deploy\b|gcloud\s+(run|app|functions)\s+deploy|az\s+webapp\s+(deploy|up)|\beb\s+deploy|git\s+push\s+\S*heroku|aws\s+s3\s+(sync|cp)\b[^|;&]*s3://' +
    '|(^|[\s;|&(])(mail|mailx|sendmail|msmtp|mutt)\s+(-|\S+@)|twilio\s+api|hooks\.slack\.com|api\.telegram\.org/bot|stripe\s+(charges|payment_intents|refunds|payouts)\s+create|curl\b[^|;&]*(-X|--request)\s+DELETE\b[^|;&]*https://(?!localhost)' +
    '|shutil\.rmtree|\brmSync\(|\brimraf\s'
$script:SecretRe = '(^|[\s;|&(])(cat|less|more|head|tail|grep|rg|type|Get-Content|gc|printenv|env|strings|awk|sed|xxd|od|base64|hexdump|bat|nl|cut|sort|tac|Select-String|sls|cp|copy|Copy-Item|scp|python3?|node|perl|ruby|php|source|\.)\b[^|;&]*(\bsecrets?[\\/.]|(^|[\s/\\"''])(?!process\.env|import\.meta\.env)[\w.*-]*\.env(rc)?(?!\.example)(\.\w+)?\b|\.pem\b|\.key\b|id_rsa|id_ed25519|credentials|\.(netrc|npmrc|pypirc|git-credentials|pgpass)\b|\.docker/config\.json|\.kube/config|service[-_]?account\S*\.json)' +
    '|docker\s+(compose\s+)?(exec|inspect)[^|;&]*\b(env|printenv|\.env)\b|docker\s+(container\s+)?inspect\b(?![^|;&]*(--format|-f\s))|git\s+(show|log|diff)[^|;&]*\.env(?!\.example)\b' +
    '|(^|[\s;|&(])((printenv|env)(\s+[A-Za-z_]\w*)?|set|export\s+-p|declare\s+-x)\s*($|[;|&)])|\$env:\w*(KEY|SECRET|TOKEN|PASS|PWD|URL|DSN|CRED|AUTH|PRIVATE|API)|(Get-ChildItem|gci|ls|dir|Get-Item|gi)\s+env:|cmd\s+/c\s+set\b' +
    '|echo\s+"?\$\{?[A-Za-z_]*(KEY|SECRET|TOKEN|PASS|PWD|URL|DSN|CRED|AUTH|PRIVATE|API)' +
    '|\bsops\s+(-d|--decrypt)|\bop\s+(read|item\s+get)|\bvault\s+(kv\s+get|read)\b|\bpass\s+show\b|gcloud\s+auth\s+print-access-token|az\s+account\s+get-access-token|aws\s+(secretsmanager\s+get-secret-value|ssm\s+get-parameters?\b[^|;&]*--with-decryption)|kubectl\s+get\s+secrets?\b[^|;&]*(-o|--output)|heroku\s+config(?!:set)|vercel\s+env\s+pull|doppler\s+secrets|dotenv\s+-p\b'
# правка файлов-инструкций через оболочку (guard-instructions видит только Write/Edit)
$script:InstrPathShellRe = '(^|[\s/"''=])(CLAUDE(\.local|\.starter)?\.md|AGENTS\.md|\.mcp\.json|\.claude\.json|\.claude[/\\](rules|skills|hooks|agents|output-styles|commands|plugins|settings)[\w./\\-]*)'
$script:WriteVerbRe = '\b(sed\s+-[a-zA-Z]*i|perl\s+-[a-zA-Z]*i|tee|Set-Content|Out-File|Add-Content|New-Item|Copy-Item|Move-Item|Remove-Item|Rename-Item|Clear-Content|cp|mv|rm|ri|del|erase|chmod|chattr|attrib|truncate|ln|install|rsync|patch|git\s+(checkout|restore|apply|stash\s+pop)|python3?\s+-|dd|unzip|tar)\b|>|<<'

# Урок 12.09.2026 (5 повторов): файл кода, записанный через оболочку, минует проверки кириллицы и правил.
$script:ShellWriteRe = '(?:>>?|\b(?:tee|Set-Content|Out-File|Add-Content)\b[^|;&\n]{0,80}?)\s*[''"]?([^\s''";|&>]+\.(?:ts|tsx|js|jsx|mjs|cjs|vue|svelte|py|php|go|rs|java|kt|rb|cs|swift|dart|sh|bash|ps1|sql|prisma|html|htm|css|scss|less))\b'
function Get-ShellWriteTarget([string]$cmd) {
    # Путь файла кода, в который пишет команда; временные каталоги не считаются.
    foreach ($m in [regex]::Matches($cmd, $script:ShellWriteRe, 'IgnoreCase')) {
        $p = $m.Groups[1].Value
        $low = ($p -replace '\\', '/').ToLowerInvariant()
        if ($low.StartsWith('/tmp/') -or $low.StartsWith('/var/tmp/') -or $low.Contains('/temp/') -or $low.StartsWith('$env:temp') -or $low.StartsWith('/dev/')) { continue }
        return $p
    }
    return $null
}
function Invoke-GuardShell($data) {
    $cmd = [string](Get-Prop (Get-Prop $data 'tool_input') 'command')
    if ([string]::IsNullOrWhiteSpace($cmd)) { return }
    Invoke-GuardStatusShell $cmd $data
    if ($cmd -match $script:SshRe) {
        $bad = @()
        if ($cmd.Contains('<<')) { $bad += 'heredoc (<<)' }
        if ($cmd.Contains('$(')) { $bad += 'подстановка $(...)' }
        if ($cmd.Contains("'`"'`"'")) { $bad += "кавычки '`"'`"'" }
        if ($cmd.Contains("@'") -or $cmd.Contains('@"')) { $bad += 'here-string PowerShell (@'' / @")' }
        if ($cmd -match '(^|[\s;"''])[^\x00-\x7F]+=') { $bad += 'переменная с кириллицей' }
        if ($bad.Count -gt 0) {
            Out-Block @(
                ('Заблокировано: команда ssh содержит ' + ($bad -join ', ') + '.'),
                "Такие конструкции ломаются при передаче через оболочку. Запиши скрипт в файл (LF, ASCII-имя), отправь scp в /tmp и выполни: ssh <сервер> 'bash /tmp/<файл>.sh' (см. правило .claude/rules/code.md)."
            )
        }
    }
    $root = Get-ProjectDir $data
    if ((Test-UpdateMode $root) -and [regex]::IsMatch($cmd, 'docs[\\/]ai[\\/]', 'IgnoreCase') -and ($cmd -match $script:WriteVerbRe)) {
        Out-Block @('Идёт обновление набора (есть .claude/starter.lock), а команда пишет в docs/ai. docs/ai — записи владельца, их не трогают ни инструментом, ни командой. Закончи обновление, убери starter.lock, и только потом правь документы.')
    }
    $outs = @(Get-ShellOutsidePaths $cmd $root)
    if ($outs.Count -gt 0) {
        Out-Ask ('В команде путь вне папки проекта: ' + (($outs | Select-Object -First 3) -join ', ') + '. Папка этого проекта — ' + $root + '. Каждый проект работает только в своей папке: возьмите то же самое изнутри проекта, а если нужного здесь нет — скажите владельцу, что понадобилось снаружи и зачем, и получите «да».')
    }
    $tgt = Get-ShellWriteTarget $cmd
    if ($tgt) {
        Out-Ask ('Запись файла кода через оболочку: ' + $tgt + '. Так обходятся проверки набора — кириллица в именах, правила для этого типа файла, синтаксис. Пиши файлы инструментом Write или Edit; если нужно именно командой (генерация, сборка), скажи владельцу зачем и получи «да».')
    }
    if ($cmd -match $script:SecretRe) {
        Out-Ask 'Чтение секретов: значения ключей не выводить и не читать. Имена переменных взять из .env.example или спросить у владельца.'
    }
    if (($cmd -match $script:InstrPathShellRe) -and ($cmd -match $script:WriteVerbRe)) {
        if ($cmd -match '\.claude[/\\](hooks|settings)|\.claude\.json') {
            Out-Ask 'Изменение защит набора (разрешений или хуков) через оболочку. Покажите владельцу, что меняется, и получите «да».'
        }
        if (-not (Test-TrustFull)) {
            Out-Ask 'Изменение инструкций Claude через оболочку. Покажите владельцу, что меняется, и получите «да».'
        }
    }
    if (($cmd -match $script:InstallRe) -and -not (Test-TrustFull)) {
        Out-Ask 'Установка или запуск стороннего кода: нужна явная команда владельца именно на это (скилл compat-check выполнен?). Если «да» уже было — подтвердите.'
    }
    if ($cmd -match $script:DangerRe) {
        Out-Ask 'Опасное действие (данные, база, удаление, история git, инфраструктура). Перед выполнением: бэкап и «да» владельца.'
    }
    $mi = [regex]::Match($cmd, $script:InteractiveRe, 'IgnoreCase')
    if ($mi.Success) {
        Out-Deny ('Команда ждёт ввода с клавиатуры (' + $mi.Value.Trim() + ') — в Claude Code некому его дать, ход повиснет на минуты и часы. Переписать без ожидания: ключ «без вопросов» (-y, --yes, -m, BatchMode), вывод в файл вместо пейджера, редактор не открывать — править Write/Edit.')
    }
}

# ------------------------------------------------------------- guard-cyrillic
# все проверки кириллицы — через [regex]::IsMatch (с учётом регистра, как в Python re), а не -match.
$script:TripleQ = @('.py','.java','.kt','.swift','.cs','.dart','.graphql','.gql')
$script:BacktickRaw = @('.ts','.tsx','.js','.jsx','.mjs','.cjs','.vue','.svelte','.go')
$script:Heredoc = @('.sh','.bash','.ps1','.php','.rb')
$script:Typed = @('.java','.kt','.cs','.go','.rs','.swift','.dart','.php')
$script:CssLike = @('.css','.scss','.less','.graphql','.gql')
$script:DocExt = @('.md','.txt','.rst','.pdf','.doc','.docx','.xls','.xlsx','.ppt','.pptx','.odt','.rtf')
$script:I18nPath = '(^|/)(locales?|i18n|lang|langs|translations?|messages|l10n)/|(^|/|\.)(ru|en|uk|be|kk|uz|ky|tg|hy|ka|az|de|fr|es|it|pt|pl|cs|tr|zh|ja|ko|ar|he)([-_][A-Za-z]{2,4})?\.(json|ya?ml)$'
function Test-Re([string]$s, [string]$re) { return [regex]::IsMatch($s, $re) }
$script:KeepNl = [System.Text.RegularExpressions.MatchEvaluator]{ param($m) return ("`n" * ([regex]::Matches($m.Value, "`n").Count)) }
function Strip-Multiline([string]$text, [string]$ext, [string]$leaf) {
    $S = [System.Text.RegularExpressions.RegexOptions]::Singleline
    if (($script:CLike -contains $ext) -or (@('.json','.jsonc','.html','.htm') -contains $ext)) {
        $text = [regex]::Replace($text, '/\*.*?\*/', $script:KeepNl, $S)
    }
    if ($script:TripleQ -contains $ext) { $text = [regex]::Replace($text, '"""(?:\\.|[^\\])*?"""', $script:KeepNl, $S) }
    if (@('.py','.dart') -contains $ext) { $text = [regex]::Replace($text, "'''(?:\\.|[^\\])*?'''", $script:KeepNl, $S) }
    if ($script:BacktickRaw -contains $ext) { $text = [regex]::Replace($text, '`(?:\\.|[^`\\])*`', $script:KeepNl, $S) }
    if ($ext -eq '.rs') { $text = [regex]::Replace($text, 'r(#*)"[\s\S]*?"\1', $script:KeepNl) }
    if ($ext -eq '.cs') { $text = [regex]::Replace($text, '(?:@\$?|\$@)"(?:[^"]|"")*"', $script:KeepNl, $S) }
    if (($script:Markup -contains $ext) -or (@('.html','.htm') -contains $ext)) { $text = [regex]::Replace($text, '<!--.*?-->', $script:KeepNl, $S) }
    if (($script:Heredoc -contains $ext) -or ($leaf -match $script:SpecialNames)) {
        $text = [regex]::Replace($text, "<<[<~-]?\s*['`"]?(\w+)['`"]?[^\n]*\n.*?\n\s*\1\b", $script:KeepNl, $S)
        $text = [regex]::Replace($text, "@['`"]\n.*?\n['`"]@", $script:KeepNl, $S)
    }
    if ($ext -eq '.ps1') { $text = [regex]::Replace($text, '<#.*?#>', $script:KeepNl, $S) }
    if (@('.yaml','.yml') -contains $ext) {
        $lines = $text -split "`n"; $out = New-Object System.Collections.Generic.List[string]; $i = 0
        while ($i -lt $lines.Count) {
            $ln = $lines[$i]; $out.Add($ln)
            $m = [regex]::Match($ln, '^(\s*)(?:[^#\n]*:|-)\s*[|>][-+]?\s*$')
            if ($m.Success) {
                $ind = $m.Groups[1].Value.Length; $i++
                while ($i -lt $lines.Count -and ([string]::IsNullOrWhiteSpace($lines[$i]) -or (($lines[$i].Length - $lines[$i].TrimStart().Length) -gt $ind))) { $out.Add(''); $i++ }
                continue
            }
            $i++
        }
        $text = ($out -join "`n")
    }
    return $text
}
$script:JsRegexLit = '(?<![\w)\]])/(?![\s*/])(?:\\.|\[(?:\\.|[^\]\\])*\]|[^/\\\n\[])+/[a-z]*'
function Strip-Inline([string]$s, [string]$ext) {
    $s = [regex]::Replace($s, '"(?:\\.|[^"\\])*"', '""')
    $s = [regex]::Replace($s, "'(?:\\.|[^'\\])*'", "''")
    if ($script:JsLike -contains $ext) {
        $s = [regex]::Replace($s, '`[^`]*`', '``')
        $s = [regex]::Replace($s, $script:JsRegexLit, '/re/')
    }
    if (($script:HashComment -contains $ext) -or ($ext -match $script:SpecialNames)) { $s = [regex]::Replace($s, '(^|\s)#.*$', '') }
    if ($ext -eq '.php') { $s = [regex]::Replace($s, '(^|\s)#(?!\[).*$', '') }
    if (($script:CLike -contains $ext) -or (@('.html','.htm') -contains $ext)) {
        $s = [regex]::Replace($s, '//.*$', '')
        $s = [regex]::Replace($s, '/\*.*?(\*/|$)', '')
        $s = [regex]::Replace($s, '^\s*\*.*$', '')
    }
    if ($ext -eq '.sql') { $s = [regex]::Replace($s, '--.*$', ''); $s = [regex]::Replace($s, '(^|\s)#.*$', '') }
    return $s
}
function Strip-CommentsOnly([string]$s, [string]$ext) {
    if (($script:HashComment -contains $ext) -or ($ext -eq '.php') -or ($ext -match $script:SpecialNames)) { $s = [regex]::Replace($s, '(^|\s)#(?!\[).*$', '') }
    if ($script:CLike -contains $ext) { $s = [regex]::Replace($s, '//.*$', '') }
    return $s
}
function Strip-QuotesOnly([string]$s, [string]$ext) {
    $s = [regex]::Replace($s, "'(?:\\.|[^'\\])*'", "''")
    if (($script:HashComment -contains $ext) -or ($ext -eq '.php') -or ($ext -match $script:SpecialNames)) { $s = [regex]::Replace($s, '(^|\s)#(?!\[).*$', '') }
    if ($script:CLike -contains $ext) { $s = [regex]::Replace($s, '//.*$', '') }
    return $s
}
$script:CodeSegRe = '[=;(]|^\s*(?:export\s+|default\s+|async\s+|static\s+|public\s+|private\s+|protected\s+)*(?:class|function|interface|enum|type|const|let|var|def|if|for|while|switch|import|return|struct|model|namespace|foreach|catch|else|try|do|with|match|case|await|yield|new|throw|use)\b'
$script:KeyBeforeBraceLc = '^\s*(?![А-ЯЁ][а-яё])[\w$]*' + $script:CYR + $script:W + '\s*[:=]\s*$'
$script:KeyBeforeBraceAny = '^\s*[\w$]*' + $script:CYR + $script:W + '\s*[:=]\s*$'
$script:CodeTailRe = '[,;{(]\s*$'
function Strip-MarkupText([string]$s) {
    $s = [regex]::Replace($s, '>[^<>{}]*<', '><')
    $s = [regex]::Replace($s, '>[^<>{}]*$', '>')
    $s = [regex]::Replace($s, '^[^<>{}=;()]*<', '<')
    if (-not (Test-Re $s '[<>{}=;()\[\]]')) { return '' }
    if ($s.Contains('{')) {
        # без MatchEvaluator-замыкания: одинаково в Windows PowerShell 5.1 и PowerShell 7
        $codeTail = Test-Re $s $script:CodeTailRe
        $sb = New-Object System.Text.StringBuilder
        $pos = 0
        foreach ($m in [regex]::Matches($s, '(^|})([^{}<>]*)({|$)')) {
            [void]$sb.Append($s.Substring($pos, $m.Index - $pos))
            $seg = $m.Groups[2].Value
            if ((Test-Re $seg $script:CodeSegRe) -or (Test-Re $seg $script:KeyBeforeBraceLc) -or ($codeTail -and (Test-Re $seg $script:KeyBeforeBraceAny))) {
                [void]$sb.Append($m.Value)
            } else {
                [void]$sb.Append($m.Groups[1].Value + $m.Groups[3].Value)
            }
            $pos = $m.Index + $m.Length
        }
        [void]$sb.Append($s.Substring($pos))
        $s = $sb.ToString()
    }
    return $s
}
$script:DeclRe = '\b(const|let|var|function|class|def|interface|type|enum|fn|func|struct|impl|trait|package|namespace|import|from|as|lambda|export|public|private|protected|static|async|final|abstract|record|object|val|ENV|ARG|declare|local|readonly|module|property|event' +
    '|for|foreach|model|read|typedef|using|global|nonlocal|new|throw|raise|return|yield|await|del|if|elif|while|in|is|not|and|or|use|case|match|instanceof|typeof)\s+(?:-{0,2}\w+\s+)?[$*&]?_*' + $script:CYR
$script:CallRe = $script:CYR + $script:W + '\('
$script:MemberRe = '(?:[A-Za-z0-9_$)\]]\??\.|[Ѐ-ӿ]{3}\.|->)_*' + $script:CYR + '[\wЀ-ӿ$]'
$script:AssignRe = '(^|[\s;{(,])[\w$]*' + $script:CYR + $script:W + '\s*(?:,[^=\n]*)?(=[^=>]|:=|\+=|-=|\|\|=|\?\?=)'
$script:KeyRe = '(^|[{,])\s*[''"]?(?![А-ЯЁ][а-яё])[\w$]*' + $script:CYR + $script:W + '[''"]?\s*:(?!:)'
$script:KeyAnyRe = '(^|[{,])\s*[''"]?[\w$]*' + $script:CYR + $script:W + '[''"]?\s*:(?!:)'
$script:JsonKeyRe = '(^|[{,])\s*"[^"]*' + $script:CYR + '[^"]*"\s*:'
$script:TagRe = '<\s*/?\s*' + $script:CYR
$script:YamlKeyRe = '^\s*-?\s*[^:#''"\n]*' + $script:CYR + '[^:#\n]*:(\s|$)'
$script:YamlQKeyRe = '^\s*-?\s*["''][^"''\n]*' + $script:CYR + '[^"''\n]*["'']\s*:(\s|$)'
$script:YamlFlowRe = '[{,]\s*[^:,{}\s"'']*' + $script:CYR + '[^:,{}]*:'
$script:YamlEnvListRe = '^\s*-\s*[\w]*' + $script:CYR + $script:W + '='
$script:YamlTextKeyRe = '^\s*-?\s*[А-ЯЁ][а-яё][^:]*:\s*(?=.*(' + $script:CYR + '|[{$%]))'
$script:EnvLeftRe = '^\s*(export\s+)?[\w]*' + $script:CYR + $script:W + '\s*='
$script:ShellVarRe = '(^|[\s;])[\w]*' + $script:CYR + $script:W + '=|\$\{?' + $script:CYR + '|^\s*(function\s+)?' + $script:CYR + $script:W + '\s*\(\)'
$script:DollarRe = '\$\{?_*' + $script:CYR
$script:PsHashRe = '[{;]\s*_*' + $script:CYR + $script:W + '\s*='
$script:MakeRe = '^_*' + $script:CYR + $script:W + '\s*(?::|[:?+!]?=)'
$script:ParamCallRe = '[A-Za-z0-9_$\]>=]\s*\(|=>'
$script:ParamRe = '[(,]\s*(?:[\w.\[\]<>*&?]+\s+)?[*&$]*_*' + $script:CYR + $script:W + '\s*(?:[:,)=]|\s+[A-Za-z*\[][\w.\[\]*]*\s*[,)])'
$script:ArrowRe = '(^|[\s(,])_*' + $script:CYR + $script:W + '\s*=>'
$script:DestructRe = '[{\[,]\s*[$*&]*_*' + $script:CYR + $script:W + '\s*[,}\]=]'
$script:DecorRe = '^\s*@_*' + $script:CYR
$script:GenericRe = '<\s*' + $script:CYR
$script:CssSelRe = '(^|[\s,>+~(:])[#.]' + $script:CYR + '|--[\w-]*' + $script:CYR
$script:PrivateRe = '(^|[\s.;({,])#_*' + $script:CYR + $script:W + '\s*(?:[=;(,)}.]|$)'
$script:FieldRe = '^\s+_*' + $script:CYR + $script:W + '\s+[A-Za-z*\[@]'
$script:TypeDeclRe = '^\s*(?:[A-Za-z_][\w<>\[\],?.]*\s+)+[*&$]*_*' + $script:CYR + $script:W + '\s*[;=,)({]'
$script:StructLitRe = '[A-Za-z0-9_\]>]\{\s*_*' + $script:CYR + $script:W + '\s*:'
$script:SymbolRe = '(^|[\s(,\[]):_*' + $script:CYR
$script:TomlTableRe = '^\s*\[\[?\s*[^\]]*' + $script:CYR
$script:TemplateExprRe = '\$\{\s*[\w$.]*' + $script:CYR
$script:FstringRe = '\b[rR]?[fF][rR]?["'']'
$script:FstringExprRe = '(?<!\{)\{\s*[\w.]*' + $script:CYR
$script:RouteRe = '["''`]/(?!/)[\w/:.{}<>*@$~-]*' + $script:CYR
$script:DjangoPathRe = '\b(path|re_path|url)\(\s*r?["''][^"'']*' + $script:CYR
$script:GoTagRe = '`[^`]*\b\w+:"[^"`]*' + $script:CYR
$script:PrismaMapRe = '@@?map\(\s*"[^"]*' + $script:CYR
$script:AttrIdRe = '\b(id|class|className|for|name|slot)\s*=\s*["''][^"''<>]*' + $script:CYR
$script:AttrNameRe = '\s(?:data-|aria-|v-|x-|hx-|ng-|:|@)?[\w-]*' + $script:CYR + '[\w-]*\s*='
$script:AttrUrlRe = '\b(href|src|action|to|routerLink|formaction)\s*=\s*["''](?:/(?!/)|#|\.{0,2}/)[^"'']*' + $script:CYR
$script:AttrCodeRe = '(?:\s|^)(?:on\w+|@[\w.:-]+|v-[\w.:-]+|:[\w.-]+|x-[\w-]+|hx-[\w-]+|\*ng[A-Za-z]+|\[[\w.]+\]|\([\w.]+\)|formControlName|ng-[\w-]+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|''((?:[^''\\]|\\.)*)'')'
$script:TextLineRe = '^\s*(?:[А-ЯЁ][а-яё]|[А-ЯЁ]{2,}(?![а-яё\w])|[а-яё]+\s+[а-яё]|[а-яё]{1,2}\.|[«"“„+\d№•–—-])'
$script:TextTailRe = '=|[,;{(]\s*$'

function Test-AttrCodeHit([string]$raw) {
    foreach ($m in [regex]::Matches($raw, $script:AttrCodeRe)) {
        $val = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        $val = [regex]::Replace($val, "'[^']*'|``[^``]*``|`"[^`"]*`"", '')
        if (Test-Re $val $script:CYR) { return $true }
    }
    return $false
}
function Test-TextLine([string]$s) { return ((Test-Re $s $script:TextLineRe) -and -not (Test-Re $s $script:TextTailRe)) }

function Get-CyrillicProblems([string]$text, [string]$ext, [string]$leaf, [bool]$i18n) {
    $problems = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrEmpty($text) -or -not (Test-Re $text $script:CYR)) { return $problems }
    $special = ($leaf -match $script:SpecialNames)
    $origLines = $text -split "`n"
    $text = Strip-Multiline $text $ext $leaf
    $i = 0
    foreach ($raw in ($text -split "`n")) {
        $i++
        $orig = if (($i - 1) -lt $origLines.Count) { $origLines[$i - 1] } else { $raw }
        if (-not (Test-Re $raw $script:CYR) -and -not (Test-Re $orig $script:CYR)) { continue }
        $hit = $false
        if ($ext -eq '.json') {
            $hit = (Test-Re $raw $script:JsonKeyRe) -and -not $i18n
        } elseif ((@('.yaml','.yml') -contains $ext) -or ($special -and ($leaf -match '^(compose|docker-compose)'))) {
            $s = [regex]::Replace($raw, '(^|\s)#.*$', '')
            $hit = (Test-Re $s $script:YamlEnvListRe) -or ((-not $i18n) -and (Test-Re $s $script:YamlFlowRe))
            if (-not $hit -and -not $i18n) {
                if (Test-Re $s $script:YamlKeyRe) { $hit = -not (Test-Re $s $script:YamlTextKeyRe) }
                elseif (Test-Re $s $script:YamlQKeyRe) { $hit = $true }
            }
        } elseif ($ext -eq '.env') {
            $hit = (Test-Re $raw $script:EnvLeftRe)
        } else {
            $e = $ext; if ($special) { $e = '.sh' }
            $shell = (@('.sh','.bash','.ps1','.conf') -contains $e) -or $special
            $pre = Strip-CommentsOnly $orig $e
            if ($shell -or ($e -eq '.php')) {
                $q = Strip-QuotesOnly $orig $e
                if ((Test-Re $q $script:DollarRe) -or ((@('.ps1','.php') -contains $e) -and (Test-Re $q $script:MemberRe))) { $hit = $true }
            }
            if (-not $hit -and ($script:JsLike -contains $e) -and (Test-Re $pre $script:TemplateExprRe)) { $hit = $true }
            if (-not $hit -and ($e -eq '.py') -and (Test-Re $pre $script:FstringRe) -and (Test-Re $pre $script:FstringExprRe)) { $hit = $true }
            if (-not $hit -and ($script:CssLike -notcontains $e) -and ($e -ne '.sql') -and ((Test-Re $pre $script:RouteRe) -or (($e -eq '.py') -and (Test-Re $pre $script:DjangoPathRe)))) { $hit = $true }
            if (-not $hit -and ($e -eq '.go') -and (Test-Re $pre $script:GoTagRe)) { $hit = $true }
            if (-not $hit -and ($e -eq '.prisma') -and (Test-Re $pre $script:PrismaMapRe)) { $hit = $true }
            if (-not $hit -and ($script:Markup -contains $ext) -and ((Test-Re $pre $script:AttrIdRe) -or (Test-Re $pre $script:AttrUrlRe) -or (Test-AttrCodeHit $pre))) { $hit = $true }
            if ($hit) { $problems.Add(('строка ' + $i + ': ' + $orig.Trim())); continue }
            if (-not (Test-Re $raw $script:CYR)) { continue }
            $s = Strip-Inline $raw $e
            if (-not (Test-Re $s $script:CYR)) { continue }
            if ($script:Markup -contains $ext) {
                if (Test-Re $s $script:TagRe) { $problems.Add(('строка ' + $i + ': ' + $raw.Trim())); continue }
                $s = Strip-MarkupText $s
                if (-not (Test-Re $s $script:CYR)) { continue }
            }
            if ((Test-Re $s $script:AttrNameRe) -and ($script:Markup -contains $ext)) { $hit = $true }
            elseif ($e -eq '.sql') { $hit = $true }
            elseif ($shell) {
                $hit = ((Test-Re $s $script:ShellVarRe) -or (Test-Re $s $script:DeclRe) -or (Test-Re $s $script:CallRe))
                if (-not $hit -and $special -and ($leaf.ToLowerInvariant() -eq 'makefile')) { $hit = (Test-Re $s $script:MakeRe) }
                if (-not $hit -and ($e -eq '.ps1')) { $hit = (Test-Re $s $script:PsHashRe) }
            } else {
                if ((@('.go','.prisma') -contains $e) -and (Test-Re $s $script:FieldRe)) { $hit = $true }
                elseif (Test-TextLine $s) { continue }
                $hit = $hit -or (Test-Re $s $script:DeclRe) -or (Test-Re $s $script:CallRe) -or (Test-Re $s $script:MemberRe) -or (Test-Re $s $script:AssignRe) `
                    -or (Test-Re $s $script:ArrowRe) -or (Test-Re $s $script:DestructRe) -or (Test-Re $s $script:DecorRe) `
                    -or ((Test-Re $s $script:ParamCallRe) -and (Test-Re $s $script:ParamRe))
                if (-not $hit -and ($script:CLike -contains $e) -and ($script:Markup -notcontains $ext) -and ($script:CssLike -notcontains $e)) { $hit = (Test-Re $s $script:GenericRe) }
                if (-not $hit -and ($script:CLike -contains $e)) { $hit = (Test-Re $s $script:StructLitRe) }
                if (-not $hit -and ($script:CssLike -contains $e)) { $hit = (Test-Re $s $script:CssSelRe) }
                if (-not $hit -and ($script:JsLike -contains $e)) { $hit = (Test-Re $s $script:PrivateRe) }
                if (-not $hit -and ($script:Typed -contains $e)) { $hit = (Test-Re $s $script:TypeDeclRe) }
                if (-not $hit -and ($e -eq '.rb')) { $hit = (Test-Re $s $script:SymbolRe) }
                if (-not $hit -and ($e -eq '.toml')) { $hit = (Test-Re $s $script:TomlTableRe) }
                if (-not $hit -and ((Test-Re $s $script:KeyRe) -or ((Test-Re $s $script:CodeTailRe) -and (Test-Re $s $script:KeyAnyRe)))) {
                    if ($script:Markup -contains $ext) {
                        $after = ''; $idx = $s.IndexOf(':'); if ($idx -ge 0) { $after = $s.Substring($idx + 1) }
                        $hit = -not (Test-Re $after $script:CYR)
                    } else { $hit = $true }
                }
            }
        }
        if ($hit) { $problems.Add(('строка ' + $i + ': ' + $raw.Trim())) }
    }
    return $problems
}
function Get-CyrillicReport([string]$path, $text, [string]$root) {
    $p = $path -replace '\\', '/'
    $leaf = $p.Substring($p.LastIndexOf('/') + 1)
    $ext = Get-FileExt $leaf
    $isCode = ($script:CodeExt -contains $ext) -or ($leaf -match $script:SpecialNames)
    $problems = New-Object System.Collections.Generic.List[string]
    if (-not $isCode -and ($script:DocExt -contains $ext)) { return ,$problems }
    if (Test-Re $leaf $script:CYR) { $problems.Add('имя файла: ' + $leaf) }
    $rel = Get-RelPath $p $root
    if ($rel) {
        $parts = $rel -split '/'
        for ($k = 0; $k -lt $parts.Count - 1; $k++) { if (Test-Re $parts[$k] $script:CYR) { $problems.Add('папка: ' + $parts[$k]) } }
    }
    if ($isCode) {
        $i18nSrc = if ($rel) { $rel } else { $p }
        $i18n = [regex]::IsMatch($i18nSrc, $script:I18nPath, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($x in (Get-CyrillicProblems ([string]$text) $ext $leaf $i18n)) { $problems.Add($x) }
    }
    return ,$problems
}
function Invoke-GuardCyrillic($data) {
    $ti = Get-Prop $data 'tool_input'
    $path = [string](Get-Prop $ti 'file_path')
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    $text = Get-Prop $ti 'content'
    if ($null -eq $text) { $text = Get-Prop $ti 'new_string' }
    $problems = Get-CyrillicReport $path $text (Get-ProjectDir $data)
    if ($problems.Count -gt 0) {
        $lines = @('Заблокировано: кириллица в идентификаторах или путях кода (' + $path + ').')
        foreach ($x in ($problems | Select-Object -First 8)) { $lines += ('  - ' + $x) }
        $lines += 'Имена файлов, папок, маршрутов, переменных, функций, ключей и заголовков — только латиница. Русский текст — в строках, комментариях и тексте интерфейса. Файл переводов с русскими ключами — положить в папку locales/ (или i18n/, lang/).'
        Out-Block $lines
    }
}

# --------------------------------------------------------- guard-instructions
$script:InstrRe = '(^|/)(CLAUDE(\.local|\.starter)?\.md|AGENTS\.md|\.mcp\.json|\.claude\.json)$|(^|/)\.claude/(rules|skills|hooks|agents|output-styles|commands|plugins)/|(^|/)\.claude/settings[\w.]*\.json$'
# Защиты (разрешения и хуки) — вопрос при любом доверии: сам себе их Claude не отключает.
$script:ProtectRe = '(^|/)\.claude/(hooks/|settings[\w.]*\.json$)|(^|/)\.claude\.json$'
$script:LocalSettingsRe = '(^|/)\.claude/settings\.local\.json$'
$script:SafeModes = @('default', 'acceptEdits', 'plan')
function Test-LocalSettingsOk([string]$text, [string]$root) {
    # Личный файл доверия Claude пишет сам, если в нём только профиль: доверие, режим, стиль ответов.
    try { $o = $text | ConvertFrom-Json } catch { return $false }
    if ($null -eq $o) { return $false }
    foreach ($p in $o.PSObject.Properties) { if (@('env', 'permissions', 'outputStyle') -notcontains $p.Name) { return $false } }
    $trust = ''
    if ($o.env) {
        foreach ($p in $o.env.PSObject.Properties) { if ($p.Name -ne 'CLAUDE_TRUST_LEVEL') { return $false } }
        $trust = [string]$o.env.CLAUDE_TRUST_LEVEL
    }
    if ($o.permissions) {
        foreach ($p in $o.permissions.PSObject.Properties) { if ($p.Name -ne 'defaultMode') { return $false } }
        if ($o.permissions.defaultMode -and ($script:SafeModes -notcontains [string]$o.permissions.defaultMode)) { return $false }
    }
    if ($trust.ToLowerInvariant() -eq 'full') {
        try {
            $p = Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'PROFILE.md'
            if (-not [System.IO.File]::Exists($p)) { return $false }
            $prof = [System.IO.File]::ReadAllText($p, $script:Utf8)
            $m = [regex]::Match($prof, 'Доверие:\s*(осторожное|обычное|полное)', 'IgnoreCase')
            if (-not $m.Success -or $m.Groups[1].Value.ToLowerInvariant() -ne 'полное') { return $false }
        } catch { return $false }
    }
    return $true
}
function Test-UpdateMode([string]$root) {
    # Метка обновления набора: .claude/starter.lock со словом update, не старше часа.
    try {
        $p = Join-Path (Join-Path $root '.claude') 'starter.lock'
        if (-not [System.IO.File]::Exists($p)) { return $false }
        if (((Get-Date).ToUniversalTime() - [System.IO.File]::GetLastWriteTimeUtc($p)).TotalSeconds -gt 3600) { return $false }
        return ([System.IO.File]::ReadAllText($p, $script:Utf8).ToLowerInvariant().Contains('update'))
    } catch { return $false }
}
function Test-KitFileUntouched([string]$root, [string]$path) {
    # Файл набора, который владелец не менял: отпечаток совпадает с .claude/starter.json.
    try {
        $rel = Get-RelPath $path $root
        if (-not $rel) { return $false }
        $man = Read-Manifest $root
        if (-not $man -or -not $man.files) { return $false }
        $pr = $man.files.PSObject.Properties[$rel]
        if (-not $pr) { return $false }
        $full = Join-Path $root $rel
        if (-not [System.IO.File]::Exists($full)) { return $false }
        return ([string]$pr.Value -ceq (Get-FileHash16 $full))
    } catch { return $false }
}
function Invoke-GuardInstructions($data) {
    $ti = Get-Prop $data 'tool_input'
    $path = ([string](Get-Prop $ti 'file_path')) -replace '\\', '/'
    if ([string]::IsNullOrWhiteSpace($path) -or ($path -notmatch $script:InstrRe)) { return }
    $root = Get-ProjectDir $data
    if ((Test-UpdateMode $root) -and (Test-KitFileUntouched $root $path)) { return }
    if (($path -match '(^|/)CLAUDE\.md$') -and [System.IO.File]::Exists((Join-Path (Join-Path $root '.claude') 'starter.json')) -and -not [System.IO.File]::Exists((Join-Path $root 'INSTALL.md'))) {
        Out-Deny 'CLAUDE.md в проекте — ядро набора, его целиком заменяет обновление; правки в нём пропадут. Правило этого проекта — в .claude/rules/project.md (грузится всегда, набор его не трогает): строка с датой и словами владельца. Правило для части файлов — отдельный файл .claude/rules/ с paths.'
    }
    if ($path -match $script:LocalSettingsRe) {
        $text = Get-Prop $ti 'content'
        if (($null -ne $text) -and (Test-LocalSettingsOk ([string]$text) (Get-ProjectDir $data))) { return }
        Out-Ask ('Изменение личных настроек (' + $path + '). Показать владельцу, что меняется, и получить «да» — сам Claude пишет туда только доверие из PROFILE.md, режим правок и стиль ответов, целиком файлом (Write).')
    }
    if ($path -match $script:ProtectRe) {
        Out-Ask ('Изменение защит набора — разрешений или хуков (' + $path + '). Покажите владельцу, что меняется, и получите «да».')
    }
    if (-not (Test-TrustFull)) {
        Out-Ask ('Изменение инструкций Claude (' + $path + '). Покажите владельцу, что меняется, и получите «да».')
    }
}
# --------------------------------------------- работа только в своей папке проекта
function Get-OutsideProject([string]$path, [string]$root) {
    # Полный путь, если файл лежит вне папки проекта; иначе $null. Временные каталоги не считаются.
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    if ($path -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') { return $null }
    # «~» — домашняя папка, как os.path.expanduser в Python.
    if ($path -eq '~' -or $path.StartsWith('~/') -or $path.StartsWith('~\\')) {
        $home0 = [string]$env:HOME; if (-not $home0) { $home0 = [string]$env:USERPROFILE }
        if ($home0) { $path = $home0 + $path.Substring(1) }
    }
    $full = $null
    try { $full = [System.IO.Path]::GetFullPath($path) } catch { return $null }
    if ($null -ne (Get-RelPath $full $root)) { return $null }
    $low = (($full -replace '\\', '/').ToLowerInvariant()).TrimEnd('/')
    $temps = @($env:TEMP, $env:TMP, [System.IO.Path]::GetTempPath(), '/tmp', '/var/folders')
    foreach ($t in $temps) {
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        $t = ((([string]$t) -replace '\\', '/').ToLowerInvariant()).TrimEnd('/')
        if ($low -eq $t -or $low.StartsWith($t + '/')) { return $null }
    }
    return $full
}
$script:WinPathRe = '(?<![\w])([A-Za-z]:[\\/][^\s"''<>|;&)]+)'
$script:UnixPathRe = '(?<![\w/.\-])((?:/(?:home|srv|mnt|media|data|Users|root)|~)/[^\s"''<>|;&)]+)'
$script:SysPathRe = '[\\/](Windows|Program Files( \(x86\))?|ProgramData)[\\/]|[\\/](AppData|\.ssh)[\\/]'
$script:RemoteCmdRe = '(^|[\s;&|(])(ssh|scp|sftp|rsync|docker|kubectl)(\.exe)?\s'
function Get-ShellOutsidePaths([string]$cmd, [string]$root) {
    # Абсолютные пути в команде, которые ведут за пределы папки проекта (системные папки не считаются).
    # Пути вида /srv/... — чужие только на Linux/macOS; на Windows это сервер или контейнер,
    # а в командах ssh/scp/rsync/docker они всегда удалённые — их не проверяем.
    $out = @()
    $rxs = @($script:WinPathRe)
    $onWindows = ($env:OS -eq 'Windows_NT') -or ([System.IO.Path]::DirectorySeparatorChar -eq '\\')
    if ((-not $onWindows) -and (-not [regex]::IsMatch($cmd, $script:RemoteCmdRe, 'IgnoreCase'))) { $rxs += $script:UnixPathRe }
    foreach ($rx in $rxs) {
        foreach ($m in [regex]::Matches($cmd, $rx)) {
            $p = $m.Groups[1].Value.TrimEnd('.', ',', ':')
            if ([regex]::IsMatch($p, $script:SysPathRe, 'IgnoreCase')) { continue }
            $full = Get-OutsideProject $p $root
            if ($full -and ($out -notcontains $full)) { $out += $full }
        }
    }
    return $out
}
$script:AttachedDocs = @('PROFILE.md', 'STATE.md', 'LESSONS.md', 'INDEX.md')
$script:ReadBudget = 12
$script:ReadOnlyShellRe = '^\s*(?:ssh\s+\S+\s+)?["'']?\s*(?:cat|head|tail|less|grep|rg|egrep|fgrep|awk|wc|ls|dir|find|tree|type|stat|file|Get-Content|gc|Select-String|sls|Get-ChildItem|gci|Get-Item|Test-Path|git\s+(?:log|status|diff|show|blame|ls-files|grep)|sed\s+-n|python3?\s+-c\s+["'']?\s*(?:print|import\s+json)|jq|xxd|od|strings|du|df)\b'
function Invoke-AttachedDocNote($data) {
    # Подключённые документы уже в контексте: запретить чтение, если файл не менялся с начала хода.
    $path = ([string](Get-Prop (Get-Prop $data 'tool_input') 'file_path')) -replace '\\', '/'
    if (-not $path) { return }
    $name = $path.Split('/')[-1]
    if (-not (($script:AttachedDocs -contains $name) -and ('/' + $path).Contains('/docs/ai/'))) { return }
    try {
        $sf = Get-StateFile $data 'turn'
        if (Test-Path -LiteralPath $sf) {
            $snap = (Get-Content -LiteralPath $sf -Raw -Encoding UTF8) | ConvertFrom-Json
            $ts = [double](Get-Prop $snap 'ts')
            if ($ts -gt 0 -and (Test-Path -LiteralPath $path)) {
                $mt = [double]([DateTimeOffset](Get-Item -LiteralPath $path).LastWriteTimeUtc).ToUnixTimeSeconds()
                if ($mt -gt $ts) { return }
            }
        }
    } catch {}
    Out-Deny ('Набор: ' + $name + ' подключён к ядру и уже есть в контексте — читать его инструментом не нужно, отвечай по тому, что уже прочитано. Правил его в этом ходе — чтение разрешено автоматически.')
}
function Test-ReadOnlyCall($data) {
    $tool = [string](Get-Prop $data 'tool_name')
    if (@('Read', 'Grep', 'Glob') -contains $tool) { return $true }
    if (@('Bash', 'PowerShell') -contains $tool) {
        $cmd = [string](Get-Prop (Get-Prop $data 'tool_input') 'command')
        if ([string]::IsNullOrWhiteSpace($cmd)) { return $false }
        if ([regex]::IsMatch($cmd, $script:ShellWriteRe, 'IgnoreCase') -or [regex]::IsMatch($cmd, $script:WriteVerbRe, 'IgnoreCase')) { return $false }
        return [regex]::IsMatch($cmd, $script:ReadOnlyShellRe, 'IgnoreCase')
    }
    return $false
}
$script:ReadBudgetChars = 60000
$script:BigOutputChars = 20000
function Invoke-ReadBudget($data) {
    # Объём вывода инструментов, осевший в контексте за ход, и число чтений; один раз за ход — субагенту.
    $tool = [string](Get-Prop $data 'tool_name')
    if (-not (@('Read', 'Grep', 'Glob', 'Bash', 'PowerShell') -contains $tool)) { return }
    $size = 0
    try { $resp = Get-Prop $data 'tool_response'; if ($null -ne $resp) { $size = (ConvertTo-Json -InputObject $resp -Depth 6 -Compress).Length } } catch { $size = 0 }
    $sf = Get-StateFile $data 'turn'
    if (-not (Test-Path -LiteralPath $sf)) { return }
    $snap = $null
    try { $snap = (Get-Content -LiteralPath $sf -Raw -Encoding UTF8) | ConvertFrom-Json } catch { return }
    $reads = 0; try { $reads = [int](Get-Prop $snap 'reads') } catch {}
    $chars = 0; try { $chars = [int](Get-Prop $snap 'out_chars') } catch {}
    $warned = [bool](Get-Prop $snap 'budget_warned'); $bigWarned = [bool](Get-Prop $snap 'big_warned')
    if (Test-ReadOnlyCall $data) { $reads++ }
    $chars += $size
    $over = (-not $warned) -and (($reads -ge $script:ReadBudget) -or ($chars -ge $script:ReadBudgetChars))
    $big = (-not $over) -and (-not $bigWarned) -and ($size -ge $script:BigOutputChars)
    foreach ($kv in @(@('reads', $reads), @('out_chars', $chars))) {
        if ($null -eq (Get-Prop $snap $kv[0])) { $snap | Add-Member -NotePropertyName $kv[0] -NotePropertyValue $kv[1] } else { $snap.($kv[0]) = $kv[1] }
    }
    if ($over) { if ($null -eq (Get-Prop $snap 'budget_warned')) { $snap | Add-Member -NotePropertyName budget_warned -NotePropertyValue $true } else { $snap.budget_warned = $true } }
    if ($big) { if ($null -eq (Get-Prop $snap 'big_warned')) { $snap | Add-Member -NotePropertyName big_warned -NotePropertyValue $true } else { $snap.big_warned = $true } }
    try { ($snap | ConvertTo-Json -Depth 4 -Compress) | Set-Content -LiteralPath $sf -Encoding UTF8 } catch {}
    if ($over) {
        Out-Block @(('Набор: за этот ход в контекст уже легло около ' + [int][math]::Floor($chars / 1000) + ' тыс. знаков вывода инструментов (' + $reads + ' чтений) — всё это остаётся до конца сеанса и оплачивается в каждом запросе. Остальную разведку отдай субагенту с точным заданием (что найти, что вернуть: пути и строки), в основной контекст — только его итог; большой вывод — head, диапазон или grep, не целиком (kit-context §1).'))
    }
    if ($big) {
        Out-Block @(('Набор: один вывод на ' + [int][math]::Floor($size / 1000) + ' тыс. знаков осел в контексте целиком. Дальше — кусок (head, диапазон строк, grep по нужному), а не весь файл или весь вывод.'))
    }
}
function Invoke-PreRead($data) {
    # Один процесс на Read/Glob/Grep/NotebookEdit: чужая папка — вопрос владельцу; подключённый документ — пометка.
    Invoke-GuardOutside $data
    Invoke-AttachedDocNote $data
}
function Invoke-GuardOutside($data) {
    # Каждый проект работает в своей папке: файл снаружи — вопрос владельцу, даже при полном доверии.
    $ti = Get-Prop $data 'tool_input'
    $path = [string](Get-Prop $ti 'file_path')
    if (-not $path) { $path = [string](Get-Prop $ti 'path') }
    if (-not $path) { $path = [string](Get-Prop $ti 'notebook_path') }
    $root = Get-ProjectDir $data
    $full = Get-OutsideProject $path $root
    if ($null -eq $full) { return }
    Out-Ask ('Файл вне папки проекта: ' + $full + '. Папка этого проекта — ' + $root + '. Каждый проект работает только в своей папке: возьмите то же самое изнутри проекта, а если нужного здесь нет — скажите владельцу, что понадобилось снаружи и зачем, и получите «да».')
}
function Invoke-GuardDocsOnUpdate($data) {
    # Обновление набора не трогает документы проекта — ни одной правки в docs/ai.
    $root = Get-ProjectDir $data
    if (-not (Test-UpdateMode $root)) { return }
    $path = [string](Get-Prop (Get-Prop $data 'tool_input') 'file_path')
    if (-not $path) { return }
    $full = ''
    try { $full = [System.IO.Path]::GetFullPath($path) } catch { return }
    $rel = Get-RelPath $full $root
    if ($null -eq $rel) { return }
    if (($rel -replace '\\', '/') -match '^docs/ai/') {
        Out-Block @(('Идёт обновление набора (есть .claude/starter.lock), а правится документ проекта: ' + $rel),
            'Обновление заменяет только файлы набора; docs/ai — ваши записи, их не трогают.',
            'Закончи обновление, убери starter.lock, и только потом правь документы.')
    }
}
$script:AgentCap = "`n`n" + 'Предел: делать только названное в «Задача» и только в местах из «Где» — за их пределы не ходить, соседнее не изучать. Не нашёл за 6 вызовов — остановиться и вернуть, что найдено и где искал; всего не больше 15 вызовов. Упёрся во вход, окно разрешения, пустую или зависшую страницу, недоступный адрес — не ждать и не пробовать по кругу: вернуться сразу, первой строкой «нужно: <что именно>». Ответ — ровно по «Вернуть», без пересказа шагов.'
$script:AgentFormWords = @('задача', 'где', 'вернуть', 'стоп')
$script:AgentFormDeny = 'Задание субагенту без формы — он пойдёт «изучать» и потратит минуты впустую. Переписать задание четырьмя строками и вызвать снова: «Задача: <одно действие — найти / проверить / сделать что именно>» · «Где: <файлы, папки, адрес, таблица — конкретно>» · «Вернуть: <что и в каком виде: пути со строками, да/нет, таблица, счёт>» · «Стоп: <когда остановиться и что считать «не найдено»>». Слова владельца — цитатой, свои выводы и догадки в задание не писать. Разведка по коду — субагент scout (12 шагов, только чтение). Три файла и меньше — прочитать самому, без субагента.'
function Invoke-PreAgent($data) {
    # Субагенту — предел времени и вызовов прямо в задание (см. kit_hooks.py).
    $ti = Get-Prop $data 'tool_input'
    $prompt = [string](Get-Prop $ti 'prompt')
    if (-not $prompt) { return }
    foreach ($w in $script:AgentFormWords) { if (-not [regex]::IsMatch($prompt, ('(?im)^\W*' + $w + '\s*:'))) { Out-Deny $script:AgentFormDeny } }
    if ($prompt.Contains('Предел:')) { return }
    $new = @{}
    foreach ($pp in $ti.PSObject.Properties) { $new[$pp.Name] = $pp.Value }
    $new['prompt'] = $prompt.TrimEnd() + $script:AgentCap
    $o = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; updatedInput = $new } }
    Write-Out ($o | ConvertTo-Json -Depth 8 -Compress)
    exit 0
}
function Invoke-PreWrite($data) {
    # Один процесс на Write/Edit: обновление набора → чужая папка → кириллица → инструкции → правила.
    Invoke-GuardDocsOnUpdate $data
    Invoke-GuardStatusWrite $data
    Invoke-GuardOutside $data
    Invoke-GuardCyrillic $data
    Invoke-GuardInstructions $data
    Invoke-RulesOnWrite $data
}

# ------------------------------------------------------------ rules-on-write
function Convert-GlobToRegex([string]$pat) {
    $pat = ($pat -replace '\\', '/').TrimStart('.', '/')
    $out = ''; $i = 0
    while ($i -lt $pat.Length) {
        if ($pat.Substring($i).StartsWith('**/')) { $out += '(?:.*/)?'; $i += 3 }
        elseif ($pat.Substring($i).StartsWith('**')) { $out += '.*'; $i += 2 }
        elseif ($pat[$i] -eq '*') { $out += '[^/]*'; $i++ }
        elseif ($pat[$i] -eq '?') { $out += '[^/]'; $i++ }
        else { $out += [regex]::Escape([string]$pat[$i]); $i++ }
    }
    return ('^' + $out + '$')
}
function Expand-Braces([string]$pat) {
    $m = [regex]::Match($pat, '\{([^{}]*)\}')
    if (-not $m.Success) { return @($pat) }
    $res = @()
    foreach ($alt in ($m.Groups[1].Value -split ',')) {
        $res += Expand-Braces ($pat.Substring(0, $m.Index) + $alt + $pat.Substring($m.Index + $m.Length))
    }
    return $res
}
function Read-Rule([string]$path) {
    try { $txt = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF) } catch { return $null }
    $txt = $txt -replace "`r`n", "`n"
    $m = [regex]::Match($txt, '^---\n(.*?)\n---\n?(.*)$', 'Singleline')
    if (-not $m.Success) { return @{ paths = @(); body = $txt } }
    $fm = $m.Groups[1].Value; $body = $m.Groups[2].Value
    $paths = @()
    $pm = [regex]::Match($fm, '(?ms)^paths:\s*(.*?)(?=^\S|\z)')
    if ($pm.Success) {
        $blk = $pm.Groups[1].Value
        $inl = [regex]::Match($blk, '^\s*\[(.*)\]')
        if ($inl.Success) { $paths = @($inl.Groups[1].Value -split ',' | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ }) }
        else { $paths = @([regex]::Matches($blk, '(?m)^\s*-\s*(.+)$') | ForEach-Object { $_.Groups[1].Value.Trim().Trim('"', "'") }) }
    }
    return @{ paths = $paths; body = $body }
}
function Invoke-RulesOnWrite($data) {
    $path = ([string](Get-Prop (Get-Prop $data 'tool_input') 'file_path')) -replace '\\', '/'
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    $root = Get-ProjectDir $data
    $rel = Get-RelPath $path $root
    if (-not $rel -or $rel.StartsWith('.claude/') -or $rel.StartsWith('docs/')) { return }
    $rulesDir = Join-Path (Join-Path $root '.claude') 'rules'
    if (-not (Test-Path -LiteralPath $rulesDir)) { return }
    $sf = Get-StateFile $data 'rules'
    $done = @()
    try { if (Test-Path -LiteralPath $sf) { $done = @((Get-Content -LiteralPath $sf -Raw -Encoding UTF8) | ConvertFrom-Json) } } catch { $done = @() }
    $inject = @()
    foreach ($full in (Sort-Ordinal @(Get-ChildItem -LiteralPath $rulesDir -Filter *.md | ForEach-Object { $_.FullName }))) {
        $f = New-Object System.IO.FileInfo -ArgumentList $full
        if ($done -contains $f.Name) { continue }
        $r = Read-Rule $f.FullName
        if ($null -eq $r -or $r.paths.Count -eq 0 -or [string]::IsNullOrWhiteSpace($r.body)) { continue }
        $matched = $false
        foreach ($pat in $r.paths) { foreach ($p in (Expand-Braces $pat)) { if ($rel -match (Convert-GlobToRegex $p)) { $matched = $true; break } }; if ($matched) { break } }
        if ($matched) { $inject += ,@($f.Name, $r.body.Trim()) }
    }
    if ($inject.Count -eq 0) { return }
    $names = @($done) + @($inject | ForEach-Object { $_[0] })
    $sorted = Sort-Ordinal @($names | Select-Object -Unique)
    try { [System.IO.File]::WriteAllText($sf, (ConvertTo-Json -InputObject $sorted -Compress), (New-Object System.Text.UTF8Encoding($false))) } catch {}
    $text = 'Правила проекта для этого файла (из .claude/rules — соблюдать при записи):' + "`n`n" + (($inject | ForEach-Object { '### ' + $_[0] + "`n" + $_[1] }) -join "`n`n")
    $o = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; additionalContext = $text } }
    Write-Out ($o | ConvertTo-Json -Depth 5 -Compress)
}

# -------------------------------------------------------------- check-python
function Find-Python {
    foreach ($exe in @('py', 'python', 'python3')) {
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
        $pre = @(); if ($exe -eq 'py') { $pre = @('-3') }
        $a = $pre + @('-c', 'import sys; print(sys.version_info[0])')
        $v = & $exe @a 2>$null
        if ($LASTEXITCODE -eq 0 -and ("$v".Trim() -eq '3')) { return @{ exe = $exe; pre = $pre } }
    }
    return $null
}
function Test-Ps1Bom([string]$path) {
    # Урок 17.09.2026: .ps1 с русским текстом без BOM Windows PowerShell 5.1 читает как ANSI и падает.
    $raw = $null
    try { $raw = [System.IO.File]::ReadAllBytes($path) } catch { return }
    if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { return }
    $txt = ''
    try { $txt = $script:Utf8.GetString($raw) } catch { return }
    if (-not (Test-Re $txt $script:CYR)) { return }
    Out-Block @(('В файле есть русский текст, а BOM нет: ' + $path),
        'Windows PowerShell 5.1 прочитает такой файл как ANSI и упадёт на разборе.',
        ("Добавь BOM одной командой (PowerShell): `$p='" + $path + "'; [IO.File]::WriteAllText(`$p, [IO.File]::ReadAllText(`$p), (New-Object Text.UTF8Encoding(`$true)))"),
        'Либо оставь в файле только латиницу.')
}
$script:LayoutPropRe = '(?<![\w-])(width|min-width|max-width|height|min-height|max-height|margin(-\w+)?|padding(-\w+)?|position|z-index|float|overflow(-\w+)?|display|flex(-\w+)?|grid(-\w+)?|top|left|right|bottom|white-space|font-size)\s*:'
$script:StyleExt = @('.css', '.scss', '.sass', '.less', '.html', '.htm', '.vue', '.svelte', '.tsx', '.jsx')
# Конструкции, из которых получаются наезды: ловятся в момент записи, а не на экране владельца.
$script:LayoutBan = @(
    @('margin[\w-]*\s*:[^;{}]*(?<![\w(.])-\d', 'отрицательный margin — расстояния делаются gap и padding'),
    @('(?<![\w-])(left|right|top|bottom)\s*:\s*\d+(\.\d+)?%', 'положение в процентах — подписи и блоки ставит flex/grid, а не left: N%'),
    @('(?<![\w-])height\s*:\s*\d{2,}px', 'height в px — у блока с текстом только min-height (px допустим значку и аватару)'),
    @('(?<![\w-])width\s*:\s*\d{3,}px', 'жёсткая ширина контейнера в px — нужны %, fr, minmax(), max-width'),
    @('position\s*:\s*absolute', 'position: absolute — только значку в углу, с местом под него в родителе; текст и данные так не ставятся')
)
$script:LayoutBanTail = ' Запрещено правилами вёрстки (.claude/rules/layout.md) — переписать сейчас, до следующего шага: '
function Invoke-LayoutGuard($data) {
    # Write/Edit в файл стиля или разметки добавляет размер/положение — вернуть памятку (см. kit_hooks.py).
    $ti = Get-Prop $data 'tool_input'
    $path = [string](Get-Prop $ti 'file_path')
    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if (-not ($script:StyleExt -contains $ext)) { return }
    $hasNew = $null -ne ($ti.PSObject.Properties['new_string'])
    $added = ''
    if ($hasNew) { $added = [string](Get-Prop $ti 'new_string') } else { $added = [string](Get-Prop $ti 'content') }
    if ($hasNew) {
        $old = [string](Get-Prop $ti 'old_string')
        if ($old) { $added = (($added -split "`n") | Where-Object { $_.Trim() -and -not $old.Contains($_) }) -join "`n" }
    }
    $hits = @{}
    foreach ($l in ($added -split "`n")) {
        $m = [regex]::Match($l, $script:LayoutPropRe, 'IgnoreCase')
        if ($m.Success -and -not [regex]::IsMatch($l, 'var\(--|@apply|^\s*//')) { $hits[$m.Groups[1].Value.ToLowerInvariant()] = 1 }
    }
    if ($hits.Count -eq 0) { return }
    $list = @($hits.Keys | Sort-Object | Select-Object -First 6) -join ', '
    $banned = @(); foreach ($b in $script:LayoutBan) { if ([regex]::IsMatch($added, $b[0], 'IgnoreCase')) { $banned += $b[1] } }
    if (($banned.Count -eq 0) -and (Test-FastTurn (Get-TurnSnap $data))) { return }
    $ban = ''; if ($banned.Count -gt 0) { $ban = $script:LayoutBanTail + ($banned -join '; ') + '.' }
    Out-Block @('В ' + [System.IO.Path]::GetFileName($path) + ' добавлено размер/положение: ' + $list + '.' + $ban + ' Перед тем как идти дальше: 1) grep — где ещё применяется этот селектор/класс и на каких страницах; общий элемент — править в общем месте (тема, общий класс), не в экране; 2) значение из темы или из документа вида, не «сырое» число; 3) снимок до/после на КАЖДОЙ странице с этим элементом и на 320 px — ничего не наезжает, не обрезано, не уехало, длинные слова переносятся, таблица в .table-wrap; 4) владелец не называл этот размер — не добавлять, вернуть как было. Проверил — продолжай.')
}
function Invoke-CheckPython($data) {
    $path = [string](Get-Prop (Get-Prop $data 'tool_input') 'file_path')
    Invoke-LayoutGuard $data
    if ($path.ToLowerInvariant().EndsWith('.ps1') -and (Test-Path -LiteralPath $path)) { Test-Ps1Bom $path; return }
    if (-not $path.ToLowerInvariant().EndsWith('.py') -or -not (Test-Path -LiteralPath $path)) { return }
    $py = Find-Python; if ($null -eq $py) { return }
    $exe = $py.exe
    $a = @($py.pre) + @('-c', 'import ast,sys; ast.parse(open(sys.argv[1],"rb").read(), sys.argv[1])', $path)
    $global:LASTEXITCODE = 0
    $out = & $exe @a 2>&1
    if ($LASTEXITCODE -ne 0) {
        Out-Block @(('Синтаксическая ошибка Python в ' + $path + ' :'), (($out | Out-String).Trim()), 'Исправь до запуска и отправки.')
    }
}

# ---------------------------------------------------- turn-start / check-docs
function Get-GitStatusMap([string]$root) {
    $out = Invoke-Git $root @('status', '--porcelain', '--untracked-files=all')
    if ($null -eq $out) { return $null }
    $res = @{}
    foreach ($ln in ($out -split "`n")) {
        if ($ln.Length -lt 4) { continue }
        $st = $ln.Substring(0, 2); $f = $ln.Substring(3).Trim().Trim('"')
        if ($f.Contains(' -> ')) { $f = ($f -split ' -> ')[-1] }
        $f = $f -replace '\\', '/'
        $full = Join-Path $root $f
        $sig = 'gone'
        try {
            $it = New-Object System.IO.FileInfo -ArgumentList $full
            if ($it.Exists) { $sig = ([string]$it.LastWriteTimeUtc.Ticks) + ':' + [string]$it.Length }
            elseif ([System.IO.Directory]::Exists($full)) { $sig = 'dir' }
        } catch {}
        $res[$f] = @($st.Trim(), $sig)
    }
    return $res
}
# Слова владельца, после которых порядок «Как выдавать выбор» кладётся прямо перед ответом:
# правило в файле само не срабатывает, а вложенное хуком — срабатывает всегда.
$script:ChoiceRe = 'покажи\s+вариант|дай\s+вариант|список\s+вариант|какие\s+(есть|бывают|варианты)|что\s+есть\s+готов|сколько\s+(их\s+)?есть|выбрать\s+из|подбери|найди\s+(готов|шаблон|тем[уы]|библиотек|вариант|стартер)|покажи\s+(шаблон|тем[уы]|готов)|варианты\b'
$script:NotItRe = 'не\s+то\b|не\s+подходит|не\s+нравится|не\s+этого\s+хотел|не\s+так\s+сделал|опять\s+не\s+то|вс[её]\s+не\s+то'
$script:ChoiceHint = 'Набор: просят варианты. Порядок — SEARCH.md, «Как выдавать выбор»: слово понимать буквально (шаблон ≠ библиотека); идти в реестр с программным доступом (GitHub API, npm, PyPI), а не в память и не в один каталог; у каждого варианта только проверяемые поля из API — звёзды, лицензия, дата правки, адрес живой витрины; дать столько, сколько попросили; показывать витрины автора, а не свои превью; страница с поиском плюс верхушка списка прямо в ответе; отбор под стек — после показа всего; назвать своё мнение одним вариантом с причиной по делу; закончить одним шагом выбора. Бесплатное по умолчанию (SEARCH.md, «Деньги»).'
$script:NotItHint = 'Набор: владельцу «не то». Своё в следующий раз не переделывать — искать чужое готовое (скилл tool-scout, §0) и показать варианты по порядку ниже.'
$script:ExactRe = '!\s*точно|!\s*переделай|в\s*точности|дословно|я\s+(такого\s+)?не\s+говорил|не\s+просил|кто\s+(тебя\s+)?просил|отсебятин|от\s+себя|повторяю|в\s*\d+[-\s]*(й|ый|ой)\s*раз|сколько\s+раз|опять\s+придумыва|не\s+выдумывай|ничего\s+не\s+добавля|делай\s+(то\s+)?что\s+(тебе\s+)?говор|только\s+то,?\s+что\s+прош|не\s+надо\s+ничего\s+лишн'
$script:LiteralRe = 'точь[\s-]*в[\s-]*точь|один\s+в\s+один|пиксель\s+в\s+пиксель|одинаков|идентичн|ничем\s+не\s+отлич|так(ой|ая|ое|ие|ую|им|ого)\s+же|так\s+же,?\s+как|(^|[^\w])(копи[яюией]|скопир|клон)|100\s*%|как\s+(на|в)\s+(фото|снимк|картинк|скрин|оригинал|образц)'
$script:LiteralHint = 'Набор: в просьбе буквальное слово («точь-в-точь», «одинаково», «такое же», «копия», «100%»). Оно значит полное совпадение, а не «похоже» и не «в том же духе». До первой правки: 1) сказать одной строкой, что с чем должно совпасть и по чему это будет проверено; 2) слово можно отнести к разному (весь продукт вместе с его работой / только вид и стиль / один экран; всё или часть) либо буквально выполнить на выбранной основе нельзя — задать ОДИН вопрос с вариантами, что каждый значит и чего стоит, и закончить ход; прочтение подешевле молча не выбирать и «приблизительно» вместо «так же» не делать; 3) прочтение одно и выполнимо — делать буквально (вид по образцу — скилл clone-screen) и сдавать со сверкой, а не со словом «похоже».'
$script:ExactHint = 'Набор: владелец требует дословности. Порядок на этот ход: 1) выписать его просьбу по пунктам его словами; 2) сделать ровно это и ничего сверх — ни оформления, ни значка, ни рамки, ни колонки, ни подсказки, ни «заодно»; 3) против каждого пункта сказать, что сделано и чем доказано; 4) лишнее, добавленное раньше, удалить в этом же ходе; 5) формулировка непонятна — один короткий вопрос, а не догадка.'
function Get-ChoiceHint([string]$prompt) {
    # Подсказка перед ответом: владелец просит варианты или говорит «не то».
    $notIt = $prompt -match $script:NotItRe
    $choice = $prompt -match $script:ChoiceRe
    if (-not ($notIt -or $choice)) { return @() }
    if ($notIt) { return @($script:NotItHint, $script:ChoiceHint) }
    return @($script:ChoiceHint)
}
# ------------------------------------------------------------------ хронометраж
# Строка на каждый ответ: когда начали, сколько всего, сколько ждали инструменты,
# сколько думала модель, сколько токенов ушло, чем работали (модель, усилие, скорость),
# какие инструменты, куда смотрели и сам вопрос владельца. Файл только растёт.
$script:TimingHead = 'начало;всего_с;инструменты_с;модель_с;вызовов;запросов;вход_т;кэш_чт_т;кэш_зап_т;выход_т;думал_т;модель;усилие;скорость;вне_папки;инструменты;куда смотрел;вопрос;правок_кода;правок_док;повт_чтений;субагентов;субагент_с;возвратов;претензия;набор;старт'
$script:ComplaintRe = 'не\s+то\b|опять|снова\s+(не|то\s+же)|всё\s+равно|все\s+равно|не\s+работает|не\s+так|я\s+же\s+(сказал|говорил|просил)|сколько\s+(можно|раз)|чушь|бред|гуано|дерьм|кривo|крив(о|ая|ой|ые)|наезжа|заезжа|съехал|переделай|верни\s+как\s+было|почему\s+(так\s+)?долго|ничего\s+не\s+(измен|поменя|сдела)|ты\s+(не\s+)?(понял|слышишь)|в\s+(третий|четв[её]ртый|пятый|\d+)[-\s]*(й|ый)?\s*раз|не\s+вижу|ты\s+(мне\s+)?утверждаешь|а\s+сказать\s+нельзя|исполнен[оа]?\s+не\s+был|в\s+этом\s+и\s+проблема|где\s+(тут|же)\s|что\s+ты\s+(там\s+)?(выполня|дела)|жду\s+уже|тупой|тупишь|самовольнича|угадыва|я\s+(же\s+)?просил|не\s+просил|почему\s+не\s+выполня|делаешь\s+что\s+хочешь|что\s+я\s+(тебе\s+)?сказал'
$script:ComplaintHint = 'Набор: это претензия — прошлый ход сделан не так, как просили. Сразу не править. В ответе по порядку: 1) процитировать, что владелец просил (его словами); 2) сказать, что сделано на деле; 3) назвать разницу одной строкой, без оправданий; 4) если объём правки можно понять по-разному (эта строка / эта и соседние / весь блок; только это / и похожее) — один вопрос с вариантами и ждать; понятно однозначно — вернуть сделанное не по просьбе как было и сделать ровно названное. Экран увидеть не можешь — сказать это и описать словами, что именно изменится и что останется. Вторая претензия подряд по одному пункту — не делать третью попытку по догадке: только вопрос.'
$script:DocPathRe = '(^|[\\/])docs[\\/]|\.(md|txt)$'
$script:TimingTail = 1500000
$script:TimingSlow = 120.0
$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture
function Get-NowSec { return ([double][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) / 1000.0 }
function Get-IsoTs($value) {
    # '2026-09-17T20:06:25.028Z' -> секунды epoch; не разобралось — $null.
    # ConvertFrom-Json сам превращает такие строки в [datetime] — учитываем оба случая.
    if ($null -eq $value) { return $null }
    try {
        if ($value -is [DateTimeOffset]) { return ([double]$value.ToUnixTimeMilliseconds()) / 1000.0 }
        if ($value -is [datetime]) {
            $d = $value
            if ($d.Kind -eq [DateTimeKind]::Unspecified) { $d = [DateTime]::SpecifyKind($d, [DateTimeKind]::Utc) }
            return ([double]([DateTimeOffset]$d).ToUnixTimeMilliseconds()) / 1000.0
        }
        $text = ([string]$value).Trim()
        if (-not $text) { return $null }
        $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
        $dto = [DateTimeOffset]::Parse($text, $script:Inv, $styles)
        return ([double]$dto.ToUnixTimeMilliseconds()) / 1000.0
    } catch { return $null }
}
function Get-Cut([string]$s, [int]$n) {
    if ([string]::IsNullOrEmpty($s)) { return '' }
    if ($s.Length -le $n) { return $s }
    return $s.Substring(0, $n)
}
function Get-IntProp($obj, [string]$name) {
    $v = Get-Prop $obj $name
    if ($null -eq $v) { return 0 }
    try { return [int]$v } catch { return 0 }
}
function Get-ToolTarget($inp) {
    # «Куда смотрел»: файл, адрес, запрос или команда — одним коротким словом.
    if ($null -eq $inp) { return '' }
    foreach ($key in @('file_path', 'path', 'notebook_path')) {
        $v = [string](Get-Prop $inp $key)
        if ($v.Trim()) {
            $v = $v.Trim().Replace('\', '/').TrimEnd('/')
            $parts = @($v -split '/')
            $leaf = $parts[$parts.Count - 1]
            if ($leaf) { return $leaf }
            return $v
        }
    }
    $v = [string](Get-Prop $inp 'url')
    if ($v.Trim()) {
        $m = [regex]::Match($v.Trim(), '^https?://([^/]+)')
        if ($m.Success) { return $m.Groups[1].Value }
        return (Get-Cut $v.Trim() 40)
    }
    foreach ($key in @('query', 'pattern', 'prompt')) {
        $v = [string](Get-Prop $inp $key)
        if ($v.Trim()) { return (Get-Cut ([regex]::Replace($v.Trim(), '\s+', ' ')) 40) }
    }
    $v = [string](Get-Prop $inp 'command')
    if ($v.Trim()) {
        $parts = @(($v.Trim() -split '\s+') | Where-Object { $_ })
        $head = @($parts[0].Replace('\', '/') -split '/')[-1]
        if ((@('cd', 'sudo', 'env', 'time') -contains $head) -and $parts.Count -gt 1) {
            $head = @($parts[1].Replace('\', '/') -split '/')[-1]
        }
        return (Get-Cut $head 40)
    }
    return ''
}
function Get-TurnTools([string]$path, [double]$since) {
    # Хвост расшифровки: вызовы инструментов этого хода, время их ответов и расход токенов.
    $out = @{ uses = @(); results = @{};
              st = @{ req = 0; 'in' = 0; out = 0; think = 0; cread = 0; cwrite = 0; model = ''; effort = ''; speed = '' } }
    if ([string]::IsNullOrWhiteSpace($path)) { return $out }
    $raw = ''
    try {
        if (-not [System.IO.File]::Exists($path)) { return $out }
        $len = (New-Object System.IO.FileInfo $path).Length
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $skip = $false
            if ($len -gt $script:TimingTail) { [void]$fs.Seek($len - $script:TimingTail, [System.IO.SeekOrigin]::Begin); $skip = $true }
            $sr = New-Object System.IO.StreamReader($fs, $script:Utf8)
            if ($skip) { [void]$sr.ReadLine() }
            $raw = $sr.ReadToEnd()
        } finally { $fs.Dispose() }
    } catch { return $out }
    $uses = @()
    foreach ($line in ($raw -split "`n")) {
        # Разбираем только строки с вызовами инструментов и с расходом токенов.
        if ($line.IndexOf('tool_use') -lt 0 -and $line.IndexOf('"usage"') -lt 0) { continue }
        $rec = $null
        try { $rec = $line | ConvertFrom-Json } catch { continue }
        $ts = Get-IsoTs (Get-Prop $rec 'timestamp')
        if (($null -eq $ts) -or ($ts -lt $since)) { continue }
        $msg = Get-Prop $rec 'message'
        $usage = Get-Prop $msg 'usage'
        if ($null -ne $usage) {
            $out.st.req += 1
            $out.st['in'] += (Get-IntProp $usage 'input_tokens')
            $out.st.out += (Get-IntProp $usage 'output_tokens')
            $out.st.cread += (Get-IntProp $usage 'cache_read_input_tokens')
            $out.st.cwrite += (Get-IntProp $usage 'cache_creation_input_tokens')
            $det = Get-Prop $usage 'output_tokens_details'
            if ($null -ne $det) { $out.st.think += (Get-IntProp $det 'thinking_tokens') }
            $sp = [string](Get-Prop $usage 'speed')
            if ($sp) { $out.st.speed = $sp }
            $md = [string](Get-Prop $msg 'model')
            if ($md) { $out.st.model = $md.Replace('claude-', '') }
        }
        $eff = Get-Prop $rec 'perTurnEffort'
        if ($null -eq $eff) { $eff = Get-Prop $rec 'effort' }
        if ($eff) { $out.st.effort = [string]$eff }
        # @() обязательно: PowerShell разворачивает массив из одного элемента при возврате из функции.
        $content = @(Get-Prop $msg 'content')
        foreach ($b in $content) {
            if ($null -eq $b -or $b -is [string]) { continue }
            $type = [string](Get-Prop $b 'type')
            if ($type -eq 'tool_use') {
                $nm = [string](Get-Prop $b 'name'); if (-not $nm) { $nm = '?' }
                $uses += [pscustomobject]@{ Id = [string](Get-Prop $b 'id'); Name = $nm; Input = (Get-Prop $b 'input'); Ts = $ts }
            } elseif ($type -eq 'tool_result') {
                $tid = [string](Get-Prop $b 'tool_use_id')
                if ((-not $out.results.ContainsKey($tid)) -or ($ts -lt $out.results[$tid])) { $out.results[$tid] = $ts }
            }
        }
    }
    $out.uses = @($uses)
    return $out
}
function Get-CsvCell($text) {
    return ([regex]::Replace([string]$text, '\s+', ' ')).Replace(';', ',').Trim()
}
$script:SlowCallS = 600
function Set-SlowCall($data, $tt) {
    # Один вызов инструмента ждал дольше SlowCallS — запомнить для начала следующего хода.
    $worst = $null
    foreach ($u in @($tt.uses)) {
        if (-not $tt.results.ContainsKey($u.Id)) { continue }
        $dur = [double]$tt.results[$u.Id] - $u.Ts
        if ($dur -ge $script:SlowCallS -and ($null -eq $worst -or $dur -gt $worst.s)) { $worst = @{ s = [int]$dur; name = [string]$u.Name; target = (Get-Cut ([string](Get-ToolTarget $u.Input)) 80) } }
    }
    if ($null -eq $worst) { return }
    try { ($worst | ConvertTo-Json -Compress) | Set-Content -LiteralPath (Get-StateFile $data 'slow') -Encoding UTF8 } catch {}
}
function Get-SlowCallHint($data) {
    $p = Get-StateFile $data 'slow'
    if (-not (Test-Path -LiteralPath $p)) { return '' }
    $st = $null
    try { $st = (Get-Content -LiteralPath $p -Raw -Encoding UTF8) | ConvertFrom-Json; Remove-Item -LiteralPath $p -Force } catch { return '' }
    if ($null -eq $st) { return '' }
    $tg = [string](Get-Prop $st 'target'); if (-not $tg) { $tg = '…' }
    return ('В прошлом ходе один вызов ' + [string](Get-Prop $st 'name') + ' (' + $tg + ') ждал ' + [int][math]::Floor([int](Get-Prop $st 's') / 60) + ' мин. Так не бывает у команды, которая работает: это запрос разрешения без владельца рядом, ожидание ввода или скрипт без конца. Дальше: долгое — только с timeout и в фоне с логом (проверять выводом, не ждать); разрешение нужно — спросить владельца словами до запуска; ввод нужен — ключ «без вопросов». Что это было и чем заменено — одной строкой в ответе.')
}
function Get-TimingRow($data, $snap, [string]$root) {
    $start = 0.0
    try { $start = [double](Get-Prop $snap 'ts') } catch { $start = 0.0 }
    $total = (Get-NowSec) - $start
    if ($total -lt 0) { $total = 0.0 }
    $calls = 0; $toolS = 0.0; $names = @{}; $targets = @(); $outside = @()
    $qCode = 0; $qDocs = 0; $qRep = 0; $qAgents = 0; $qAgentS = 0.0; $qSeen = @{}
    $tt = Get-TurnTools ([string](Get-Prop $data 'transcript_path')) ($start - 1.0)
    $seen = @{}
    foreach ($u in @($tt.uses | Sort-Object Ts)) {
        if ($seen.ContainsKey($u.Id)) { continue }
        $seen[$u.Id] = $true
        $calls += 1
        if ($names.ContainsKey($u.Name)) { $names[$u.Name] = [int]$names[$u.Name] + 1 } else { $names[$u.Name] = 1 }
        if ($tt.results.ContainsKey($u.Id)) {
            $end = [double]$tt.results[$u.Id]
            if ($end -ge $u.Ts) { $toolS += ($end - $u.Ts) }
        }
        $qPath = [string](Get-Prop $u.Input 'file_path'); if (-not $qPath) { $qPath = [string](Get-Prop $u.Input 'notebook_path') }
        if ($u.Name -in @('Write', 'Edit', 'MultiEdit', 'NotebookEdit')) {
            if ([regex]::IsMatch($qPath, $script:DocPathRe, 'IgnoreCase')) { $qDocs += 1 } else { $qCode += 1 }
        } elseif ($u.Name -eq 'Read' -and $qPath) {
            $qk = ($qPath -replace '\\', '/').ToLowerInvariant()
            if ($qSeen.ContainsKey($qk)) { $qRep += 1 } else { $qSeen[$qk] = 1 }
        } elseif ($u.Name -eq 'Agent') {
            $qAgents += 1
            if ($tt.results.ContainsKey($u.Id)) { $qe = [double]$tt.results[$u.Id]; if ($qe -ge $u.Ts) { $qAgentS += ($qe - $u.Ts) } }
        }
        $tgt = Get-ToolTarget $u.Input
        if ($tgt -and ($targets -notcontains $tgt)) { $targets += $tgt }
        $fp = [string](Get-Prop $u.Input 'file_path')
        if (-not $fp) { $fp = [string](Get-Prop $u.Input 'path') }
        $out = Get-OutsideProject $fp $root
        if ($out -and ($outside -notcontains $out)) { $outside += $out }
    }
    if ($toolS -gt $total) { $toolS = $total }
    Set-SlowCall $data $tt
    $pairs = @()
    foreach ($k in (Sort-Ordinal @($names.Keys))) { $pairs += [pscustomobject]@{ N = $k; C = [int]$names[$k] } }
    $top = ((@($pairs | Sort-Object -Property @{ Expression = 'C'; Descending = $true } | Select-Object -First 6) | ForEach-Object { $_.N + '*' + $_.C }) -join ' ')
    $when = [DateTimeOffset]::FromUnixTimeMilliseconds([long]([Math]::Round($start * 1000))).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss', $script:Inv)
    $st = $tt.st
    $cells = @($when,
        $total.ToString('0.0', $script:Inv),
        $toolS.ToString('0.0', $script:Inv),
        ($total - $toolS).ToString('0.0', $script:Inv),
        [string]$calls,
        [string]$st.req, [string]$st['in'], [string]$st.cread, [string]$st.cwrite,
        [string]$st.out, [string]$st.think,
        (Get-CsvCell $st.model), (Get-CsvCell $st.effort), (Get-CsvCell $st.speed),
        [string]@($outside).Count,
        (Get-CsvCell $top),
        (Get-Cut (Get-CsvCell (@($targets | Select-Object -First 12) -join ' ')) 180),
        (Get-Cut (Get-CsvCell (Get-Prop $snap 'prompt')) 140))
    $qStops = 0; try { $qStops = [int](Get-Prop $snap 'stops') } catch { $qStops = 0 }
    $qRet = [Math]::Max(0, $(if ($qStops -lt 1) { 1 } else { $qStops }) - 1)
    $qCompl = '0'; if ((Get-Prop $snap 'complaint') -eq $true) { $qCompl = '1' }
    $cells += @([string]$qCode, [string]$qDocs, [string]$qRep, [string]$qAgents, $qAgentS.ToString('0', $script:Inv), [string]$qRet, $qCompl, (Get-CsvCell (Read-KitVersion $root)), (Get-CsvCell (Get-Prop $snap 'boot')))
    return ($cells -join ';')
}
function Get-TimingPath([string]$root) {
    return (Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'timing.csv')
}
function Get-TimingTail([string]$path, [int]$limit) {
    # Последние строки растущего файла без чтения его целиком.
    if (-not [System.IO.File]::Exists($path)) { return @() }
    try {
        $len = (New-Object System.IO.FileInfo $path).Length
        $back = [Math]::Min($len, [Math]::Max(4096, $limit * 400))
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            if ($back -lt $len) { [void]$fs.Seek($len - $back, [System.IO.SeekOrigin]::Begin) }
            $sr = New-Object System.IO.StreamReader($fs, $script:Utf8)
            if ($back -lt $len) { [void]$sr.ReadLine() }
            $text = $sr.ReadToEnd()
        } finally { $fs.Dispose() }
        $rows = @(($text -split "`n") | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_.Trim() -and -not $_.StartsWith('начало;') })
        return @($rows | Select-Object -Last $limit)
    } catch { return @() }
}
function Get-TimingSameTurn([string]$path, [string]$key) {
    # Смещение начала последней строки, если она про тот же ход; иначе $null.
    try {
        $len = (New-Object System.IO.FileInfo $path).Length
        $back = [Math]::Min($len, 8192)
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            [void]$fs.Seek($len - $back, [System.IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] $back
            [void]$fs.Read($buf, 0, $back)
        } finally { $fs.Dispose() }
        $text = $script:Utf8.GetString($buf)
        $lines = @($text -split "`n")
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
        if ($lines.Count -eq 0) { return $null }
        $last = $lines[$lines.Count - 1]
        if (-not $last.StartsWith($key + ';')) { return $null }
        return $len - ($script:Utf8.GetByteCount($last) + 1)
    } catch { return $null }
}
function Write-Timing($data, [string]$root) {
    # Вызывается при завершении ответа; повторный вызов того же хода строку заменяет.
    # Файл только растёт: старые ходы не стираются, чтобы по ним можно было смотреть историю.
    if (-not [System.IO.Directory]::Exists((Join-Path (Join-Path $root 'docs') 'ai'))) { return }
    $snap = $null
    try {
        $sf = Get-StateFile $data 'turn'
        if (Test-Path -LiteralPath $sf) { $snap = (Get-Content -LiteralPath $sf -Raw -Encoding UTF8) | ConvertFrom-Json }
    } catch { $snap = $null }
    if ($null -eq $snap -or -not (Get-Prop $snap 'ts')) { return }
    # Сколько раз ход подходил к концу: больше одного — возвращал хук.
    try {
        $stops = 0; try { $stops = [int](Get-Prop $snap 'stops') } catch { $stops = 0 }
        $snap | Add-Member -NotePropertyName stops -NotePropertyValue ($stops + 1) -Force
        ($snap | ConvertTo-Json -Depth 4 -Compress) | Set-Content -LiteralPath (Get-StateFile $data 'turn') -Encoding UTF8
    } catch {}
    $row = ''
    try { $row = Get-TimingRow $data $snap $root } catch { return }
    if (-not $row) { return }
    $path = Get-TimingPath $root
    try {
        if ([System.IO.File]::Exists($path)) {
            $first = ''
            $sr = New-Object System.IO.StreamReader($path, $script:Utf8)
            try { $first = ([string]$sr.ReadLine()).TrimEnd("`r").TrimStart([char]0xFEFF) } finally { $sr.Dispose() }
            if (($first -ne $script:TimingHead) -and $first -and $script:TimingHead.StartsWith($first)) {
                # Добавились столбцы справа: заголовок заменить, историю оставить (старые строки короче).
                $all = [System.IO.File]::ReadAllText($path, $script:Utf8).TrimStart([char]0xFEFF)
                $nl = $all.IndexOf("`n")
                $rest = ''; if ($nl -ge 0) { $rest = $all.Substring($nl + 1) }
                [System.IO.File]::WriteAllText($path, ($script:TimingHead + "`n" + $rest), $script:Utf8)
            } elseif ($first -ne $script:TimingHead) {
                # Колонки сменились: старый файл отложить целиком, новый начать с заголовка.
                $old = Join-Path (Split-Path -Parent $path) 'timing.old.csv'
                if ([System.IO.File]::Exists($old)) { [System.IO.File]::Delete($old) }
                [System.IO.File]::Move($path, $old)
            }
        }
        if (-not [System.IO.File]::Exists($path)) {
            [System.IO.File]::WriteAllText($path, ($script:TimingHead + "`n"), $script:Utf8)
        }
        $cut = Get-TimingSameTurn $path (@($row -split ';')[0])
        if ($null -ne $cut) {
            $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            try { $fs.SetLength([long]$cut) } finally { $fs.Dispose() }
        }
        $bytes = $script:Utf8.GetBytes($row + "`n")
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
    } catch {}
}
$script:CtxLimit = 150000
function Get-ContextPerRequest([string]$row) {
    $p = @($row -split ';')
    if ($p.Count -lt 11) { return $null }
    try {
        $req = [int]$p[5]
        if ($req -lt 2) { return $null }
        return ([double]([int]$p[6] + [int]$p[7] + [int]$p[8])) / $req
    } catch { return $null }
}
function Get-ContextHint([string]$root) {
    # Контекст на один запрос по логу. Раздут — сказать один раз при переходе порога и потом каждый
    # пятый ход, а не каждый: иначе напоминание становится обоями (ERP: 41 ход из 42 над порогом).
    # @() обязательно: одна строка возвращается как строка, и $rows[0] дал бы первый символ.
    $rows = @(Get-TimingTail (Get-TimingPath $root) 12)
    if ($rows.Count -eq 0) { return '' }
    $ctx = Get-ContextPerRequest $rows[$rows.Count - 1]
    if ($null -eq $ctx -or $ctx -lt $script:CtxLimit) { return '' }
    $streak = 0
    for ($i = $rows.Count - 1; $i -ge 0; $i--) {
        $c = Get-ContextPerRequest $rows[$i]
        if ($null -eq $c -or $c -lt $script:CtxLimit) { break }
        $streak++
    }
    if ($streak -ne 1 -and ($streak % 5) -ne 0) { return '' }
    $k = [int][math]::Floor($ctx / 1000)
    return ('Набор: контекст около ' + $k + ' тыс. токенов на каждый запрос — каждый ход дорожает и замедляется. Когда текущая просьба выполнена: одной-двумя строками записать итог в STATE.md («Сейчас», «Следующий шаг»; полный порядок — kit-handover, если тема большая) и последней строкой ответа сказать владельцу: «Тема записана — введите /clear, контекст ~' + $k + ' тыс.». Посреди начатой правки или незаданного вопроса не обрывать.' + "`n")
}
function Get-TimingNotice([string]$root) {
    # Одна строка при старте сеанса: куда уходит время и стоит ли разбираться.
    $tot = @(); $too = @(); $tok = @(); $outside = 0
    foreach ($r in (Get-TimingTail (Get-TimingPath $root) 20)) {
        $p = @($r -split ';')
        if ($p.Count -lt 15) { continue }
        try {
            $tot += [double]::Parse($p[1], $script:Inv)
            $too += [double]::Parse($p[2], $script:Inv)
            $tok += ([double][int]$p[6] + [int]$p[7] + [int]$p[8] + [int]$p[9])
            if ([int]$p[14] -gt 0) { $outside += 1 }
        } catch {}
    }
    if ($tot.Count -lt 10) { return $null }
    $avg = ($tot | Measure-Object -Sum).Sum / $tot.Count
    $avgT = ($too | Measure-Object -Sum).Sum / $too.Count
    $avgK = ($tok | Measure-Object -Sum).Sum / $tok.Count / 1000.0
    $share = 0
    if ($avg -gt 0) { $share = [int][Math]::Round(100 * $avgT / $avg) }
    $slow = @($tot | Where-Object { $_ -ge $script:TimingSlow }).Count
    $tail = ''
    if ($slow -ge 3) { $tail = ' Долгих (от 2 мин) — ' + $slow + ' из ' + $tot.Count + ': предложить владельцу /kit-timing.' }
    if ($outside -gt 0) { $tail += ' В ' + $outside + ' ходах трогали файлы вне папки проекта — так нельзя, работать только в ' + $root + '.' }
    return ('Хронометраж: последние ' + $tot.Count + ' ответов — в среднем ' + $avg.ToString('0', $script:Inv) + ' с, из них в инструментах ' + $avgT.ToString('0', $script:Inv) + ' с (' + $share + '%), токенов на ход около ' + $avgK.ToString('0', $script:Inv) + ' тыс.' + $tail)
}
# ------------------------------------------- секрет, вставленный владельцем в чат
$script:PastedSecretRe = 'sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[0-9A-Za-z_-]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(?:\b(?:setx|export|set)\s+\w*(?:KEY|TOKEN|SECRET|PASS)\w*[=\s]+["'']?)([^\s"'']{8,})|(?:\b(?:api[_-]?key|token|secret|password|passwd|пароль)\s*[:=]\s*["'']?)([A-Za-z0-9!@#$%^&*()_+=\-\[\]{}.,;/\\|~]{8,})'
$script:SecretHint = 'Набор: в сообщении владельца похоже на секрет (ключ, токен или пароль). Дал его сам для задачи — пользоваться в командах этой задачи, не переспрашивая; в файлы, документы и git не записывать (постоянное место — переменная среды или .env у владельца). Попал случайно (вывод, лог, снимок) — первой строкой сказать сменить.'
function Hide-Secrets([string]$text) {
    # Значение секрета в логе заменяется меткой; имя переменной и команда остаются.
    $ev = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $whole = $m.Value
        foreach ($g in 1, 2) {
            $v = $m.Groups[$g].Value
            if ($v) { return ($whole.Substring(0, $whole.Length - $v.Length) + '<секрет>') }
        }
        return '<секрет>'
    }
    return [regex]::Replace($text, $script:PastedSecretRe, $ev, 'IgnoreCase')
}
# ------------------------------------------- второй сеанс Claude в той же папке
$script:SessionLockMin = 10
function Get-SessionLockPath([string]$root) { return (Join-Path (Join-Path $root '.claude') 'session.lock') }
function Set-SessionClaim($data, [string]$root) {
    # Записать себя как текущий сеанс папки; вернуть предупреждение, если тут только что работал другой.
    $lock = Get-SessionLockPath $root
    $sid = [string](Get-Prop $data 'session_id')
    $notice = ''
    try {
        if ([System.IO.File]::Exists($lock)) {
            $j = ([System.IO.File]::ReadAllText($lock, $script:Utf8)) | ConvertFrom-Json
            $ts = [double](Get-Prop $j 'ts')
            $age = [double]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) - $ts
            $osid = [string](Get-Prop $j 'sid')
            if ($sid -and $osid -and ($osid -ne $sid) -and ($age -ge 0) -and ($age -lt ($script:SessionLockMin * 60))) {
                $notice = ('Набор: в этой папке работает ещё один сеанс Claude (его последний ход — ' + [int][math]::Floor($age / 60) + ' мин назад). Два сеанса в одной папке затирают правки друг друга и делают одну работу дважды. Первой строкой предупредить владельца и до его ответа ничего не править — только читать и отвечать.')
            }
        }
    } catch {}
    try {
        $dir = Split-Path -Parent $lock
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        [System.IO.File]::WriteAllText($lock, ('{"sid": ' + (ConvertTo-Json $sid) + ', "ts": ' + $now + '}'), $script:Utf8)
    } catch {}
    return $notice
}
# ------------------------------------------- указатель сам подсказывает, куда идти
$script:IndexStop = @('котор','можно','нужно','сдела','прове','посмо','почем','тоест','непон','давай','чтобы','потом','сейча','проек','докум','запис','данны','файлы','файла','папку','папка','папке','скажи','напиш','добав','убери','попра','измен','после','перед','этого','этому','вопро','ответ','работ','нужен','нужна','какой','какая','какие','когда','откуд','зачем','через','всегд','подкл','сразу','тольк','опять','снова','ничег','всего','больш','меньш','просто')
$script:IndexAttached = @('PROFILE.md','STATE.md','LESSONS.md','INDEX.md')
function Get-IndexStems([string]$text) {
    $out = @()
    foreach ($m in [regex]::Matches($text.ToLowerInvariant(), '[а-яёa-z]+')) {
        $w = $m.Value
        if ($w.Length -lt 5) { continue }
        $st = $w.Substring(0, 5)
        if (($script:IndexStop -contains $st) -or ($out -contains $st)) { continue }
        $out += $st
    }
    return $out
}
function Get-IndexHint([string]$root, [string]$prompt) {
    $stems = @(Get-IndexStems $prompt)
    if ($stems.Count -eq 0) { return '' }
    $p = Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'INDEX.md'
    if (-not [System.IO.File]::Exists($p)) { return '' }
    $txt = ''
    try { $txt = [System.IO.File]::ReadAllText($p, $script:Utf8).TrimStart([char]0xFEFF) } catch { return '' }
    $best = @()
    foreach ($line in ($txt -split "`n")) {
        if (-not $line.StartsWith('|')) { continue }
        $cells = @(($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -lt 2 -or $cells[0].StartsWith('---') -or $cells[0].ToLowerInvariant().StartsWith('файл')) { continue }
        $name = ($cells[0] -replace '`', '').Trim()
        $skip = $false
        foreach ($a in $script:IndexAttached) { if ($name.EndsWith($a)) { $skip = $true } }
        if ($skip -or $name.Contains('timing')) { continue }
        $low = $line.ToLowerInvariant()
        $hit = @($stems | Where-Object { $low.Contains($_) })
        if ($hit.Count -gt 0) {
            $best += ,@($hit.Count, (-$line.Length), $name, (Get-Cut $cells[1] 70), $hit)
        }
    }
    if ($best.Count -eq 0) { return '' }
    $sorted = @($best | Sort-Object -Property @{Expression={$_[0]}; Descending=$true}, @{Expression={$_[1]}; Descending=$true})
    $top = @($sorted | Select-Object -First 2 | Where-Object { $_[0] -ge $sorted[0][0] })
    $docs = ($top | ForEach-Object { $_[2] + ' (' + $_[3] + ')' }) -join '; '
    $words = (@($top[0][4] | Select-Object -First 2) | ForEach-Object { '«' + $_ + '…»' }) -join ', '
    return ('Указатель: по словам запроса (' + $words + ') подходит ' + $docs + ' — сначала посмотреть там, и только если ответа нет, идти в код или на сервер.')
}
# ------------------------------------------- «доделывай» без предмета: брать пункты по порядку, не стоять
$script:VagueRe = '^\W*(доделывай|доделай|продолжай|продолжи|дальше|давай дальше|остальное|делай|работай|ну что)\W*$'
$script:VagueHint = 'Набор: владелец не назвал предмет. Взять пункты из «Следующий шаг» в STATE.md по порядку: каждый — сделать, проверить, закоммитить, одна строка отчёта — и следующий, пока не кончатся или владелец не вмешается. Что ждёт владельца — записать в «Ждёт владельца» и пропустить, не стоять. Вопрос, на который ответит эталон, код, сервер или интернет, — задать им, не владельцу.'
function Get-StateSection([string]$txt, [string]$title) {
    $m = [regex]::Match($txt, '(?ms)^## ' + [regex]::Escape($title) + '[^\n]*\n(.*?)(?=^## |\z)')
    if ($m.Success) { return $m.Groups[1].Value } else { return '' }
}
function Get-WaitingNotice([string]$root) {
    $p = Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'STATE.md'
    if (-not [System.IO.File]::Exists($p)) { return '' }
    $txt = ''
    try { $txt = [System.IO.File]::ReadAllText($p, $script:Utf8).TrimStart([char]0xFEFF) } catch { return '' }
    $item = '^\s*(\d+[а-я]?[.)]|[-*•])\s*\S'
    $wait = @((Get-StateSection $txt 'Ждёт владельца') -split "`n" | Where-Object { [regex]::IsMatch($_, $item) -and -not [regex]::IsMatch($_, '[—-]\s*$') })
    $nxt = @((Get-StateSection $txt 'Следующий шаг') -split "`n" | Where-Object { [regex]::IsMatch($_, $item) })
    if ($wait.Count -eq 0 -or $nxt.Count -eq 0) { return '' }
    $first = [regex]::Replace([regex]::Replace($nxt[0], '^\s*(\d+[а-я]?[.)]|[-*•])\s*', ''), '\s+', ' ').Trim('*', ' ')
    $first = Get-Cut $first 90
    return ('Ждёт владельца: ' + $wait.Count + ' пункт(а) — их не ждать и не переспрашивать. Следующий шаг: «' + $first + '» — брать его и идти по списку дальше.')
}
# ------------------------------------------- главная задача: последняя строка ответа, вопрос не останавливает
$script:MainTaskTail = 'Параллельно выполняю главную задачу'
$script:MainTaskWait = 'Жду вашего решения по главной задаче'
$script:MainTaskEmptyRe = '^(—|-|–|нет|пусто|TODO.*|\(.*\))?$'
function Get-MainTask([string]$root) {
    # «Главная задача:» в «Сейчас» STATE.md — ТЗ владельца; живёт там, пока он не сказал «готово».
    $p = Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'STATE.md'
    if (-not [System.IO.File]::Exists($p)) { return '' }
    $txt = ''
    try { $txt = [System.IO.File]::ReadAllText($p, $script:Utf8).TrimStart([char]0xFEFF) } catch { return '' }
    $m = [regex]::Match($txt, '(?m)^\s*(?:[-*•]\s*)?\**Главная задача\**\s*:\s*(.*?)\s*$')
    if (-not $m.Success) { return '' }
    $v = $m.Groups[1].Value.Trim('*', ' ').Trim()
    if ([regex]::IsMatch($v, $script:MainTaskEmptyRe, 'IgnoreCase')) { return '' }
    return (Get-Cut ([regex]::Replace($v, '\s+', ' ')) 120)
}
function Get-LastAnswer([string]$path, [double]$since) {
    # Последний текст ответа Claude в этом ходе — чтобы проверить его последнюю строку.
    $last = ''; $lastTs = -1.0
    if ([string]::IsNullOrWhiteSpace($path)) { return '' }
    $raw = ''
    try {
        if (-not [System.IO.File]::Exists($path)) { return '' }
        $len = (New-Object System.IO.FileInfo $path).Length
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $skip = $false
            if ($len -gt $script:TimingTail) { [void]$fs.Seek($len - $script:TimingTail, [System.IO.SeekOrigin]::Begin); $skip = $true }
            $sr = New-Object System.IO.StreamReader($fs, $script:Utf8)
            if ($skip) { [void]$sr.ReadLine() }
            $raw = $sr.ReadToEnd()
        } finally { $fs.Dispose() }
    } catch { return '' }
    foreach ($line in ($raw -split "`n")) {
        if ($line.IndexOf('"assistant"') -lt 0 -or $line.IndexOf('"text"') -lt 0) { continue }
        $rec = $null
        try { $rec = $line | ConvertFrom-Json } catch { continue }
        if ([string](Get-Prop $rec 'type') -ne 'assistant') { continue }
        $ts = Get-IsoTs (Get-Prop $rec 'timestamp')
        if (($null -eq $ts) -or ($ts -lt $since) -or ($ts -lt $lastTs)) { continue }
        $msg = Get-Prop $rec 'message'
        if ($null -eq $msg) { continue }
        $content = Get-Prop $msg 'content'
        if ($null -eq $content) { continue }
        foreach ($b in @($content)) {
            if ($null -eq $b) { continue }
            if ([string](Get-Prop $b 'type') -ne 'text') { continue }
            $t = [string](Get-Prop $b 'text')
            if ($t.Trim()) { $last = $t; $lastTs = $ts }
        }
    }
    return $last
}
function Get-MainTaskHint([string]$root) {
    $task = Get-MainTask $root
    if (-not $task) { return '' }
    return ('Главная задача: «' + $task + '». Последняя строка ответа — одна из двух: идёт работа → «' + $script:MainTaskTail + ': ' + $task + ', сейчас <что делаю>»; сделано и нужен владелец → «' + $script:MainTaskWait + ' <какой>: <что именно сделать — посмотреть экран / да-нет / дать данные> и где (адрес)». Слово «выполняю» без действия в этом ходе запрещено. Вопрос владельцу или побочный ответ работу не останавливает: спросил (ответил) — и в том же ходе продолжил.')
}
function Get-MainTaskCheck($data, [string]$root, [double]$since) {
    # Конец хода: главная задача есть, а последняя строка ответа не про неё — вернуть и продолжить.
    # Повторный проход тоже проверяется — до двух возвратов за ход (см. Invoke-CheckDocs).
    $task = Get-MainTask $root
    if (-not $task) { return @() }
    $ans = Get-LastAnswer ([string](Get-Prop $data 'transcript_path')) $since
    if (-not $ans) { return @() }
    $tail = $ans.Trim(); if ($tail.Length -gt 400) { $tail = $tail.Substring($tail.Length - 400) }
    $low = $tail.ToLowerInvariant()
    if ($low.Contains($script:MainTaskTail.ToLowerInvariant()) -or $low.Contains($script:MainTaskWait.ToLowerInvariant())) { return @() }
    return @('Главная задача не закрыта: «' + $task + '», а последней строки про неё в ответе нет. Допиши последней строкой «' + $script:MainTaskTail + ': …, сейчас <что делаю>» — и продолжи её в этом же ходе, не дожидаясь владельца; либо, если сделано и без него не двинуться, «' + $script:MainTaskWait + ' <какой>: <что сделать и где>»; принята владельцем — в STATE.md «Главная задача: —».')
}
# ------------------------------------------- вопрос о готовности: только ответ, правок в этом ходе нет
$script:StatusRe = '(готов[аоы]?\s*\?|всё готово|все готово|что осталось|сколько осталось|как долго|долго (ещё|еще)|когда (будет|закончишь|сделаешь|всё|все)|завершен[оа]?\s*\?|закончен[оа]?\s*\?|сделан[оа]?\s*\?|ты закончил|закончил\s*\?|как идёт|как идет|что по (копии|задаче|срокам))'
$script:StatusWorkRe = '\b(сделай|доделай|делай|продолжай|запускай|исправь|почини|переделай|добавь|убери|верни)\b'
$script:StatusHint = 'Набор: владелец спрашивает о готовности. В этом ходе — только ответ, по таблице готовности (часть · сделано · проверено · сверил владелец): да/нет, что осталось списком, сколько это займёт. Таблицы нет — составить её сейчас в документе главной задачи и ответить по ней. Правки файлов, команды на сервер и коммиты в этом ходе запрещены (хук не пропустит); работа — следующим ходом, после его слова.'
$script:StatusDeny = 'Ход начался с вопроса владельца о готовности — в нём только ответ по таблице готовности, без правок и команд, которые что-то меняют. Ответь сейчас; работу — следующим ходом, когда он скажет.'
$script:ChangeCmdRe = '(^|[\s;&|("''])(scp|rsync|patch|tee|sed\s+-i|git\s+(commit|push|apply)|docker\s+(compose\s+)?(build|up|restart)|npm\s+run\s+build|cp|mv|Set-Content|Out-File|Add-Content)\b|>\s*(?!&|/dev/null)\S'
$script:QuestionRe = '(\?\s*$|^\W*(что|как|почему|зачем|где|когда|какой|какая|какие|сколько|можно ли|есть ли|это|а что|а как|а почему|правильно ли|верно ли|нужно ли|надо ли)\b)'
$script:WorkRe = '\b(сделай|сделать|добавь|добавить|исправь|исправить|убери|убрать|поправь|поправить|замени|заменить|проверь|проверить|запусти|выложи|перенеси|напиши|создай|удали|обнови|продолжай|доделай|делай|давай|разбей|подключи|настрой|почини|верни)\b'
$script:AnswerHint = 'Набор: это вопрос, а не задание. Ответить словами — из головы, STATE и одного взгляда в код (Read/Grep можно); правок, команд с записью и коммитов в этом ходе нет (хук не пропустит). Чтобы ответить, нужна работа, или неясно, ответ нужен или работа, — спросить одной строкой «сделать: <что>?» и закончить ход; его «да» откроет.'
$script:AnswerDeny = 'Ход начался с вопроса владельца — в нём только ответ словами. Нужна работа — спроси одной строкой «сделать: <что>?» и закончи ход; его «да» следующим сообщением откроет этот вызов.'
function Test-Question([string]$prompt) {
    $p = $prompt.Trim()
    if ([regex]::IsMatch($p, '^\W*(чат|chat)\s*[:：]', 'IgnoreCase')) { return $true }
    if (-not $p -or $p.Length -gt 300 -or $p.StartsWith('<')) { return $false }
    if (-not [regex]::IsMatch($p, $script:QuestionRe, 'IgnoreCase')) { return $false }
    if ([regex]::IsMatch($p, $script:WorkRe, 'IgnoreCase')) { return $false }
    return $true
}
function Test-StatusQuestion([string]$prompt) {
    $p = $prompt.Trim()
    if (-not $p -or $p.Length -gt 160) { return $false }
    if (-not [regex]::IsMatch($p, $script:StatusRe, 'IgnoreCase')) { return $false }
    if ([regex]::IsMatch($p, $script:StatusWorkRe, 'IgnoreCase')) { return $false }
    return $true
}
function Get-TurnSnap($data) {
    try { $sf = Get-StateFile $data 'turn'; if (Test-Path -LiteralPath $sf) { return ((Get-Content -LiteralPath $sf -Raw -Encoding UTF8) | ConvertFrom-Json) } } catch {}
    return $null
}
$script:MemoryPathRe = '(^|/)(docs/ai/[^/]+\.md|docs/ai/(specs|solutions)/.+\.md|\.claude/rules/project\.md)$'
function Invoke-GuardStatusWrite($data) {
    $snap = Get-TurnSnap $data
    if (-not $snap) { return }
    if (-not ((Get-Prop $snap 'ready_q') -eq $true -or (Get-Prop $snap 'answer') -eq $true)) { return }
    $path = ([string](Get-Prop (Get-Prop $data 'tool_input') 'file_path')) -replace '\\', '/'
    if ([regex]::IsMatch($path, $script:MemoryPathRe, 'IgnoreCase')) { return }
    if ((Get-Prop $snap 'ready_q') -eq $true) { Out-Deny $script:StatusDeny }
    Out-Deny $script:AnswerDeny
}
function Invoke-GuardStatusShell([string]$cmd, $data) {
    $snap = Get-TurnSnap $data
    if (-not $snap -or -not [regex]::IsMatch($cmd, $script:ChangeCmdRe, 'IgnoreCase')) { return }
    if ((Get-Prop $snap 'ready_q') -eq $true) { Out-Deny $script:StatusDeny }
    if ((Get-Prop $snap 'answer') -eq $true) { Out-Deny $script:AnswerDeny }
}
# ------------------------------------------- проверяющий интерфейса: менялись экраны — ui-checker обязан сходить
$script:UiFileRe = '[\w./\\-]+\.(tsx|jsx|vue|svelte|css|scss|less|html?)\b'
$script:UiSkipRe = '(^|/)(docs/ai/previews|node_modules|dist|build|\.next)/'
function Get-UiChanges($uses) {
    $files = New-Object System.Collections.Generic.List[string]
    $checked = $false
    foreach ($u in @($uses)) {
        if ($null -eq $u) { continue }
        $name = [string]$u.Name; $inp = $u.Input
        if ($name -eq 'Agent') {
            $blob = ''; try { $blob = ($inp | ConvertTo-Json -Depth 6 -Compress) } catch { $blob = [string]$inp }
            if ([regex]::IsMatch($blob, 'ui-checker|проверяющ', 'IgnoreCase')) { $checked = $true }
            continue
        }
        if ($name -in @('Write', 'Edit', 'MultiEdit', 'NotebookEdit')) {
            $path = [string](Get-Prop $inp 'file_path'); if (-not $path) { $path = [string](Get-Prop $inp 'notebook_path') }
            $path = $path -replace '\\', '/'
            if ([regex]::IsMatch($path, $script:UiFileRe, 'IgnoreCase') -and -not [regex]::IsMatch($path, $script:UiSkipRe, 'IgnoreCase')) {
                $files.Add([System.IO.Path]::GetFileName($path))
            } elseif ($name -eq 'Write' -and [regex]::IsMatch($path, '\.(py|sh|ps1|js|mjs)$', 'IgnoreCase')) {
                foreach ($m in [regex]::Matches([string](Get-Prop $inp 'content'), $script:UiFileRe, 'IgnoreCase')) {
                    if (-not [regex]::IsMatch($m.Value, $script:UiSkipRe, 'IgnoreCase')) { $files.Add([System.IO.Path]::GetFileName(($m.Value -replace '\\', '/'))) }
                }
            }
        } elseif ($name -in @('Bash', 'PowerShell')) {
            $cmd = [string](Get-Prop $inp 'command')
            if ([regex]::IsMatch($cmd, $script:ChangeCmdRe, 'IgnoreCase') -or [regex]::IsMatch($cmd, '\bpython\S*\s+\S*(patch|fix|apply)', 'IgnoreCase')) {
                foreach ($m in [regex]::Matches($cmd, $script:UiFileRe, 'IgnoreCase')) {
                    if (-not [regex]::IsMatch($m.Value, $script:UiSkipRe, 'IgnoreCase')) { $files.Add([System.IO.Path]::GetFileName(($m.Value -replace '\\', '/'))) }
                }
            }
        }
    }
    $seen = @{}; $out = @()
    foreach ($f in $files) { $k = $f.ToLowerInvariant(); if (-not $seen.ContainsKey($k)) { $seen[$k] = 1; $out += $f } }
    return @{ files = @($out); checked = $checked }
}
function Get-UiCheckMsgs($data, [string]$root, [double]$since) {
    if (-not [System.IO.File]::Exists((Join-Path (Join-Path (Join-Path $root '.claude') 'agents') 'ui-checker.md'))) { return @() }
    $tt = Get-TurnTools ([string](Get-Prop $data 'transcript_path')) $since
    $ch = Get-UiChanges $tt.uses
    if ($ch.files.Count -eq 0 -or $ch.checked) { return @() }
    return @('Менялись файлы интерфейса (' + (($ch.files | Select-Object -First 4) -join ', ') + '), а проверяющий ui-checker не ходил. Отправь его сейчас субагентом (Agent, ui-checker): сверить экран с эталоном в браузере, итог одной строкой; расхождение — переделать; браузера нет — сказать владельцу первой строкой.')
}
# ------------------------------------------- «как в эталоне» — только со сверкой по элементам и парой снимков
# Урок 03.10.2026 (Bass): при 65 снимках эталона экран «сверили на глаз» по 8 и сдали как совпадающий — день впустую.
$script:CloneClaimRe = '(?<!не )(соответству\w+\s+эталону|совпада\w+\s+с\s+эталоном|свер\w+\s+(на\s+глаз\s+)?с\s+эталоном|как\s+в\s+эталоне|точь-в-точь\s+как|один\s+в\s+один)'
$script:CloneScoreRe = 'сверка(?:\s+\w+)?\s*:?\s*(\d+)\s*из\s*(\d+)'
$script:ClonePairRe = 'pair[\w.-]*\.(html|png|jpe?g)'
$script:CloneDeliverRe = '(экран|карточк|страниц|шаблон|макет|тем[ауы]|структур|вкладк|дашборд)\w*[^.\n]{0,80}(готов|сделан|собран|включ[её]н|перенес[её]н|на\s+месте)|можно\s+(смотреть|проверять|открывать)|посмотрите|откройте|проверьте|принимайте|сдаю'
$script:CloneDeliverMsg = 'Идёт копия по эталону (есть docs/ai/specs/ui/ETALON.md), в ответе экран сдаётся владельцу, а пары снимков нет. Сдавать можно только так (скилл clone-screen, п. 5): открыть свой экран в браузере, снять его, собрать пару (pair.html: эталон слева, наш экран справа), в ответе — строка «Сверка: N из M» и путь к паре. Экран не открывается или показывает старое — это и сказать первой строкой, а не «готово». В этом ходе экран не сдаётся — убрать слова о готовности.'
function Get-CloneClaimMsgs($data, [string]$root, [double]$since) {
    if (-not [System.IO.File]::Exists((Join-Path (Join-Path (Join-Path (Join-Path $root '.claude') 'skills') 'clone-screen') 'SKILL.md'))) { return @() }
    $ans = Get-LastAnswer ([string](Get-Prop $data 'transcript_path')) $since
    if ([string]::IsNullOrEmpty($ans)) { return @() }
    if (-not [regex]::IsMatch($ans, $script:CloneClaimRe, 'IgnoreCase')) {
        # Сдача экрана без слов о совпадении («структура собрана, откройте») — тоже только с парой.
        $etalon = Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'specs') 'ui') 'ETALON.md'
        $proved = ([regex]::IsMatch($ans, $script:CloneScoreRe, 'IgnoreCase') -and [regex]::IsMatch($ans, $script:ClonePairRe, 'IgnoreCase'))
        if ([System.IO.File]::Exists($etalon) -and [regex]::IsMatch($ans, $script:CloneDeliverRe, 'IgnoreCase') -and -not $proved) { return @($script:CloneDeliverMsg) }
        return @()
    }
    $m = [regex]::Match($ans, $script:CloneScoreRe, 'IgnoreCase')
    if ($m.Success -and [regex]::IsMatch($ans, $script:ClonePairRe, 'IgnoreCase')) {
        if ([int]$m.Groups[1].Value -ge [int]$m.Groups[2].Value) { return @() }
        return @('В ответе сказано, что экран как в эталоне, а сверка — ' + $m.Groups[1].Value + ' из ' + $m.Groups[2].Value + '. Это не совпадение: убрать слова о совпадении и перечислить, каких элементов нет и почему, либо доделать (скилл clone-screen).')
    }
    return @('В ответе сказано, что экран как в эталоне, но нет доказательства. Нужно (скилл clone-screen): строка «Сверка: N из M» — счёт элементов из описи эталона по таблице проверяющего — и путь к паре снимков (pair.html: эталон слева, наш экран справа). Нет описи и пары — слова о совпадении убрать и сказать, что сделано на деле.')
}
# ------------------------------------------- замер вёрстки: правили интерфейс — в ответе числа замера, и они нулевые
# Урок 03.10.2026: правила вёрстки и проверяющий «глазами» не ловят наезды в 5–10 px; ловит только замер в браузере.
$script:MeasureLineRe = 'замер\s+в[её]рстки\s*:([^\n]*)'
$script:MeasureNumRe = '(\d{3,4})\s*[—–-]\s*(\d+)'
$script:MeasureMissing = 'Менялись файлы интерфейса (%s), а строки замера в ответе нет. Замер обязателен (скилл layout-check): открыть экран в браузере, выполнить .claude/skills/layout-check/layout-check.js на ширинах 320, 768, 1280 и 1920, исправить всё найденное и написать в ответе строку «Замер вёрстки: 320 — 0, 768 — 0, 1280 — 0, 1920 — 0». Браузера нет — «Замер вёрстки: не выполнен — <почему>» первой строкой ответа, и экран владельцу не сдавать.'
$script:MeasureDirty = 'Замер вёрстки показал проблемы (%s), а ход заканчивается. Наезды, вылезания и обрезанный текст исправляются до сдачи: править общий стиль, замерить снова, пока не будет 0 на всех ширинах. Наложение задумано — пометить элемент data-overlap-ok и назвать его владельцу.'
function Get-LayoutMeasureMsgs($data, [string]$root, [double]$since) {
    if (-not [System.IO.File]::Exists((Join-Path (Join-Path (Join-Path (Join-Path $root '.claude') 'skills') 'layout-check') 'layout-check.js'))) { return @() }
    $tt = Get-TurnTools ([string](Get-Prop $data 'transcript_path')) $since
    $ch = Get-UiChanges $tt.uses
    if ($ch.files.Count -eq 0) { return @() }
    $ans = [string](Get-LastAnswer ([string](Get-Prop $data 'transcript_path')) $since)
    $m = [regex]::Match($ans, $script:MeasureLineRe, 'IgnoreCase')
    if (-not $m.Success) { return @($script:MeasureMissing.Replace('%s', (($ch.files | Select-Object -First 4) -join ', '))) }
    $nums = [regex]::Matches($m.Groups[1].Value, $script:MeasureNumRe)
    $skipped = [regex]::IsMatch([string]$m.Groups[1].Value, 'не\s+выполнен', 'IgnoreCase')
    if ((@($nums).Count -lt 4) -and (-not $skipped)) { return @($script:MeasureMissing.Replace('%s', (($ch.files | Select-Object -First 4) -join ', '))) }
    $bad = @()
    foreach ($x in $nums) { if ([int]$x.Groups[2].Value -gt 0) { $bad += ($x.Groups[1].Value + ' — ' + $x.Groups[2].Value) } }
    if ($bad.Count -gt 0) { return @($script:MeasureDirty.Replace('%s', ($bad -join ', '))) }
    return @()
}
# ------------------------------------------- «Следующий шаг»: первый пункт — один
function Get-NextStepProblem([string]$root) {
    $p = Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'STATE.md'
    if (-not [System.IO.File]::Exists($p)) { return '' }
    $txt = ''
    try { $txt = [System.IO.File]::ReadAllText($p, $script:Utf8).TrimStart([char]0xFEFF) } catch { return '' }
    $firsts = 0
    foreach ($m in [regex]::Matches((Get-StateSection $txt 'Следующий шаг'), '(?m)^\s*(\d+)[а-яa-z]?[.)]\s*\S')) {
        if ([int]$m.Groups[1].Value -le 1) { $firsts++ }
    }
    if ($firsts -lt 2) { return '' }
    return ('В «Следующий шаг» ' + $firsts + ' пункт(а) претендуют на первое место (0, 0а, 0б, 1…): оставить один первый, остальные пронумеровать ниже по порядку — иначе очередь без вершины.')
}
# ------------------------------------------- уроки с повторами: раз в сеанс не выпускать без предложения проверки
function Get-StuckLessons([string]$root, [int]$minReps) {
    $p = Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'LESSONS.md'
    if (-not [System.IO.File]::Exists($p)) { return @() }
    $txt = ''
    try { $txt = [System.IO.File]::ReadAllText($p, $script:Utf8).TrimStart([char]0xFEFF) } catch { return @() }
    $stuck = @()
    foreach ($line in ($txt -split "`n")) {
        if (-not $line.StartsWith('|')) { continue }
        $cells = @(($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -lt 5 -or $cells[0].StartsWith('---') -or $cells[0].ToLowerInvariant().StartsWith('дата')) { continue }
        $status = $cells[3].ToLowerInvariant()
        $m = [regex]::Match($cells[4], '\d+')
        $reps = 0; if ($m.Success) { $reps = [int]$m.Value }
        if ($reps -lt $minReps -or $status.Contains('закрыт')) { continue }
        if ([regex]::IsMatch($line, 'хук|тест|линтер|rules/|\.md\b|правил', 'IgnoreCase')) { continue }
        $stuck += [pscustomobject]@{ Reps = $reps; Text = (Get-Cut $cells[1] 60) }
    }
    return @($stuck)
}
$script:CodeLinesLimit = 1000
function Get-BigCodeNotice($data, [string]$top, $touched) {
    # Тронутый файл кода длиннее CodeLinesLimit строк — раз за сеанс напомнить про разделение.
    $marker = Get-StateFile $data 'bigcode'
    if (Test-Path -LiteralPath $marker) { return @() }
    $big = @()
    foreach ($f in (Sort-Ordinal @($touched))) {
        $ext = [System.IO.Path]::GetExtension($f).ToLowerInvariant()
        if (-not (($script:HeaderExt -contains $ext) -or (@('.css', '.scss', '.less', '.html', '.htm') -contains $ext))) { continue }
        if ($f -match $script:Generated) { continue }
        $full = Join-Path $top $f
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $n = 0
        try { $n = [System.IO.File]::ReadAllLines($full).Count } catch { continue }
        if ($n -gt $script:CodeLinesLimit) { $big += ($f + ' (' + $n + ' строк)') }
    }
    if ($big.Count -eq 0) { return @() }
    try { Set-Content -LiteralPath $marker -Value '1' -Encoding UTF8 } catch {}
    return @('Файл кода перерос предел: ' + (($big | Select-Object -First 3) -join ', ') + '. На каждую правку читается он целиком. Предложить владельцу разделение по экранам (project-restructure, §4а: только перенос, по шагу с коммитом) — одной строкой в ответе и в STATE.md «Заметил». Один раз за сеанс.')
}
function Get-LessonsBlockMsgs($data, [string]$root) {
    if ((Get-Prop $data 'stop_hook_active') -eq $true) { return @() }
    $stuck = @(Get-StuckLessons $root 3)
    if ($stuck.Count -eq 0) { return @() }
    $marker = Get-StateFile $data 'lessons'
    if (Test-Path -LiteralPath $marker) { return @() }
    try { Set-Content -LiteralPath $marker -Value '1' -Encoding UTF8 } catch {}
    $top = ($stuck | Sort-Object -Property Reps -Descending | Select-Object -First 1)
    return @('Урок «' + $top.Text + '» повторился ' + $top.Reps + ' раз(а), а проверки для него нет. В этом ответе предложи владельцу хук или тест одной фразой (что проверять и где) — или впиши в строку урока, чем он уже закрыт. Один раз за сеанс.')
}
function Invoke-TurnStart($data) {
    $root = Get-ProjectDir $data
    $ts = 0
    try { $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() } catch {}
    $promptRaw = [string](Get-Prop $data 'prompt')
    $prompt0 = [regex]::Replace($promptRaw.Trim(), '\s+', ' ')
    $hasSecret = [regex]::IsMatch($promptRaw, $script:PastedSecretRe, 'IgnoreCase')
    # Регистр не важен: «Дословно», «Не просил» с заглавной — те же слова (в Python re.I).
    $isExact = [regex]::IsMatch($promptRaw, $script:ExactRe, 'IgnoreCase')
    $isStatus = Test-StatusQuestion $promptRaw
    $isAnswer = (-not $isStatus) -and (Test-Question $promptRaw)
    $isOk = ($promptRaw.Trim().Length -le 24) -and [regex]::IsMatch($promptRaw.Trim(), $script:OkRe, 'IgnoreCase')
    $snap = @{ ts = $ts; head = $null; status = @{}; ready_q = $isStatus; answer = $isAnswer; ok = $isOk; exact = $isExact; complaint = [regex]::IsMatch($promptRaw, $script:ComplaintRe, 'IgnoreCase'); boot = (Get-BootOnce $data); check = [regex]::IsMatch($promptRaw, $script:CheckRe, 'IgnoreCase'); prompt = (Get-Cut (Hide-Secrets $prompt0) 140) }
    $head = Invoke-Git $root @('rev-parse', 'HEAD')
    if ($null -ne $head) {
        $snap.head = $head.Trim()
        $top = Invoke-Git $root @('rev-parse', '--show-toplevel'); if ([string]::IsNullOrWhiteSpace($top)) { $top = $root } else { $top = $top.Trim() }
        $st = Get-GitStatusMap $top
        if ($st) { foreach ($k in $st.Keys) { $snap.status[$k] = $st[$k][1] } }
    }
    try { ($snap | ConvertTo-Json -Depth 4 -Compress) | Set-Content -LiteralPath (Get-StateFile $data 'turn') -Encoding UTF8 } catch {}
    $other = Set-SessionClaim $data $root
    $prompt = ([string](Get-Prop $data 'prompt')).Trim()
    if ($prompt.StartsWith('/')) { return }
    if ($other) { Write-Out $other }
    if ($hasSecret) { Write-Out $script:SecretHint }
    if (-not $prompt.StartsWith('<')) { $ih = Get-IndexHint $root $prompt; if ($ih) { Write-Out $ih } }
    if ($isStatus) { Write-Out $script:StatusHint }
    elseif ($isAnswer) { Write-Out $script:AnswerHint }
    elseif ([regex]::IsMatch($prompt, $script:VagueRe, 'IgnoreCase')) { Write-Out $script:VagueHint }
    if ($isExact) { Write-Out $script:ExactHint }
    if ([regex]::IsMatch($promptRaw, $script:CheckRe, 'IgnoreCase') -and -not (Test-KitFull)) { Write-Out $script:CheckHint }
    if ([regex]::IsMatch($promptRaw, $script:ComplaintRe, 'IgnoreCase')) { Write-Out $script:ComplaintHint }
    if ([regex]::IsMatch($promptRaw, $script:LiteralRe, 'IgnoreCase') -and -not $promptRaw.TrimStart().StartsWith('/')) { Write-Out $script:LiteralHint }
    $ctxHint = Get-ContextHint $root
    if ($ctxHint) { Write-Out $ctxHint }
    $hint = Get-ChoiceHint $prompt
    if ($hint) { foreach ($line in $hint) { Write-Out $line } }
    $mt = ''; if (Test-KitFull) { $mt = Get-MainTaskHint $root }
    if ($mt) { Write-Out $mt }
    $sh = Get-SlowCallHint $data
    if ($sh) { Write-Out $sh }
    if ($prompt.Length -lt 12) { return }
    Write-Out 'Набор: сверь запрос с «Что запускать» в CLAUDE.md; первая строка ответа — «режим — итог» (если владелец не задал форму ответа). Изменил код — сам, молча, в том же шаге: шапка файла и docs/ai.'
}
# Лимиты строк: подключённые всегда документы — жёстче, остальные — 300.
$script:DocLimits = @{ 'PROFILE.md' = 40; 'STATE.md' = 60; 'KNOWLEDGE.md' = 80; 'LESSONS.md' = 40; 'INDEX.md' = 60; 'PROJECT_MAP.md' = 40 }
$script:DocLimitDefault = 300
function Get-FamilyZero([string]$root, [string]$index, [string]$family) {
    # Нулевой файл семейства — тот, что назван в строке INDEX про папку: «(оглавление — X)».
    if (-not $index) { return @($null, 'нет строки') }
    foreach ($line in ($index -split "`n")) {
        if (-not $line.Contains('specs/' + $family + '/')) { continue }
        $m = [regex]::Match($line, 'оглавлени[ея]\s*[—-]\s*`?([^`|)\s]+)')
        if (-not $m.Success) { return @($null, 'без нулевого') }
        $name = $m.Groups[1].Value.Trim()
        foreach ($cand in @((Join-Path $root $name), (Join-Path (Join-Path (Join-Path $root 'docs') 'ai') $name))) {
            if ([System.IO.File]::Exists($cand)) { return @($cand, 'ok') }
        }
        return @($null, ('нет файла ' + $name))
    }
    return @($null, 'нет строки')
}
function Get-DocProblems([string]$root, [string]$top, $touched) {
    # Документы docs/ai, изменённые в этом ходе: не переполнены, записаны в INDEX.md,
    # а часть семейства — в его нулевом файле (нулевой — только маршрут, содержимое — в частях).
    $index = $null
    try { $ip = Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'INDEX.md'; if ([System.IO.File]::Exists($ip)) { $index = [System.IO.File]::ReadAllText($ip, $script:Utf8) } } catch {}
    $over = @(); $unreg = @(); $fam = @()
    foreach ($f in (Sort-Ordinal @($touched))) {
        $m = [regex]::Match($f, '(^|/)docs/ai/(?:(specs|solutions)/[^/]+/)?([^/]+\.md)$')
        if (-not $m.Success -or ('/' + $f).Contains('/previews/')) { continue }
        $kind = $m.Groups[2].Value; $name = $m.Groups[3].Value
        $full = Join-Path $top $f
        if (-not [System.IO.File]::Exists($full)) { continue }
        $txt = [System.IO.File]::ReadAllText($full, $script:Utf8)
        $n = ([regex]::Matches($txt, "`n")).Count
        if ($txt.Length -gt 0 -and -not $txt.EndsWith("`n")) { $n++ }
        $limit = $script:DocLimitDefault
        if (-not $kind -and $script:DocLimits.ContainsKey($name)) { $limit = $script:DocLimits[$name] }
        if ($n -gt $limit) { $over += ($name + ' (' + $n + ' строк, предел ' + $limit + ')') }
        if ($kind -eq 'specs') {
            $family = [regex]::Match($f, '(^|/)docs/ai/specs/([^/]+)/').Groups[2].Value
            $z = Get-FamilyZero $root $index $family
            $zero = $z[0]; $why = $z[1]
            if ($null -eq $zero) {
                $reason = $why
                if ($why -eq 'нет строки') { $reason = 'в INDEX.md нет строки про семейство' }
                elseif ($why -eq 'без нулевого') { $reason = 'в строке INDEX не назван нулевой файл «(оглавление — X)»' }
                $fam += ('specs/' + $family + '/ — ' + $reason)
            } else {
                $ztxt = ''
                try { $ztxt = [System.IO.File]::ReadAllText($zero, $script:Utf8) } catch {}
                if (-not $ztxt.Contains($name)) { $fam += ($name + ' не записана в нулевом файле ' + [System.IO.Path]::GetFileName($zero)) }
            }
        } elseif ((-not $kind) -and ($null -ne $index) -and (-not $script:DocLimits.ContainsKey($name)) -and (-not $index.Contains($name))) { $unreg += $name }
    }
    $msgs = @()
    if ($over.Count -gt 0) {
        $msgs += ('Документ переполнен: ' + ($over -join ', ') + '. Раздели молча по «Рост документов» (скилл project-memory): отдельная тема — в свой docs/ai/<ТЕМА>.md; разросшаяся тема — исходный файл становится нулевым (только маршрут), содержимое уходит в части docs/ai/specs/<тема>/, у каждой — строка «когда сюда идти»; переросшая часть — новая часть, не дописывать. В docs/ai/INDEX.md — строка на семейство с «(оглавление — X)».')
    }
    if ($unreg.Count -gt 0) {
        $msgs += ('Документ не записан в docs/ai/INDEX.md: ' + ($unreg -join ', ') + '. Добавь строку: файл · какие данные в нём · когда читать.')
    }
    if ($fam.Count -gt 0) {
        $msgs += ('Часть семейства без записи в нулевом файле: ' + ($fam -join '; ') + '. Нулевой файл — только маршрут: строка на каждую часть — что в ней и когда сюда идти, записывается сразу, тем же ходом.')
    }
    return $msgs
}
function Get-OvergrownNotice([string]$root) {
    # На старте: все документы docs/ai против пределов, а не только тронутые в ходе.
    $base = Join-Path (Join-Path $root 'docs') 'ai'
    if (-not (Test-Path -LiteralPath $base)) { return '' }
    $over = @()
    foreach ($fi in (Get-ChildItem -LiteralPath $base -Recurse -File -Filter *.md)) {
        $rel = ($fi.FullName.Substring($base.Length).TrimStart('\', '/')) -replace '\\', '/'
        if ($rel.StartsWith('previews/')) { continue }
        $txt = ''
        try { $txt = [System.IO.File]::ReadAllText($fi.FullName, $script:Utf8) } catch { continue }
        $n = ([regex]::Matches($txt, "`n")).Count
        if ($txt.Length -gt 0 -and -not $txt.EndsWith("`n")) { $n++ }
        $limit = $script:DocLimitDefault
        if (-not $rel.Contains('/') -and $script:DocLimits.ContainsKey($fi.Name)) { $limit = $script:DocLimits[$fi.Name] }
        if ($n -gt $limit) { $over += ($rel + ' (' + $n + '/' + $limit + ')') }
    }
    if ($over.Count -eq 0) { return '' }
    $tail = ''; if ($over.Count -gt 4) { $tail = ' и ещё ' + ($over.Count - 4) }
    return ('Документы переросли предел: ' + (($over | Select-Object -First 4) -join ', ') + $tail + ' — разделить по «Рост документов» (project-memory), когда будет удобно остановиться.')
}
function Set-StateStamp([string]$root, [string]$top) {
    # Техническая часть STATE.md (дата и коммит) — хуком, без участия Claude.
    try {
        $p = Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'STATE.md'
        if (-not [System.IO.File]::Exists($p)) { return }
        $raw = [System.IO.File]::ReadAllBytes($p)
        $bom = ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF)
        $txt = $script:Utf8.GetString($raw).TrimStart([char]0xFEFF)
        $m = [regex]::Match($txt, '(обновлено:\s*)([^)\n]*?)(,\s*head:\s*)([^)\n]*)(\))')
        if (-not $m.Success -or $m.Value.Contains('TODO')) { return }
        $head = ([string](Invoke-Git $top @('rev-parse', '--short', 'HEAD'))).Trim()
        # Владелец записал не просто sha («2c51ac9 в /srv/panel») — его head не трогаем, обновляем только дату.
        $keep = $m.Groups[4].Value
        if ($head -and [regex]::IsMatch($m.Groups[4].Value, '^\s*[0-9a-fA-F]{6,40}\s*$')) { $keep = $head }
        $new = $m.Groups[1].Value + (Get-Date).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) + $m.Groups[3].Value + $keep + $m.Groups[5].Value
        if ($new -eq $m.Value) { return }
        $txt = $txt.Substring(0, $m.Index) + $new + $txt.Substring($m.Index + $m.Length)
        $bytes = $script:Utf8.GetBytes($txt)
        if ($bom) { $bytes = [byte[]](0xEF, 0xBB, 0xBF) + $bytes }
        [System.IO.File]::WriteAllBytes($p, $bytes)
    } catch {}
}
function Out-StopBlock($data, $snap, [string[]]$lines, [bool]$again = $false) {
    # Возврат ответа на доработку. Первый проход возвращает всегда; повторный (stop_hook_active) —
    # один раз за ход, чтобы не зациклиться: итого не больше двух возвратов на ход.
    if (-not $again) { Out-Block $lines }
    $p = Get-StateFile $data 'stop'
    $st = $null
    try { if (Test-Path -LiteralPath $p) { $st = (Get-Content -LiteralPath $p -Raw -Encoding UTF8) | ConvertFrom-Json } } catch { $st = $null }
    $ts = $null; if ($snap) { $ts = Get-Prop $snap 'ts' }
    if ($st -and ([string](Get-Prop $st 'ts') -eq [string]$ts) -and ([int](Get-Prop $st 'n') -ge 1)) { return }
    try { (@{ ts = $ts; n = 1 } | ConvertTo-Json -Compress) | Set-Content -LiteralPath $p -Encoding UTF8 } catch {}
    Out-Block $lines
}
# ------------------------------------------- «сделано» = владелец может увидеть: строка «Где смотреть»
$script:WhereMsg = 'В этом ходе правился код, а в ответе нет строки «Где смотреть: …». Владелец смотрит результат на своём экране и не видит правок, которые лежат только в файлах или в тестовой копии. Последней строкой ответа написать одно из трёх: «Где смотреть: <адрес или экран> — изменение уже там» / «Где смотреть: пока нигде — правка только в файлах, чтобы увидеть: <что сделать или сказать>» / «Где смотреть: <адрес тестовой копии> — на боевом ещё нет». Слово «сделано» без этого — обман: для владельца сделано то, что он может увидеть. Не видишь результат сам — попросить доступ, не гадать.'
function Get-WhereMsgs($data, [double]$since) {
    $tt = Get-TurnTools ([string](Get-Prop $data 'transcript_path')) $since
    $code = $false
    foreach ($u in @($tt.uses)) {
        if ($null -eq $u) { continue }
        $path = [string](Get-Prop $u.Input 'file_path'); if (-not $path) { $path = [string](Get-Prop $u.Input 'notebook_path') }
        if (($u.Name -in @('Write', 'Edit', 'MultiEdit', 'NotebookEdit')) -and $path -and (-not [regex]::IsMatch($path, $script:DocPathRe, 'IgnoreCase')) -and (($path -replace '\\', '/').IndexOf('/.claude/') -lt 0)) { $code = $true; break }
    }
    if (-not $code) { return @() }
    $ans = [string](Get-LastAnswer ([string](Get-Prop $data 'transcript_path')) $since)
    if ((-not $ans) -or [regex]::IsMatch($ans, 'где\s+смотреть\s*:', 'IgnoreCase')) { return @() }
    return @($script:WhereMsg)
}
function Invoke-CheckDocs($data) {
    $root = Get-ProjectDir $data
    Write-Timing $data $root
    $snap = $null
    try { $sf = Get-StateFile $data 'turn'; if (Test-Path -LiteralPath $sf) { $snap = (Get-Content -LiteralPath $sf -Raw -Encoding UTF8) | ConvertFrom-Json } } catch { $snap = $null }
    $since = -1.0
    if ($snap) { try { $since = [double](Get-Prop $snap 'ts') - 1.0 } catch { $since = -1.0 } }
    $again = ((Get-Prop $data 'stop_hook_active') -eq $true)
    if (Test-FastTurn $snap) {
        # Быстрый режим: единственное, что не пропускается, — слова о совпадении с эталоном без доказательства.
        $fm = @(); if (-not $again) { $fm = @(@(Get-CloneClaimMsgs $data $root $since) | Where-Object { $_ -ne $script:CloneDeliverMsg }) + @(Get-WhereMsgs $data $since) }
        if ($fm.Count -gt 0) { Out-StopBlock $data $snap @('Перед завершением: ' + ($fm -join ' ')) $again }
        return
    }
    $lessonMsgs = @(); if (-not $again) { $lessonMsgs = @(Get-WhereMsgs $data $since) + @(Get-LayoutMeasureMsgs $data $root $since) + @(Get-CloneClaimMsgs $data $root $since) + @(Get-LessonsBlockMsgs $data $root) }
    $taskMsgs = @(Get-MainTaskCheck $data $root $since) + @(Get-UiCheckMsgs $data $root $since) + $lessonMsgs
    $head = Invoke-Git $root @('rev-parse', 'HEAD')
    if ($null -eq $head) {
        if ($taskMsgs.Count -gt 0) { $pre = 'Перед завершением: '; if ($again) { $pre = 'Повторно, перед завершением: ' }; Out-StopBlock $data $snap @($pre + ($taskMsgs -join ' ')) $again }
        return
    }
    $head = $head.Trim()
    $top = Invoke-Git $root @('rev-parse', '--show-toplevel'); if ([string]::IsNullOrWhiteSpace($top)) { $top = $root } else { $top = $top.Trim() }
    $now = Get-GitStatusMap $top; if ($null -eq $now) { $now = @{} }
    $touched = New-Object System.Collections.Generic.HashSet[string]
    $snapHead = $null; if ($snap) { $snapHead = [string](Get-Prop $snap 'head') }
    if ($snapHead) {
        $prev = Get-Prop $snap 'status'
        foreach ($f in $now.Keys) {
            $old = $null; if ($prev) { $old = Get-Prop $prev $f }
            if ([string]$old -ne [string]$now[$f][1]) { [void]$touched.Add($f) }
        }
        if ($snapHead -ne $head) {
            $diff = Invoke-Git $top @('diff', '--name-only', '--diff-filter=AMR', $snapHead, $head)
            if ($diff) { foreach ($x in ($diff -split "`n")) { if ($x.Trim()) { [void]$touched.Add(($x.Trim() -replace '\\', '/')) } } }
        }
    } else {
        $cutoff = (Get-Date).ToUniversalTime().AddMinutes(-30)
        foreach ($f in $now.Keys) {
            try { $fi = New-Object System.IO.FileInfo -ArgumentList (Join-Path $top $f); if ($fi.Exists -and $fi.LastWriteTimeUtc -ge $cutoff) { [void]$touched.Add($f) } } catch {}
        }
    }
    # Свой же лог хронометража не считается работой этого хода.
    foreach ($f in @($touched)) { if ($f -match '(^|/)docs/ai/timing(\.old)?\.csv$|(^|/)\.claude/session\.lock$') { [void]$touched.Remove($f) } }
    # Штамп — до любой блокировки и при повторном проходе тоже (см. kit_hooks.py).
    if ($touched.Count -gt 0) { Set-StateStamp $root $top }
    if ($again) {
        if ($taskMsgs.Count -gt 0) { Out-StopBlock $data $snap @('Повторно, перед завершением: ' + ($taskMsgs -join ' ')) $true }
        return
    }
    $code = @(); $docs = $false
    foreach ($f in (Sort-Ordinal @($touched))) {
        if ($now.ContainsKey($f) -and $now[$f][0].Contains('D')) { continue }
        if (($f -cmatch '(^|/)docs/ai/([^/]+\.md$|(specs|solutions)/)') -or ($f -cmatch '(^|/)CLAUDE(\.local)?\.md$') -or (('/' + $f).Contains('/.claude/rules/'))) { $docs = $true; continue }
        $ext = [System.IO.Path]::GetExtension($f).ToLowerInvariant()
        if (($script:HeaderExt -contains $ext) -and ($f -notmatch $script:Generated)) { $code += $f }
    }
    $alive = @($touched | Where-Object { -not ($now.ContainsKey($_) -and $now[$_][0].Contains('D')) })
    $exactMsgs = @()
    if (($null -ne $snap) -and (Get-Prop $snap 'exact') -and ($alive.Count -gt 0)) {
        $exactMsgs += 'Владелец требовал сделать дословно. Прежде чем заканчивать: сверь по пунктам его словами, что просили и что сделано; всё, добавленное сверх просьбы (оформление, значок, рамка, пунктир, колонка, подсказка, блок, поле), удали сейчас; непонятное — один короткий вопрос. Сверил, лишнего нет — заканчивай ответ, владельцу про эту проверку не писать.'
    }
    $docMsgs = @($taskMsgs) + @($exactMsgs) + @(Get-DocProblems $root $top $alive) + @(Get-BigCodeNotice $data $top $alive)
    if (@($alive | Where-Object { $_ -match '(^|/)docs/ai/STATE\.md$' }).Count -gt 0) {
        $nsp = Get-NextStepProblem $root
        if ($nsp) { $docMsgs += $nsp }
    }
    if ($code.Count -eq 0) {
        if ($docMsgs.Count -gt 0) { Out-StopBlock $data $snap @('Перед завершением: ' + ($docMsgs -join ' ')) }
        return
    }
    $noHeader = @()
    foreach ($f in $code) {
        $full = Join-Path $top $f
        if (-not (Test-Path -LiteralPath $full)) { continue }
        try { $h = Get-Content -LiteralPath $full -TotalCount 15 -Encoding UTF8 } catch { continue }
        if (-not (($h -join "`n") -match 'назначение:')) { $noHeader += $f }
    }
    $msgs = @($docMsgs)
    if (-not $docs) {
        $msgs += ('В этом ходе изменён код (' + $code.Count + ' файл.), а docs/ai не обновлены. Обнови сейчас: STATE.md (что сделано, следующий шаг) и по необходимости KNOWLEDGE / PROJECT_MAP / FOUNDATION / SPEC / DECISIONS / TOOLS / LESSONS. Если обновлять нечего — просто заверши ответ, владельцу об этом не писать.')
    }
    if ($noHeader.Count -gt 0) {
        $msgs += ("Нет строки 'Назначение:' в начале файлов: " + (($noHeader | Select-Object -First 10) -join ', ') + '. Добавь шапку (правило .claude/rules/code-headers.md).')
    }
    if ($msgs.Count -gt 0) { Out-StopBlock $data $snap @('Перед завершением: ' + ($msgs -join ' ')) }
}

# ------------------------------------------------------------- session-start
function Get-TrustNotice([string]$root) {
    # Профиль в PROFILE.md обещает полное доверие, а хуки его не видят (нет settings.local.json).
    try {
        $p = Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'PROFILE.md'
        if (-not [System.IO.File]::Exists($p)) { return '' }
        $txt = [System.IO.File]::ReadAllText($p, $script:Utf8)
        $m = [regex]::Match($txt, 'Доверие:\s*(осторожное|обычное|полное)', 'IgnoreCase')
        if (-not $m.Success -or $m.Groups[1].Value.ToLowerInvariant() -ne 'полное' -or (Test-TrustFull)) { return '' }
        return 'В PROFILE.md доверие «полное», но хуки его не видят: нет `.claude/settings.local.json` с {"env": {"CLAUDE_TRUST_LEVEL": "full"}} (личный файл, в git не попадает). Предложить владельцу создать его и перезапустить сеанс.'
    } catch { return '' }
}
function Test-SameCommit([string]$a, [string]$b) {
    $a = ([string]$a).Trim().ToLowerInvariant(); $b = ([string]$b).Trim().ToLowerInvariant()
    return ($a -and $b -and ($a.StartsWith($b) -or $b.StartsWith($a)))
}
function Test-StateHeadOk([string]$root, [string]$rec) {
    # STATE пишут до коммита, поэтому записанный head = HEAD или HEAD~1 — норма.
    if (Test-SameCommit $rec (Invoke-Git $root @('rev-parse', 'HEAD'))) { return $true }
    return [bool](Test-SameCommit $rec (Invoke-Git $root @('rev-parse', 'HEAD~1')))
}
function Clear-OldState($data) {
    try {
        $dir = Split-Path -Parent (Get-StateFile $data 'turn')
        $old = (Get-Date).ToUniversalTime().AddDays(-7)
        foreach ($f in [System.IO.Directory]::GetFiles($dir, 'starter-*.json')) {
            if ([System.IO.File]::GetLastWriteTimeUtc($f) -lt $old) { [System.IO.File]::Delete($f) }
        }
    } catch {}
}
# ------------------------------------------------------------- версия набора
# Файлы набора (без документов проекта и сливаемых файлов) и их отпечатки — в .claude/starter.json.
$script:KitSkipTop = @('.git', '.gitignore', 'docs', 'README.md', 'INSTALL.md', 'CLAUDE.md', '.mcp.json', 'VERSION', 'CHANGELOG.md')
$script:KitSkipRel = @('.claude/settings.json', '.claude/settings.unix.json', '.claude/starter.json', '.claude/rules/project.md', '.claude/settings.local.json', 'starter.lock', '.claude/starter.lock', '.claude/session.lock')
function Get-FileHash16([string]$path) {
    $raw = [System.IO.File]::ReadAllBytes($path)
    $buf = New-Object System.Collections.Generic.List[byte] ($raw.Length)
    for ($i = 0; $i -lt $raw.Length; $i++) {
        if ($raw[$i] -eq 13 -and $i + 1 -lt $raw.Length -and $raw[$i + 1] -eq 10) { continue }
        $buf.Add($raw[$i])
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $h = $sha.ComputeHash($buf.ToArray())
    return (-join ($h | ForEach-Object { $_.ToString('x2') })).Substring(0, 16)
}
function Get-KitFiles([string]$kit) {
    $kit = [System.IO.Path]::GetFullPath($kit)
    $res = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($kit)
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        $relD = if ($d -eq $kit) { '.' } else { $d.Substring($kit.Length).TrimStart('\', '/') -replace '\\', '/' }
        foreach ($f in [System.IO.Directory]::GetFiles($d)) {
            $name = [System.IO.Path]::GetFileName($f)
            $rel = if ($relD -eq '.') { $name } else { $relD + '/' + $name }
            if (($relD -eq '.' -and $script:KitSkipTop -contains $name) -or ($script:KitSkipRel -contains $rel)) { continue }
            $res.Add($rel)
        }
        foreach ($sd in [System.IO.Directory]::GetDirectories($d)) {
            $name = [System.IO.Path]::GetFileName($sd)
            if ($name -eq '__pycache__' -or ($relD -eq '.' -and $script:KitSkipTop -contains $name)) { continue }
            $stack.Push($sd)
        }
    }
    return (Sort-Ordinal $res)
}
function Read-KitVersion([string]$kit) {
    try { return ([System.IO.File]::ReadAllText((Join-Path $kit 'VERSION'), $script:Utf8)).Trim().TrimStart([char]0xFEFF) } catch { return '' }
}
function Get-VerKey([string]$v) {
    $n = @([regex]::Matches([string]$v, '\d+') | Select-Object -First 3 | ForEach-Object { [int]$_.Value })
    while ($n.Count -lt 3) { $n += 0 }
    return ('{0:D6}.{1:D6}.{2:D6}' -f $n[0], $n[1], $n[2])
}
function Get-ManifestPath([string]$root) { return (Join-Path (Join-Path $root '.claude') 'starter.json') }
function Read-Manifest([string]$root) {
    try { return ([System.IO.File]::ReadAllText((Get-ManifestPath $root), $script:Utf8) | ConvertFrom-Json) } catch { return $null }
}
function Write-KitManifest([string]$kit, [string]$source, [string]$root) {
    $files = [ordered]@{}
    foreach ($rel in (Get-KitFiles $kit)) {
        $p = Join-Path $root $rel
        if ([System.IO.File]::Exists($p)) { $files[$rel] = Get-FileHash16 $p }
    }
    $version = Read-KitVersion $kit
    if (-not $version) {
        # Папка-источник без VERSION (например, указали сам проект) — не затирать записанную версию.
        $man = Read-Manifest $root
        if ($man) { $version = [string](Get-Prop $man 'version') }
        if (-not $version) {
            Write-Out 'Не записано: в папке набора нет файла VERSION, а в проекте нет записанной версии. Укажи путь к исходнику набора: manifest <папка набора> <адрес источника>.'
            return
        }
        Write-Out ('В указанной папке нет VERSION — версия оставлена прежней: ' + $version + '.')
    }
    $data = [ordered]@{ files = $files; installed = (Get-Date).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture); source = $source; version = $version }
    [System.IO.File]::WriteAllText((Get-ManifestPath $root), ($data | ConvertTo-Json -Depth 5), $script:Utf8)
    Write-Out ('Записано: .claude/starter.json — версия ' + $data.version + ', файлов набора: ' + $files.Count + '.')
}
function Write-UpdatePlan([string]$kit, [string]$root) {
    $man = Read-Manifest $root
    $old = @{}
    if ($man -and $man.files) { foreach ($pr in $man.files.PSObject.Properties) { $old[$pr.Name] = [string]$pr.Value } }
    $newFiles = @(Get-KitFiles $kit)
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($rel in $newFiles) {
        $dst = Join-Path $root $rel
        if (-not [System.IO.File]::Exists($dst)) { $rows.Add('добавить: ' + $rel); continue }
        $cur = Get-FileHash16 $dst
        if ($cur -eq (Get-FileHash16 (Join-Path $kit $rel))) { continue }
        if ($old.ContainsKey($rel) -and $old[$rel] -ceq $cur) { $rows.Add('заменить: ' + $rel) }
        else { $rows.Add('изменён владельцем — показать разницу и спросить: ' + $rel) }
    }
    foreach ($rel in (Sort-Ordinal @($old.Keys))) {
        $dst = Join-Path $root $rel
        if (($newFiles -notcontains $rel) -and [System.IO.File]::Exists($dst)) {
            if ($old[$rel] -ceq (Get-FileHash16 $dst)) { $rows.Add('удалить (нет в новой версии): ' + $rel) }
            else { $rows.Add('нет в новой версии, изменён владельцем — спросить: ' + $rel) }
        }
    }
    $lv = if ($man -and $man.version) { [string]$man.version } else { '?' }
    $nv = Read-KitVersion $kit; if (-not $nv) { $nv = '?' }
    Write-Out ('Версия: в проекте ' + $lv + ', новая ' + $nv + '.')
    foreach ($r in $rows) { Write-Out $r }
    Write-Out ('Действий с файлами набора: ' + $rows.Count + '. CLAUDE.md, settings.json, .mcp.json — сверить вручную.')
}
function Get-RemoteVersion([string]$src) {
    if ([System.IO.Directory]::Exists($src)) { return (Read-KitVersion $src) }
    $m = [regex]::Match($src, '^https?://github\.com/([^/\s]+)/([^/\s#?]+?)(?:\.git)?/?$')
    if (-not $m.Success) { return '' }
    $url = 'https://raw.githubusercontent.com/' + $m.Groups[1].Value + '/' + $m.Groups[2].Value + '/HEAD/VERSION'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        return ([string]$r.Content).Trim()
    } catch { return '' }
}
function Get-UpdateNotice([string]$root) {
    # Раз в сутки: версия набора в источнике новее установленной → строка для Claude.
    if ($env:KIT_NO_UPDATE_CHECK) { return '' }
    $man = Read-Manifest $root
    if (-not $man) { return '' }
    $local = [string]$man.version; $src = [string]$man.source
    if (-not $local -or -not $src) { return '' }
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) 'claude-starter'
    $cache = Join-Path $dir 'starter-update-check.json'
    $remote = $null
    try {
        if ([System.IO.File]::Exists($cache)) {
            $c = [System.IO.File]::ReadAllText($cache, $script:Utf8) | ConvertFrom-Json
            $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [double]$c.ts
            if ($c.source -eq $src -and $age -lt 86400) { $remote = [string]$c.version }
        }
    } catch {}
    if ($null -eq $remote) {
        $remote = Get-RemoteVersion $src
        try {
            [void][System.IO.Directory]::CreateDirectory($dir)
            $obj = [ordered]@{ source = $src; ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); version = $remote }
            [System.IO.File]::WriteAllText($cache, ($obj | ConvertTo-Json -Compress), $script:Utf8)
        } catch {}
    }
    if ($remote -and ((Get-VerKey $remote) -gt (Get-VerKey $local))) {
        return ('Вышла новая версия набора: ' + $remote + ' (в проекте ' + $local + '). Предложить владельцу обновить (скилл kit-update).')
    }
    return ''
}
function Invoke-Scan([string[]]$paths) {
    # Проверка без записи: как guard-cyrillic, но по файлам с диска. Для /kit-audit.
    $root = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }
    $root = [System.IO.Path]::GetFullPath($root)
    if (-not $paths -or $paths.Count -eq 0) { $paths = @('.') }
    $skip = @('.git','node_modules','.venv','venv','__pycache__','dist','build','.next','vendor','target')
    $files = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.Stack[string]
    foreach ($a in $paths) {
        $full = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $a))
        if ([System.IO.Directory]::Exists($full)) { $stack.Push($full) } elseif ([System.IO.File]::Exists($full)) { $files.Add($full) }
    }
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        foreach ($f in [System.IO.Directory]::GetFiles($d)) { $files.Add($f) }
        foreach ($sd in [System.IO.Directory]::GetDirectories($d)) { if ($skip -notcontains [System.IO.Path]::GetFileName($sd)) { $stack.Push($sd) } }
    }
    $total = 0; $bad = 0
    foreach ($f in (Sort-Ordinal $files)) {
        try {
            if ((New-Object System.IO.FileInfo -ArgumentList $f).Length -gt 1000000) { continue }
            $text = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF) -replace "`r`n", "`n"
        } catch { continue }
        $total++
        $probs = Get-CyrillicReport $f $text $root
        if ($probs.Count -gt 0) {
            $bad++
            $rel = Get-RelPath ($f -replace '\\', '/') $root; if (-not $rel) { $rel = $f }
            Write-Out ($rel + ': ' + $probs.Count + ' — ' + ((@($probs) | Select-Object -First 3) -join '; '))
        }
    }
    Write-Out ('Проверено файлов: ' + $total + ', с замечаниями: ' + $bad + '.')
}
# ------------------------------------------- уроки, которые повторяются, а проверки нет
function Get-LessonsNotice([string]$root) {
    $stuck = @(Get-StuckLessons $root 2)
    if ($stuck.Count -eq 0) { return '' }
    $texts = @($stuck | ForEach-Object { $_.Text })
    return ('Уроки: ' + $stuck.Count + ' повторились 2 раза и больше, а проверки (хук, тест, правило) для них нет — «' + (($texts | Select-Object -First 2) -join '»; «') + '». Предложить владельцу закрепить проверкой (project-memory, «уроки»).')
}
function Get-InterfaceNotice([string]$root) {
    $p = Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'PROFILE.md'
    if (-not [System.IO.File]::Exists($p)) { return '' }
    $txt = ''
    try { $txt = [System.IO.File]::ReadAllText($p, $script:Utf8) } catch { return '' }
    if (-not [regex]::IsMatch($txt, 'интерфейс\s*:\s*(да|есть)', 'IgnoreCase')) { return '' }
    return 'Проект с интерфейсом: вид проверяется только через браузер (снимок экрана), не чтением вёрстки. Браузерных инструментов в сеансе нет — предложить владельцу подключить их первой строкой.'
}
function Get-BootOnce($data) {
    # Отметка «сеанс начался с clear / compact / startup» читается один раз — первым ходом после события.
    try {
        $p = Get-StateFile $data 'boot'
        if (-not (Test-Path -LiteralPath $p)) { return '' }
        $s = [string](Get-Prop ((Get-Content -LiteralPath $p -Raw -Encoding UTF8) | ConvertFrom-Json) 'src')
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        return $s
    } catch { return '' }
}
function Invoke-SessionStart($data) {
    $root = Get-ProjectDir $data
    $src = [string](Get-Prop $data 'source')
    $lines = @('[claude-starter] Старт сеанса' + $(if ($src) { ' (' + $src + ')' } else { '' }) + '.')
    $statePath = Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'STATE.md'
    Clear-OldState $data
    [void](Set-SessionClaim $data $root)
    try { $bs = $src; if (-not $bs) { $bs = 'startup' }; (@{ src = $bs } | ConvertTo-Json -Compress) | Set-Content -LiteralPath (Get-StateFile $data 'boot') -Encoding UTF8 } catch {}
    if ([System.IO.File]::Exists((Join-Path $root 'INSTALL.md')) -and [System.IO.File]::Exists((Join-Path $root 'VERSION'))) {
        $lines += ('Это исходник набора claude-starter (версия ' + (Read-KitVersion $root) + '), не проект: не устанавливать и не заполнять docs/ai. Работа здесь — /kit-harvest (уроки из проектов), выпуск версий.')
    }
    $head = Invoke-Git $root @('rev-parse', '--short', 'HEAD')
    $inside = ([string](Invoke-Git $root @('rev-parse', '--is-inside-work-tree'))).Trim() -eq 'true'
    if ($null -ne $head) {
        $head = $head.Trim()
        $branch = ([string](Invoke-Git $root @('rev-parse', '--abbrev-ref', 'HEAD'))).Trim()
        $st = [string](Invoke-Git $root @('status', '--porcelain'))
        $n = @(($st -split "`n") | Where-Object { $_.Trim() }).Count
        $lines += ('git: ветка ' + $branch + ', HEAD ' + $head + ', незакоммиченных файлов: ' + $n + '.')
    } elseif ($inside) {
        $lines += 'git: репозиторий без коммитов — сделать первый коммит (после .gitignore).'
    } else {
        $lines += 'git: не репозиторий — без истории откат невозможен; предложить git init.'
    }
    if (Test-Path -LiteralPath $statePath) {
        $txt = ''; try { $txt = [System.IO.File]::ReadAllText($statePath, [System.Text.Encoding]::UTF8) } catch {}
        $m = [regex]::Match($txt, 'head:\s*([0-9a-f]{7,40})', 'IgnoreCase')
        if ($m.Success -and $null -ne $head) {
            $rec = $m.Groups[1].Value.ToLowerInvariant()
            if (-not (Test-StateHeadOk $root $rec)) {
                $lines += ('⚠ STATE.md записан на коммите ' + $rec.Substring(0, 7) + ', а сейчас ' + $head + ' — сначала сверить с git log.')
            }
        }
        $body = @(($txt -split "`n") | ForEach-Object { $_.TrimEnd() } | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('<!--') })
        $keep = @()
        foreach ($ln in $body) { if ($ln.StartsWith('## ') -and $keep.Count -gt 0) { break }; $keep += $ln }
        $keep = @($keep | Select-Object -First 8)
        if ($keep.Count -gt 0) { $lines += ('STATE.md: ' + $keep[0]); foreach ($x in ($keep | Select-Object -Skip 1)) { $lines += ('  ' + $x) } }
        if ($txt.Length -gt 0 -and $txt.Substring(0, [Math]::Min(400, $txt.Length)).Contains('TODO')) { $lines += 'STATE.md ещё не заполнен — набор не инициализирован: предложить владельцу /kit-setup.' }
    } else {
        $lines += 'docs/ai/STATE.md нет — набор не инициализирован: предложить владельцу /kit-setup.'
    }
    $note = Get-TrustNotice $root
    if ($note) { $lines += $note }
    $note = Get-UpdateNotice $root
    if ($note) { $lines += $note }
    $note = Get-TimingNotice $root
    if ($note) { $lines += $note }
    $note = Get-LessonsNotice $root
    if ($note) { $lines += $note }
    $note = Get-OvergrownNotice $root
    if ($note) { $lines += $note }
    $note = Get-WaitingNotice $root
    if ($note) { $lines += $note }
    $task = Get-MainTask $root
    if ($task) { $lines += ('Главная задача (не закрыта): «' + $task + '» — вести её параллельно всему; последняя строка каждого ответа: «' + $script:MainTaskTail + ': …, сейчас …» или «' + $script:MainTaskWait + ' …: что нужно и где».') }
    $note = Get-NextStepProblem $root
    if ($note) { $lines += $note }
    $note = Get-InterfaceNotice $root
    if ($note) { $lines += $note }
    $lines += 'Дальше: сверить запрос с «Что запускать» (CLAUDE.md); подробности состояния — в docs/ai/STATE.md.'
    Write-Out ($lines -join "`n")
}
