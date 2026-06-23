param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "NotifyHubVR"),
    [string]$TaskName = "Notify Hub VR",
    [switch]$RemoveFiles
)

$ErrorActionPreference = "Stop"

$StartupDir = [Environment]::GetFolderPath("Startup")
$StartupCmdPath = Join-Path $StartupDir "Notify Hub VR.cmd"

$RunningProcesses = Get-Process -Name NotifyHubVr -ErrorAction SilentlyContinue
if ($null -ne $RunningProcesses) {
    Write-Host "Stopping running NotifyHubVr process."
    $RunningProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

try {
    $Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -ne $Task) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed Scheduled Task: $TaskName"
    } else {
        Write-Host "Scheduled Task not found: $TaskName"
    }
} catch {
    Write-Warning "Could not query or remove Scheduled Task. Continuing with Startup folder cleanup."
    Write-Warning $_.Exception.Message
}

if (Test-Path $StartupCmdPath) {
    Remove-Item -Force $StartupCmdPath
    Write-Host "Removed Startup folder entry: $StartupCmdPath"
} else {
    Write-Host "Startup folder entry not found: $StartupCmdPath"
}

if ($RemoveFiles) {
    Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
    Write-Host "Removed files: $InstallDir"
} else {
    Write-Host "Kept files: $InstallDir"
}
