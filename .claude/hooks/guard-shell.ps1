# Назначение: хук guard-shell (Windows) — хрупкие ssh-команды (блок), установки/опасное/секреты (вопрос)
# Логика в kit_common.ps1; пара для Linux/macOS — run.sh guard-shell.
. "$PSScriptRoot\kit_common.ps1"
$data = Read-HookInput
if ($null -eq $data) { exit 0 }
Invoke-GuardShell $data
exit 0
