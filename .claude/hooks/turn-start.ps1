# Назначение: хук turn-start (Windows) — снимок состояния репозитория в начале хода + напоминание о маршруте
# Логика в kit_common.ps1; пара для Linux/macOS — run.sh turn-start.
. "$PSScriptRoot\kit_common.ps1"
$data = Read-HookInput
if ($null -eq $data) { exit 0 }
Invoke-TurnStart $data
exit 0
