# Назначение: хук guard-cyrillic (Windows) — кириллица в именах файлов, папок и идентификаторах кода (блок)
# Логика в kit_common.ps1; пара для Linux/macOS — run.sh guard-cyrillic.
. "$PSScriptRoot\kit_common.ps1"
$data = Read-HookInput
if ($null -eq $data) { exit 0 }
Invoke-GuardCyrillic $data
exit 0
