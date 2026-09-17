# Назначение: прогон случаев из cases.json через kit_common.ps1 в одном процессе (для run_tests.py).
# Out-Block / Out-Ask подменяются на исключения, чтобы не завершать процесс.
param([string]$CasesFile, [string]$OutFile, [string]$Root)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'kit_common.ps1')
function Out-Block([string[]]$lines) { throw ("BLOCK`n" + ($lines -join "`n")) }
function Out-Ask([string]$reason) { throw ("ASK`n" + $reason) }
$cases = [System.IO.File]::ReadAllText($CasesFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$results = New-Object System.Collections.Generic.List[object]
foreach ($c in $cases) {
    $data = (($c.data | ConvertTo-Json -Depth 10 -Compress).Replace('{ROOT}', $Root.Replace('\', '/'))) | ConvertFrom-Json
    $env:CLAUDE_PROJECT_DIR = $Root
    $env:CLAUDE_TRUST_LEVEL = if ($c.env -and $c.env.CLAUDE_TRUST_LEVEL) { $c.env.CLAUDE_TRUST_LEVEL } else { 'normal' }
    $verdict = 'allow'; $msg = ''
    try {
        switch ($c.hook) {
            'guard-cyrillic' { Invoke-GuardCyrillic $data }
            'guard-shell' { Invoke-GuardShell $data }
            'guard-instructions' { Invoke-GuardInstructions $data }
        }
    } catch {
        $m = [string]$_.Exception.Message
        if ($m.StartsWith('BLOCK')) { $verdict = 'block'; $msg = $m.Substring(6) }
        elseif ($m.StartsWith('ASK')) { $verdict = 'ask'; $msg = $m.Substring(4) }
        else { $verdict = 'error'; $msg = $m }
    }
    $results.Add([pscustomobject]@{ id = $c.id; verdict = $verdict; msg = $msg })
}
[System.IO.File]::WriteAllText($OutFile, (ConvertTo-Json -InputObject $results.ToArray() -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
