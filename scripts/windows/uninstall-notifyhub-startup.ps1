param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "NotifyHubVR"),
    [string]$TaskName = "Notify Hub VR",
    [switch]$RemoveFiles
)

$ErrorActionPreference = "Stop"

$StartupDir = [Environment]::GetFolderPath("Startup")
$StartupCmdPath = Join-Path $StartupDir "Notify Hub VR.cmd"

$Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -ne $Task) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed Scheduled Task: $TaskName"
} else {
    Write-Host "Scheduled Task not found: $TaskName"
}

if (Test-Path $StartupCmdPath) {
    Remove-Item -Force $StartupCmdPath
    Write-Host "Removed Startup folder entry: $StartupCmdPath"
}

if ($RemoveFiles) {
    Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
    Write-Host "Removed files: $InstallDir"
} else {
    Write-Host "Kept files: $InstallDir"
}
