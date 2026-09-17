# Назначение: хук pre-write (Windows) — перед Write/Edit в одном процессе: guard-cyrillic, guard-instructions, rules-on-write
# Логика в kit_common.ps1; пара для Linux/macOS — run.sh pre-write.
. "$PSScriptRoot\kit_common.ps1"
$data = Read-HookInput
if ($null -eq $data) { exit 0 }
Invoke-PreWrite $data
exit 0
