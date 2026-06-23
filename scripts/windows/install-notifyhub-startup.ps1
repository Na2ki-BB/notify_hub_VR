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
$LauncherPath = Join-Path $InstallDir "start-notifyhub-hidden.vbs"
$StartupDir = [Environment]::GetFolderPath("Startup")
$StartupCmdPath = Join-Path $StartupDir "Notify Hub VR.cmd"
$StartupVbsPath = Join-Path $StartupDir "Notify Hub VR.vbs"
$RunKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$RunValueName = "Notify Hub VR"
$PowerShellExe = (Get-Command powershell.exe).Source
$WScriptExe = (Get-Command wscript.exe).Source

function ConvertTo-VbsString([string]$Value) {
    return $Value.Replace('"', '""')
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
} else {
    Remove-ScheduledTaskIfPresent
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

function Write-HiddenLauncher {
    $PowerShellForVbs = ConvertTo-VbsString $PowerShellExe
    $RunnerForVbs = ConvertTo-VbsString $RunnerPath
    $LogDirForVbs = ConvertTo-VbsString $LogDir
    $StartupLogForVbs = ConvertTo-VbsString (Join-Path $LogDir "startup-launch.log")
    $Launcher = @"
Option Explicit
Dim shell, fso, logDir, logPath, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
logDir = "$LogDirForVbs"
logPath = "$StartupLogForVbs"
If Not fso.FolderExists(logDir) Then
  fso.CreateFolder(logDir)
End If
AppendLog "launcher invoked"
command = """$PowerShellForVbs"" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$RunnerForVbs"""
AppendLog "starting runner"
shell.Run command, 0, False

Sub AppendLog(message)
  Dim file
  Set file = fso.OpenTextFile(logPath, 8, True)
  file.WriteLine Now & " " & message
  file.Close
End Sub
"@
    Set-Content -Path $LauncherPath -Value $Launcher -Encoding Unicode
    Write-Host "Wrote hidden launcher: $LauncherPath"
}

function Register-RunKeyEntry {
    New-Item -Path $RunKeyPath -Force | Out-Null
    $RunCommand = "`"$WScriptExe`" //B //Nologo `"$LauncherPath`""
    Set-ItemProperty -Path $RunKeyPath -Name $RunValueName -Value $RunCommand
    Remove-StartupFolderEntries
    Write-Host "Registered HKCU Run entry: $RunValueName"
}

function Install-StartupFolderEntry {
    New-Item -ItemType Directory -Force -Path $StartupDir | Out-Null
    Copy-Item -Force $LauncherPath $StartupVbsPath
    Remove-RunKeyEntry
    if (Test-Path $StartupCmdPath) {
        Remove-Item -Force $StartupCmdPath
    }
    Write-Host "Registered Startup folder entry: $StartupVbsPath"
}

function Start-NotifyHubInBackground {
    Start-Process -FilePath $WScriptExe `
        -ArgumentList @("//B", "//Nologo", $LauncherPath) `
        -WorkingDirectory $InstallDir `
        -WindowStyle Hidden
    Write-Host "Started Notify Hub VR through hidden launcher."
}

Write-HiddenLauncher

$RegisteredTask = $false
if ($UseScheduledTask) {
    Remove-RunKeyEntry
    Remove-StartupFolderEntries
    $Action = New-ScheduledTaskAction `
        -Execute $WScriptExe `
        -Argument "//B //Nologo `"$LauncherPath`"" `
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
        Write-Host "Registered Scheduled Task: $TaskName"
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

if ($StartNow) {
    if ($RegisteredTask) {
        try {
            Start-ScheduledTask -TaskName $TaskName
            Write-Host "Started Scheduled Task: $TaskName"
        } catch {
            Write-Warning "Start-ScheduledTask failed. Starting Notify Hub VR through hidden launcher."
            Write-Warning $_.Exception.Message
            Start-NotifyHubInBackground
        }
    } else {
        Start-NotifyHubInBackground
    }
}

Write-Host ""
Write-Host "Useful commands:"
Write-Host "  Get-ItemProperty -Path '$RunKeyPath' -Name '$RunValueName'"
Write-Host "  Get-Process NotifyHubVr -ErrorAction SilentlyContinue"
Write-Host "  Stop-Process -Name NotifyHubVr -ErrorAction SilentlyContinue # PowerShell"
Write-Host "  taskkill /IM NotifyHubVr.exe /F                         # cmd.exe"
Write-Host "  Get-Content -Tail 80 -Wait '$LogDir\notifyhub-*.log'"
Write-Host "  Get-Content -Tail 80 '$LogDir\startup-launch.log'"
Write-Host "  Hidden launcher: $LauncherPath"
Write-Host "  Use -UseScheduledTask only if you intentionally want Task Scheduler registration."
