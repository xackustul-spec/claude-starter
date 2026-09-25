# Назначение: хук pre-read (Windows) — перед Read/Glob/Grep/NotebookEdit: файл вне папки проекта → вопрос владельцу
# Логика в kit_common.ps1; пара для Linux/macOS — run.sh pre-read.
. "$PSScriptRoot\kit_common.ps1"
$data = Read-HookInput
if ($null -eq $data) { exit 0 }
Invoke-PreRead $data
exit 0
