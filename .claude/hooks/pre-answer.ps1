# Назначение: хук pre-answer (Windows) — в ход-вопрос: без правок, команд с записью и субагентов, не больше 5 обращений
# Ничего не спрашивает, только отказывает с причиной. Логика в kit_common.ps1; пара для Linux/macOS — run.sh pre-answer.
. "$PSScriptRoot\kit_common.ps1"
$data = Read-HookInput
if ($null -eq $data) { exit 0 }
Invoke-PreAnswer $data
exit 0
