# Назначение: хук read-budget (Windows) — после 12 чтений в одном ходе напомнить: разведку — субагенту
# Логика в kit_common.ps1; пара для Linux/macOS — run.sh read-budget.
. "$PSScriptRoot\kit_common.ps1"
$data = Read-HookInput
if ($null -eq $data) { exit 0 }
Invoke-ReadBudget $data
exit 0
