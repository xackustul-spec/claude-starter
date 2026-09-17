# Назначение: хук check-docs (Windows) — в конце ответа: код изменён в этом ходе — документы и шапки обновлены?
# Логика в kit_common.ps1; пара для Linux/macOS — run.sh check-docs.
. "$PSScriptRoot\kit_common.ps1"
$data = Read-HookInput
if ($null -eq $data) { exit 0 }
Invoke-CheckDocs $data
exit 0
