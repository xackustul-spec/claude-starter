# Назначение: хук check-python (Windows) — синтаксис .py после записи (блок при ошибке)
# Логика в kit_common.ps1; пара для Linux/macOS — run.sh check-python.
. "$PSScriptRoot\kit_common.ps1"
$data = Read-HookInput
if ($null -eq $data) { exit 0 }
Invoke-CheckPython $data
exit 0
