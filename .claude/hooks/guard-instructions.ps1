# Назначение: хук guard-instructions (Windows) — правка инструкций Claude — вопрос владельцу (кроме полного доверия)
# Логика в kit_common.ps1; пара для Linux/macOS — run.sh guard-instructions.
. "$PSScriptRoot\kit_common.ps1"
$data = Read-HookInput
if ($null -eq $data) { exit 0 }
Invoke-GuardInstructions $data
exit 0
