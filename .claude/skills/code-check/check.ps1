# Назначение: проверка изменённых файлов кода по своду без Python (Windows): размеры, ошибки, журнал, секреты; замечания — только по изменённым строкам.
# Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File check.ps1 [файлы]; без аргументов — изменённые по git. Код возврата: 0 — чисто, 1 — есть замечания.
param([string[]]$Files)
$MaxFile = 400
$MaxFunc = 40
$Exts = @('.py', '.js', '.jsx', '.mjs', '.cjs', '.ts', '.tsx', '.vue', '.svelte')
$SkipRe = '(^|/)(node_modules|dist|build|vendor|migrations|\.venv|venv|tests?|__tests__)/|\.min\.|\.test\.|\.spec\.|conftest'
$SecretRe = '(?i)\b(password|passwd|secret|token|api[_-]?key|apikey)\b\s*[:=]\s*["''][^"''\s]{6,}["'']'
$TripleD = '"' * 3
$TripleS = "'" * 3

function Get-ChangedSet([string]$path, [int]$total) {
    $set = New-Object 'System.Collections.Generic.HashSet[int]'
    $diff = ''
    try { $diff = (@(& git diff -U0 HEAD -- $path 2>$null)) -join "`n" } catch { $diff = '' }
    if (-not $diff.Trim()) {
        for ($i = 1; $i -le $total; $i++) { [void]$set.Add($i) }
        return ,$set
    }
    foreach ($m in [regex]::Matches($diff, '(?m)^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@')) {
        $start = [int]$m.Groups[1].Value
        $cnt = 1
        if ($m.Groups[2].Success) { $cnt = [int]$m.Groups[2].Value }
        if ($cnt -lt 1) { $cnt = 1 }
        for ($i = $start; $i -lt ($start + $cnt); $i++) { [void]$set.Add($i) }
    }
    return ,$set
}

function Test-Overlap($set, [int]$from, [int]$to) {
    for ($i = $from; $i -le $to; $i++) { if ($set.Contains($i)) { return $true } }
    return $false
}

