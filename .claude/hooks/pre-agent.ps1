# Назначение: хук pre-agent (Windows) — перед Agent: вписать субагенту предел времени и вызовов
# Логика в kit_common.ps1; пара для Linux/macOS — run.sh pre-agent.
. "$PSScriptRoot\kit_common.ps1"
$data = Read-HookInput
if ($null -eq $data) { exit 0 }
Invoke-PreAgent $data
exit 0
