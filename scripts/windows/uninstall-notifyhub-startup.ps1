param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "NotifyHubVR"),
    [string]$TaskName = "Notify Hub VR",
    [switch]$RemoveFiles
)

$ErrorActionPreference = "Stop"

$StartupDir = [Environment]::GetFolderPath("Startup")
$StartupCmdPath = Join-Path $StartupDir "Notify Hub VR.cmd"
$StartupVbsPath = Join-Path $StartupDir "Notify Hub VR.vbs"
$LauncherPath = Join-Path $InstallDir "start-notifyhub-hidden.vbs"
$RunKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$RunValueName = "Notify Hub VR"

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
    Write-Warning "Could not query or remove Scheduled Task. Continuing with user autostart cleanup."
    Write-Warning $_.Exception.Message
}

try {
    Remove-ItemProperty -Path $RunKeyPath -Name $RunValueName -ErrorAction SilentlyContinue
    Write-Host "Removed HKCU Run entry: $RunValueName"
} catch {
    Write-Warning "Could not remove HKCU Run entry."
    Write-Warning $_.Exception.Message
}

$RemovedStartupEntry = $false
if (Test-Path $StartupVbsPath) {
    Remove-Item -Force $StartupVbsPath
    Write-Host "Removed Startup folder entry: $StartupVbsPath"
    $RemovedStartupEntry = $true
}
if (Test-Path $StartupCmdPath) {
    Remove-Item -Force $StartupCmdPath
    Write-Host "Removed legacy Startup folder entry: $StartupCmdPath"
    $RemovedStartupEntry = $true
}
if (-not $RemovedStartupEntry) {
    Write-Host "Startup folder entry not found."
}

if (Test-Path $LauncherPath) {
    Remove-Item -Force $LauncherPath
    Write-Host "Removed hidden launcher: $LauncherPath"
}

if ($RemoveFiles) {
    Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
    Write-Host "Removed files: $InstallDir"
} else {
    Write-Host "Kept files: $InstallDir"
}