function Get-Issues([string]$path) {
    $issues = New-Object System.Collections.ArrayList
    $lines = @([System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8))
    $n = $lines.Count
    $ch = Get-ChangedSet $path $n
    $isPy = $path.EndsWith('.py')
    $isTs = ($path.EndsWith('.ts') -or $path.EndsWith('.tsx'))
    if ($n -gt $MaxFile) { [void]$issues.Add(@(1, ('файл ' + $n + ' строк (предел ' + $MaxFile + ') — новый код в новый модуль'))) }
    for ($i = 1; $i -le $n; $i++) {
        if (-not $ch.Contains($i)) { continue }
        $ln = $lines[$i - 1]
        if ([regex]::IsMatch($ln, $SecretRe)) { [void]$issues.Add(@($i, 'похоже на секрет в тексте — вынести в окружение')) }
        if ($isPy) {
            if ([regex]::IsMatch($ln, '^\s*print\(')) { [void]$issues.Add(@($i, 'print() — использовать logging')) }
            if ([regex]::IsMatch($ln, '^\s*except\s*(Exception|BaseException)?\s*(as\s+\w+)?\s*:')) {
                $tail = ($lines[($i - 1)..([Math]::Min($i + 2, $n - 1))]) -join ' '
                if (-not [regex]::IsMatch($tail, '\braise\b')) { [void]$issues.Add(@($i, 'except без конкретного исключения и без raise')) }
            }
        } else {
            $code = [regex]::Replace($ln, '//.*$', '')
            if ([regex]::IsMatch($code, '\bconsole\.(log|debug)\(')) { [void]$issues.Add(@($i, 'console.log — использовать pino/winston')) }
            if ([regex]::IsMatch($code, '\bvar\s+\w')) { [void]$issues.Add(@($i, 'var — использовать const/let')) }
            if ([regex]::IsMatch($code, '[^=!<>]==[^=]|!=[^=]')) { [void]$issues.Add(@($i, '== / != — использовать === / !==')) }
            if ($isTs -and [regex]::IsMatch($code, ':\s*any\b|<any>|\bas any\b')) { [void]$issues.Add(@($i, 'any — использовать unknown или конкретный тип')) }
            if ([regex]::IsMatch($code, 'catch\s*(\(\w*\))?\s*\{\s*\}')) { [void]$issues.Add(@($i, 'пустой catch — ошибка проглочена')) }
        }
    }
    if ($isPy) {
        for ($i = 1; $i -le $n; $i++) {
            $m = [regex]::Match($lines[$i - 1], '^(\s*)(async\s+)?def\s+(\w+)\(')
            if (-not $m.Success) { continue }
            $indent = $m.Groups[1].Value.Length
            $name = $m.Groups[3].Value
            $end = $i
            for ($j = $i + 1; $j -le $n; $j++) {
                $t = $lines[$j - 1]
                if (-not $t.Trim()) { continue }
                $ind = $t.Length - $t.TrimStart().Length
                if (($ind -le $indent) -and (-not $t.TrimStart().StartsWith(')'))) { break }
                $end = $j
            }
            if (-not (Test-Overlap $ch $i $end)) { continue }
            if (($end - $i + 1) -gt $MaxFunc) { [void]$issues.Add(@($i, ('функция ' + $name + ' — ' + ($end - $i + 1) + ' строк (предел ' + $MaxFunc + ')'))) }
            if (-not $name.StartsWith('_')) {
                $h = $i
                while (($h -lt $n) -and (-not $lines[$h - 1].TrimEnd().EndsWith(':'))) { $h++ }
                $header = ($lines[($i - 1)..($h - 1)]) -join ' '
                if ($header -notmatch '->') { [void]$issues.Add(@($i, ('функция ' + $name + ' без аннотации результата'))) }
                $nxt = ''
                for ($k = $h + 1; $k -le $n; $k++) { if ($lines[$k - 1].Trim()) { $nxt = $lines[$k - 1].Trim(); break } }
                if (-not ($nxt.StartsWith($TripleD) -or $nxt.StartsWith($TripleS))) { [void]$issues.Add(@($i, ('публичная функция ' + $name + ' без docstring'))) }
            }
        }
    } else {
        $depth = 0
        $start = 0
        $fname = ''
        for ($i = 1; $i -le $n; $i++) {
            $ln = $lines[$i - 1]
            $m = [regex]::Match($ln, '(?:function\s+(\w+)|(\w+)\s*[:=]\s*(?:async\s*)?(?:function\b|\([^)]*\)\s*=>))')
            if ($m.Success -and ($depth -eq 0) -and $ln.Contains('{')) {
                $start = $i
                $fname = $m.Groups[1].Value
                if (-not $fname) { $fname = $m.Groups[2].Value }
            }
            $depth += ($ln.Length - $ln.Replace('{', '').Length) - ($ln.Length - $ln.Replace('}', '').Length)
            if (($start -gt 0) -and ($depth -le 0)) {
                if ((($i - $start + 1) -gt $MaxFunc) -and (Test-Overlap $ch $start $i)) { [void]$issues.Add(@($start, ('функция ' + $fname + ' — ' + ($i - $start + 1) + ' строк (предел ' + $MaxFunc + ')'))) }
                $start = 0
                $depth = 0
            }
        }
    }
    return ,$issues
}

if ((-not $Files) -or ($Files.Count -eq 0)) {
    $Files = @()
    try {
        foreach ($l in @(& git status --porcelain 2>$null)) {
            if (($l.Length -gt 3) -and (-not $l.StartsWith(' D'))) { $Files += $l.Substring(3).Trim().Trim('"') }
        }
    } catch { $Files = @() }
}
$todo = @()
foreach ($f in $Files) {
    $ext = [System.IO.Path]::GetExtension($f)
    if (($Exts -contains $ext) -and (-not [regex]::IsMatch(($f -replace '\\', '/'), $SkipRe)) -and (Test-Path -LiteralPath $f -PathType Leaf)) { $todo += $f }
}
if ($todo.Count -eq 0) { Write-Output 'Код-проверка: файлов кода для проверки нет.'; exit 0 }
$total = 0
foreach ($f in $todo) {
    $found = Get-Issues $f
    foreach ($it in ($found | Sort-Object { $_[0] })) {
        Write-Output ($f + ':' + $it[0] + ' — ' + $it[1])
        $total++
    }
}
Write-Output ('Код-проверка: ' + $total + ' замечаний в ' + $todo.Count + ' файлах.')
if ($total -gt 0) { exit 1 } else { exit 0 }
