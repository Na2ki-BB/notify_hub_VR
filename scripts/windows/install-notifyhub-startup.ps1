param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "NotifyHubVR"),
    [string]$TaskName = "Notify Hub VR",
    [switch]$StartNow
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$ProjectPath = Join-Path $RepoRoot "src\NotifyHubVr"
$AppDir = Join-Path $InstallDir "app"
$LogDir = Join-Path $InstallDir "logs"
$ConfigPath = Join-Path $InstallDir "config.openvr.json"
$RunnerPath = Join-Path $InstallDir "run-notifyhub.ps1"
$StartupDir = [Environment]::GetFolderPath("Startup")
$StartupCmdPath = Join-Path $StartupDir "Notify Hub VR.cmd"

$ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -ne $ExistingTask) {
    Write-Host "Stopping existing Scheduled Task before publishing: $TaskName"
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

Write-Host "Publishing Notify Hub VR to $AppDir"
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

dotnet publish $ProjectPath -c Release -o $AppDir

$ProgramFilesX86 = ${env:ProgramFiles(x86)}
if ([string]::IsNullOrWhiteSpace($ProgramFilesX86)) {
    $ProgramFilesX86 = $env:ProgramFiles
}
$SteamOpenVrDll = Join-Path $ProgramFilesX86 "Steam\steamapps\common\SteamVR\bin\win64\openvr_api.dll"
$OpenVrDest = Join-Path $AppDir "openvr_api.dll"
if (Test-Path $SteamOpenVrDll) {
    Copy-Item -Force $SteamOpenVrDll $OpenVrDest
    Write-Host "Copied openvr_api.dll from SteamVR."
} else {
    Write-Warning "openvr_api.dll was not found at $SteamOpenVrDll"
    Write-Warning "Copy it to $OpenVrDest before using the OpenVR renderer."
}

if (-not (Test-Path $ConfigPath)) {
    $LocalConfig = Join-Path $ProjectPath "config.openvr.json"
    $ExampleConfig = Join-Path $ProjectPath "config.openvr.example.json"
    if (Test-Path $LocalConfig) {
        Copy-Item $LocalConfig $ConfigPath
        Write-Host "Copied local config.openvr.json to $ConfigPath"
    } else {
        Copy-Item $ExampleConfig $ConfigPath
        Write-Host "Copied example config to $ConfigPath"
    }
} else {
    Write-Host "Keeping existing config at $ConfigPath"
}

$Runner = @'
$ErrorActionPreference = "Stop"
$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppPath = Join-Path $BaseDir "app\NotifyHubVr.exe"
$ConfigPath = Join-Path $BaseDir "config.openvr.json"
$LogDir = Join-Path $BaseDir "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogPath = Join-Path $LogDir ("notifyhub-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
"[$(Get-Date -Format o)] Starting Notify Hub VR" | Out-File -FilePath $LogPath -Encoding utf8 -Append
& $AppPath $ConfigPath *>> $LogPath
"[$(Get-Date -Format o)] Notify Hub VR exited with code $LASTEXITCODE" | Out-File -FilePath $LogPath -Encoding utf8 -Append
exit $LASTEXITCODE
'@
Set-Content -Path $RunnerPath -Value $Runner -Encoding UTF8

$PowerShellExe = (Get-Command powershell.exe).Source
$Action = New-ScheduledTaskAction `
    -Execute $PowerShellExe `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$RunnerPath`"" `
    -WorkingDirectory $InstallDir
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Principal = New-ScheduledTaskPrincipal `
    -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
    -LogonType Interactive `
    -RunLevel Limited
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0) `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

function Install-StartupFolderEntry {
    New-Item -ItemType Directory -Force -Path $StartupDir | Out-Null
    $StartupCommand = @"
@echo off
start "Notify Hub VR" /min "$PowerShellExe" -NoProfile -ExecutionPolicy Bypass -File "$RunnerPath"
"@
    Set-Content -Path $StartupCmdPath -Value $StartupCommand -Encoding ASCII
    Write-Host "Registered Startup folder entry: $StartupCmdPath"
}

$RegisteredTask = $false
try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Principal $Principal `
        -Settings $Settings `
        -Force | Out-Null
    $RegisteredTask = $true
    if (Test-Path $StartupCmdPath) {
        Remove-Item -Force $StartupCmdPath
    }
    Write-Host "Registered Scheduled Task: $TaskName"
} catch {
    if ($_.Exception.Message -match "Access is denied|アクセス.*拒否") {
        Write-Warning "Register-ScheduledTask was denied. Falling back to the current user's Startup folder."
        Install-StartupFolderEntry
    } else {
        throw
    }
}

Write-Host "InstallDir: $InstallDir"
Write-Host "Config: $ConfigPath"
Write-Host "Logs: $LogDir"

if ($StartNow) {
    if ($RegisteredTask) {
        Start-ScheduledTask -TaskName $TaskName
        Write-Host "Started Scheduled Task: $TaskName"
    } else {
        Start-Process -FilePath $PowerShellExe `
            -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $RunnerPath) `
            -WorkingDirectory $InstallDir `
            -WindowStyle Minimized
        Write-Host "Started Notify Hub VR directly."
    }
}

Write-Host ""
Write-Host "Useful commands:"
Write-Host "  Get-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Stop-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Stop-Process -Name NotifyHubVr -ErrorAction SilentlyContinue"
Write-Host "  Get-Content -Tail 80 -Wait '$LogDir\notifyhub-*.log'"
Write-Host "  Startup fallback file: $StartupCmdPath"
