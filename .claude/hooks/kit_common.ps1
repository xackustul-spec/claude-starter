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
        return ($raw | ConvertFrom-Json)
    } catch { return $null }
}
function Get-Prop($obj, $name) {
    if ($null -eq $obj) { return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($null -eq $p) { return $null }
    return $p.Value
}
function Out-Ask([string]$reason) {
    $o = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'ask'; permissionDecisionReason = $reason } }
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

function Invoke-GuardShell($data) {
    $cmd = [string](Get-Prop (Get-Prop $data 'tool_input') 'command')
    if ([string]::IsNullOrWhiteSpace($cmd)) { return }
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
function Invoke-PreWrite($data) {
    # Один процесс на Write/Edit: кириллица (блок) → инструкции (вопрос) → правила в контекст.
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
function Invoke-CheckPython($data) {
    $path = [string](Get-Prop (Get-Prop $data 'tool_input') 'file_path')
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
$script:TimingHead = 'начало;всего_с;инструменты_с;модель_с;вызовов;запросов;вход_т;кэш_чт_т;кэш_зап_т;выход_т;думал_т;модель;усилие;скорость;инструменты;куда смотрел;вопрос'
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
function Get-TimingRow($data, $snap) {
    $start = 0.0
    try { $start = [double](Get-Prop $snap 'ts') } catch { $start = 0.0 }
    $total = (Get-NowSec) - $start
    if ($total -lt 0) { $total = 0.0 }
    $calls = 0; $toolS = 0.0; $names = @{}; $targets = @()
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
        $tgt = Get-ToolTarget $u.Input
        if ($tgt -and ($targets -notcontains $tgt)) { $targets += $tgt }
    }
    if ($toolS -gt $total) { $toolS = $total }
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
        (Get-CsvCell $top),
        (Get-Cut (Get-CsvCell (@($targets | Select-Object -First 12) -join ' ')) 180),
        (Get-Cut (Get-CsvCell (Get-Prop $snap 'prompt')) 140))
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
    $row = ''
    try { $row = Get-TimingRow $data $snap } catch { return }
    if (-not $row) { return }
    $path = Get-TimingPath $root
    try {
        if ([System.IO.File]::Exists($path)) {
            $first = ''
            $sr = New-Object System.IO.StreamReader($path, $script:Utf8)
            try { $first = ([string]$sr.ReadLine()).TrimEnd("`r").TrimStart([char]0xFEFF) } finally { $sr.Dispose() }
            if ($first -ne $script:TimingHead) {
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
            $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            try { $fs.SetLength([long]$cut) } finally { $fs.Dispose() }
        }
        $bytes = $script:Utf8.GetBytes($row + "`n")
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
    } catch {}
}
function Get-TimingNotice([string]$root) {
    # Одна строка при старте сеанса: куда уходит время и стоит ли разбираться.
    $tot = @(); $too = @(); $tok = @()
    foreach ($r in (Get-TimingTail (Get-TimingPath $root) 20)) {
        $p = @($r -split ';')
        if ($p.Count -lt 11) { continue }
        try {
            $tot += [double]::Parse($p[1], $script:Inv)
            $too += [double]::Parse($p[2], $script:Inv)
            $tok += ([double][int]$p[6] + [int]$p[7] + [int]$p[8] + [int]$p[9])
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
    return ('Хронометраж: последние ' + $tot.Count + ' ответов — в среднем ' + $avg.ToString('0', $script:Inv) + ' с, из них в инструментах ' + $avgT.ToString('0', $script:Inv) + ' с (' + $share + '%), токенов на ход около ' + $avgK.ToString('0', $script:Inv) + ' тыс.' + $tail)
}
function Invoke-TurnStart($data) {
    $root = Get-ProjectDir $data
    $ts = 0
    try { $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() } catch {}
    $prompt0 = [regex]::Replace(([string](Get-Prop $data 'prompt')).Trim(), '\s+', ' ')
    $snap = @{ ts = $ts; head = $null; status = @{}; prompt = (Get-Cut $prompt0 140) }
    $head = Invoke-Git $root @('rev-parse', 'HEAD')
    if ($null -ne $head) {
        $snap.head = $head.Trim()
        $top = Invoke-Git $root @('rev-parse', '--show-toplevel'); if ([string]::IsNullOrWhiteSpace($top)) { $top = $root } else { $top = $top.Trim() }
        $st = Get-GitStatusMap $top
        if ($st) { foreach ($k in $st.Keys) { $snap.status[$k] = $st[$k][1] } }
    }
    try { ($snap | ConvertTo-Json -Depth 4 -Compress) | Set-Content -LiteralPath (Get-StateFile $data 'turn') -Encoding UTF8 } catch {}
    $prompt = ([string](Get-Prop $data 'prompt')).Trim()
    if ($prompt.StartsWith('/')) { return }
    $hint = Get-ChoiceHint $prompt
    if ($hint) { foreach ($line in $hint) { Write-Out $line } }
    if ($prompt.Length -lt 12) { return }
    Write-Out 'Набор: сверь запрос с «Что запускать» в CLAUDE.md; первая строка ответа — «режим — итог». Изменил код — сам, молча, в том же шаге: шапка файла и docs/ai.'
}
# Лимиты строк: подключённые всегда документы — жёстче, остальные — 300.
$script:DocLimits = @{ 'PROFILE.md' = 40; 'STATE.md' = 60; 'KNOWLEDGE.md' = 80; 'LESSONS.md' = 40; 'INDEX.md' = 60 }
$script:DocLimitDefault = 300
function Get-DocProblems([string]$root, [string]$top, $touched) {
    # Документы docs/ai, изменённые в этом ходе: не переполнены и записаны в INDEX.md.
    $index = $null
    try { $ip = Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'INDEX.md'; if ([System.IO.File]::Exists($ip)) { $index = [System.IO.File]::ReadAllText($ip, $script:Utf8) } } catch {}
    $over = @(); $unreg = @()
    foreach ($f in (Sort-Ordinal @($touched))) {
        $m = [regex]::Match($f, '(^|/)docs/ai/([^/]+\.md)$')
        if (-not $m.Success) { continue }
        $name = $m.Groups[2].Value
        $full = Join-Path $top $f
        if (-not [System.IO.File]::Exists($full)) { continue }
        $txt = [System.IO.File]::ReadAllText($full, $script:Utf8)
        $n = ([regex]::Matches($txt, "`n")).Count
        if ($txt.Length -gt 0 -and -not $txt.EndsWith("`n")) { $n++ }
        $limit = if ($script:DocLimits.ContainsKey($name)) { $script:DocLimits[$name] } else { $script:DocLimitDefault }
        if ($n -gt $limit) { $over += ($name + ' (' + $n + ' строк, предел ' + $limit + ')') }
        if ($null -ne $index -and -not $script:DocLimits.ContainsKey($name) -and -not $index.Contains($name)) { $unreg += $name }
    }
    $msgs = @()
    if ($over.Count -gt 0) {
        $msgs += ('Документ переполнен: ' + ($over -join ', ') + '. Раздели молча: отдельная тема — в свой docs/ai/<ТЕМА>.md; продолжение той же темы — в <ИМЯ>_2.md, <ИМЯ>_3.md; из STATE/KNOWLEDGE/LESSONS — старое и крупные темы вынести. В docs/ai/INDEX.md у каждой части: какие данные в ней.')
    }
    if ($unreg.Count -gt 0) {
        $msgs += ('Документ не записан в docs/ai/INDEX.md: ' + ($unreg -join ', ') + '. Добавь строку: файл · какие данные в нём · когда читать.')
    }
    return $msgs
}
function Set-StateStamp([string]$root, [string]$top) {
    # Техническая часть STATE.md (дата и коммит) — хуком, без участия Claude.
    try {
        $p = Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'STATE.md'
        if (-not [System.IO.File]::Exists($p)) { return }
        $raw = [System.IO.File]::ReadAllBytes($p)
        $bom = ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF)
        $txt = $script:Utf8.GetString($raw).TrimStart([char]0xFEFF)
        $m = [regex]::Match($txt, '(обновлено:\s*)([^,)\n]*)(,\s*head:\s*)([^)\n]*)(\))')
        if (-not $m.Success -or $m.Value.Contains('TODO')) { return }
        $head = ([string](Invoke-Git $top @('rev-parse', '--short', 'HEAD'))).Trim()
        if (-not $head) { $head = $m.Groups[4].Value }
        $new = $m.Groups[1].Value + (Get-Date).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) + $m.Groups[3].Value + $head + $m.Groups[5].Value
        if ($new -eq $m.Value) { return }
        $txt = $txt.Substring(0, $m.Index) + $new + $txt.Substring($m.Index + $m.Length)
        $bytes = $script:Utf8.GetBytes($txt)
        if ($bom) { $bytes = [byte[]](0xEF, 0xBB, 0xBF) + $bytes }
        [System.IO.File]::WriteAllBytes($p, $bytes)
    } catch {}
}
function Invoke-CheckDocs($data) {
    $root = Get-ProjectDir $data
    Write-Timing $data $root
    if ((Get-Prop $data 'stop_hook_active') -eq $true) { return }
    $head = Invoke-Git $root @('rev-parse', 'HEAD')
    if ($null -eq $head) { return }
    $head = $head.Trim()
    $top = Invoke-Git $root @('rev-parse', '--show-toplevel'); if ([string]::IsNullOrWhiteSpace($top)) { $top = $root } else { $top = $top.Trim() }
    $snap = $null
    try { $sf = Get-StateFile $data 'turn'; if (Test-Path -LiteralPath $sf) { $snap = (Get-Content -LiteralPath $sf -Raw -Encoding UTF8) | ConvertFrom-Json } } catch { $snap = $null }
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
    $code = @(); $docs = $false
    foreach ($f in (Sort-Ordinal @($touched))) {
        if ($now.ContainsKey($f) -and $now[$f][0].Contains('D')) { continue }
        if (($f -cmatch '(^|/)docs/ai/([^/]+\.md$|(specs|solutions)/)') -or ($f -cmatch '(^|/)CLAUDE(\.local)?\.md$') -or (('/' + $f).Contains('/.claude/rules/'))) { $docs = $true; continue }
        $ext = [System.IO.Path]::GetExtension($f).ToLowerInvariant()
        if (($script:HeaderExt -contains $ext) -and ($f -notmatch $script:Generated)) { $code += $f }
    }
    $alive = @($touched | Where-Object { -not ($now.ContainsKey($_) -and $now[$_][0].Contains('D')) })
    $docMsgs = @(Get-DocProblems $root $top $alive)
    if ($code.Count -eq 0) {
        if ($docMsgs.Count -gt 0) { Out-Block @('Перед завершением: ' + ($docMsgs -join ' ')) }
        if ($touched.Count -gt 0) { Set-StateStamp $root $top }
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
    if ($msgs.Count -gt 0) { Out-Block @('Перед завершением: ' + ($msgs -join ' ')) }
    Set-StateStamp $root $top
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
$script:KitSkipTop = @('.git', '.gitignore', 'docs', 'inbox', 'README.md', 'INSTALL.md', 'CLAUDE.md', '.mcp.json', 'VERSION', 'CHANGELOG.md')
$script:KitSkipRel = @('.claude/settings.json', '.claude/settings.unix.json', '.claude/starter.json')
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
    $data = [ordered]@{ files = $files; installed = (Get-Date).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture); source = $source; version = (Read-KitVersion $kit) }
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
function Invoke-SessionStart($data) {
    $root = Get-ProjectDir $data
    $src = [string](Get-Prop $data 'source')
    $lines = @('[claude-starter] Старт сеанса' + $(if ($src) { ' (' + $src + ')' } else { '' }) + '.')
    $statePath = Join-Path (Join-Path (Join-Path $root 'docs') 'ai') 'STATE.md'
    Clear-OldState $data
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
    $lines += 'Дальше: сверить запрос с «Что запускать» (CLAUDE.md); подробности состояния — в docs/ai/STATE.md.'
    Write-Out ($lines -join "`n")
}
