# Назначение: хук rules-on-write (Windows) — подгружает правила .claude/rules с paths при записи подходящего файла (раз за сеанс)
# Логика в kit_common.ps1; пара для Linux/macOS — run.sh rules-on-write.
. "$PSScriptRoot\kit_common.ps1"
$data = Read-HookInput
if ($null -eq $data) { exit 0 }
Invoke-RulesOnWrite $data
exit 0
