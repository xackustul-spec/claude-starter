# Назначение: версия набора (Windows): kit-version.ps1 manifest <папка набора> <источник> | update-plan <папка новой версии>
. "$PSScriptRoot\kit_common.ps1"
$root = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }
$cmd = [string]$args[0]
if ($cmd -eq 'manifest' -and $args.Count -ge 2) { Write-KitManifest ([System.IO.Path]::GetFullPath([string]$args[1])) ([string]$args[2]) $root }
elseif ($cmd -eq 'update-plan' -and $args.Count -ge 2) { Write-UpdatePlan ([System.IO.Path]::GetFullPath([string]$args[1])) $root }
exit 0
