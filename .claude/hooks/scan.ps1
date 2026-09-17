# Назначение: проверка кириллицы в файлах без записи (для /kit-audit): scan.ps1 <папки или файлы>
. "$PSScriptRoot\kit_common.ps1"
Invoke-Scan @($args | ForEach-Object { [string]$_ })
exit 0
