# Назначение: хук session-start (Windows) — в начале сеанса — состояние проекта из STATE.md и git
# Логика в kit_common.ps1; пара для Linux/macOS — run.sh session-start.
. "$PSScriptRoot\kit_common.ps1"
$data = Read-HookInput
if ($null -eq $data) { exit 0 }
Invoke-SessionStart $data
exit 0
