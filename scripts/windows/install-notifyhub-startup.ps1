param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "NotifyHubVR"),
    [string]$TaskName = "Notify Hub VR",
    [switch]$StartNow,
    [switch]$UseStartupFolder,
    [switch]$UseScheduledTask
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$ProjectPath = Join-Path $RepoRoot "src\NotifyHubVr"
$LauncherProjectPath = Join-Path $RepoRoot "src\NotifyHubVr.Launcher"
$AppDir = Join-Path $InstallDir "app"
$LauncherDir = Join-Path $InstallDir "launcher"
$LogDir = Join-Path $InstallDir "logs"
$ConfigPath = Join-Path $InstallDir "config.openvr.json"
$AppExe = Join-Path $AppDir "NotifyHubVr.exe"
$LauncherExe = Join-Path $LauncherDir "NotifyHubVr.Launcher.exe"
$LegacyRunnerPath = Join-Path $InstallDir "run-notifyhub.ps1"
$LegacyVbsPath = Join-Path $InstallDir "start-notifyhub-hidden.vbs"
$StartupDir = [Environment]::GetFolderPath("Startup")
$StartupCmdPath = Join-Path $StartupDir "Notify Hub VR.cmd"
$StartupVbsPath = Join-Path $StartupDir "Notify Hub VR.vbs"
$RunKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$RunValueName = "Notify Hub VR"

function Get-LauncherArguments {
    return @("`"$AppExe`"", "`"$ConfigPath`"", "`"$LogDir`"")
}

function Get-LauncherCommandLine {
    return "`"$LauncherExe`" `"$AppExe`" `"$ConfigPath`" `"$LogDir`""
}

function Stop-NotifyHubProcesses {
    foreach ($ProcessName in @("NotifyHubVr", "NotifyHubVr.Launcher")) {
        $Processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($null -ne $Processes) {
            Write-Host "Stopping running process: $ProcessName"
            $Processes | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 2
}

function Remove-StartupFolderEntries {
    if (Test-Path $StartupCmdPath) {
        Remove-Item -Force $StartupCmdPath
        Write-Host "Removed legacy Startup folder entry: $StartupCmdPath"
    }
    if (Test-Path $StartupVbsPath) {
        Remove-Item -Force $StartupVbsPath
        Write-Host "Removed Startup folder entry: $StartupVbsPath"
    }
}

function Remove-RunKeyEntry {
    try {
        Remove-ItemProperty -Path $RunKeyPath -Name $RunValueName -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Could not remove HKCU Run entry."
        Write-Warning $_.Exception.Message
    }
}

function Remove-ScheduledTaskIfPresent {
    try {
        $ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($null -ne $ExistingTask) {
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "Removed existing Scheduled Task: $TaskName"
        }
    } catch {
        Write-Warning "Could not query or remove the existing Scheduled Task. Continuing."
        Write-Warning $_.Exception.Message
    }
}

function Remove-LegacyLaunchers {
    foreach ($LegacyPath in @($LegacyRunnerPath, $LegacyVbsPath)) {
        if (Test-Path $LegacyPath) {
            Remove-Item -Force $LegacyPath
            Write-Host "Removed legacy launcher file: $LegacyPath"
        }
    }
}

function Publish-Project([string]$Project, [string]$OutputDir, [string]$Label) {
    Write-Host "Publishing $Label to $OutputDir"
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    dotnet publish $Project -c Release -o $OutputDir
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed for $Label with exit code $LASTEXITCODE."
    }
}

function Register-RunKeyEntry {
    New-Item -Path $RunKeyPath -Force | Out-Null
    Set-ItemProperty -Path $RunKeyPath -Name $RunValueName -Value (Get-LauncherCommandLine)
    Remove-StartupFolderEntries
    Write-Host "Registered HKCU Run entry: $RunValueName"
}

function Install-StartupFolderEntry {
    New-Item -ItemType Directory -Force -Path $StartupDir | Out-Null
    $StartupCommand = @"
@echo off
start "Notify Hub VR" "$LauncherExe" "$AppExe" "$ConfigPath" "$LogDir"
"@
    Set-Content -Path $StartupCmdPath -Value $StartupCommand -Encoding ASCII
    if (Test-Path $StartupVbsPath) {
        Remove-Item -Force $StartupVbsPath
    }
    Remove-RunKeyEntry
    Write-Host "Registered Startup folder entry: $StartupCmdPath"
}

function Register-ScheduledTaskEntry {
    Remove-RunKeyEntry
    Remove-StartupFolderEntries
    $Action = New-ScheduledTaskAction `
        -Execute $LauncherExe `
        -Argument "`"$AppExe`" `"$ConfigPath`" `"$LogDir`"" `
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

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Principal $Principal `
        -Settings $Settings `
        -Force | Out-Null
    Write-Host "Registered Scheduled Task: $TaskName"
}

function Start-NotifyHubInBackground {
    Start-Process -FilePath $LauncherExe `
        -ArgumentList (Get-LauncherArguments) `
        -WorkingDirectory $InstallDir `
        -WindowStyle Hidden
    Write-Host "Started Notify Hub VR through launcher."
}

Stop-NotifyHubProcesses
Remove-LegacyLaunchers

if (-not $UseScheduledTask) {
    Remove-ScheduledTaskIfPresent
}

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Publish-Project $ProjectPath $AppDir "Notify Hub VR"
Publish-Project $LauncherProjectPath $LauncherDir "Notify Hub VR launcher"

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

if ($UseScheduledTask) {
    try {
        Register-ScheduledTaskEntry
    } catch {
        Write-Warning "Register-ScheduledTask failed. Falling back to HKCU Run entry."
        Write-Warning $_.Exception.Message
        Register-RunKeyEntry
    }
} elseif ($UseStartupFolder) {
    Write-Warning "Using Startup folder entry instead of the default HKCU Run entry."
    Install-StartupFolderEntry
} else {
    Register-RunKeyEntry
}

Write-Host "InstallDir: $InstallDir"
Write-Host "Config: $ConfigPath"
Write-Host "Logs: $LogDir"
Write-Host "Launcher: $LauncherExe"

if ($StartNow) {
    Start-NotifyHubInBackground
}

Write-Host ""
Write-Host "Useful commands:"
Write-Host "  Get-ItemProperty -Path '$RunKeyPath' -Name '$RunValueName'"
Write-Host "  Get-Process NotifyHubVr -ErrorAction SilentlyContinue"
Write-Host "  Get-Process NotifyHubVr.Launcher -ErrorAction SilentlyContinue"
Write-Host "  Stop-Process -Name NotifyHubVr,NotifyHubVr.Launcher -ErrorAction SilentlyContinue # PowerShell"
Write-Host "  taskkill /IM NotifyHubVr.exe /F                         # cmd.exe"
Write-Host "  taskkill /IM NotifyHubVr.Launcher.exe /F                # cmd.exe"
Write-Host "  Get-Content -Tail 80 -Wait '$LogDir\notifyhub-*.log'"
Write-Host "  Get-Content -Tail 80 '$LogDir\startup-launch.log'"
Write-Host "  Use -UseScheduledTask only if you intentionally want Task Scheduler registration."
