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
$AppDir = Join-Path $InstallDir "app"
$LogDir = Join-Path $InstallDir "logs"
$ConfigPath = Join-Path $InstallDir "config.openvr.json"
$RunnerPath = Join-Path $InstallDir "run-notifyhub.ps1"
$StartupDir = [Environment]::GetFolderPath("Startup")
$StartupCmdPath = Join-Path $StartupDir "Notify Hub VR.cmd"
$StartupVbsPath = Join-Path $StartupDir "Notify Hub VR.vbs"
$PowerShellExe = (Get-Command powershell.exe).Source

if ($UseStartupFolder) {
    Write-Warning "-UseStartupFolder is now the default and can be omitted."
}

$RunningProcesses = Get-Process -Name NotifyHubVr -ErrorAction SilentlyContinue
if ($null -ne $RunningProcesses) {
    Write-Host "Stopping running NotifyHubVr process before publishing."
    $RunningProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

if ($UseScheduledTask) {
    try {
        $ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($null -ne $ExistingTask) {
            Write-Host "Stopping existing Scheduled Task before publishing: $TaskName"
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    } catch {
        Write-Warning "Could not query or stop the existing Scheduled Task. Continuing with publish."
        Write-Warning $_.Exception.Message
    }
}

Write-Host "Publishing Notify Hub VR to $AppDir"
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

dotnet publish $ProjectPath -c Release -o $AppDir
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE."
}

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

function ConvertTo-VbsString([string]$Value) {
    return $Value.Replace('"', '""')
}

function Install-StartupFolderEntry {
    New-Item -ItemType Directory -Force -Path $StartupDir | Out-Null
    $PowerShellForVbs = ConvertTo-VbsString $PowerShellExe
    $RunnerForVbs = ConvertTo-VbsString $RunnerPath
    $StartupScript = @"
Set shell = CreateObject("WScript.Shell")
shell.Run """$PowerShellForVbs"" -NoProfile -ExecutionPolicy Bypass -File ""$RunnerForVbs""", 0, False
"@
    Set-Content -Path $StartupVbsPath -Value $StartupScript -Encoding Unicode
    if (Test-Path $StartupCmdPath) {
        Remove-Item -Force $StartupCmdPath
    }
    Write-Host "Registered hidden Startup folder entry: $StartupVbsPath"
}

function Start-NotifyHubDirectly {
    Start-Process -FilePath $PowerShellExe `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $RunnerPath) `
        -WorkingDirectory $InstallDir `
        -WindowStyle Hidden
    Write-Host "Started Notify Hub VR directly in the background."
}

$RegisteredTask = $false
if ($UseScheduledTask) {
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
        if (Test-Path $StartupVbsPath) {
            Remove-Item -Force $StartupVbsPath
        }
        Write-Host "Registered Scheduled Task: $TaskName"
    } catch {
        Write-Warning "Register-ScheduledTask failed. Falling back to the current user's Startup folder."
        Write-Warning $_.Exception.Message
        Install-StartupFolderEntry
    }
} else {
    Write-Host "Using Startup folder entry for logon launch."
    Install-StartupFolderEntry
}

Write-Host "InstallDir: $InstallDir"
Write-Host "Config: $ConfigPath"
Write-Host "Logs: $LogDir"

if ($StartNow) {
    if ($RegisteredTask) {
        try {
            Start-ScheduledTask -TaskName $TaskName
            Write-Host "Started Scheduled Task: $TaskName"
        } catch {
            Write-Warning "Start-ScheduledTask failed. Starting Notify Hub VR directly."
            Write-Warning $_.Exception.Message
            Start-NotifyHubDirectly
        }
    } else {
        Start-NotifyHubDirectly
    }
}

Write-Host ""
Write-Host "Useful commands:"
Write-Host "  Stop-Process -Name NotifyHubVr -ErrorAction SilentlyContinue # PowerShell"
Write-Host "  taskkill /IM NotifyHubVr.exe /F                         # cmd.exe"
Write-Host "  Get-Content -Tail 80 -Wait '$LogDir\notifyhub-*.log'"
Write-Host "  Startup folder file: $StartupVbsPath"
Write-Host "  Use -UseScheduledTask only if you intentionally want Task Scheduler registration."
