# Windows Startup

Windows側のNotify Hub VRをログオン時に自動起動するための手順です。

標準では、現在ユーザーのRun registry (`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`) に非表示ランチャーを登録します。これは管理者権限なしで動き、WindowsユーザーがログオンしたときにNotify Hub VRを非表示で自動起動します。毎回コマンドを打つ必要はありません。

SteamVR/OpenVR overlayはログイン中のデスクトップセッションで動かす必要があります。そのため、Windows Serviceではなく、ログオン後に通常アプリとして起動します。

## 初回インストール

PowerShellまたはcmd.exeでrepo rootへ移動して実行します。

PowerShell:

```powershell
cd C:\Users\YOUR_USER\notify_hub_VR
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\install-notifyhub-startup.ps1 -StartNow
```

cmd.exe:

```bat
cd /d C:\Users\YOUR_USER\notify_hub_VR
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\install-notifyhub-startup.ps1 -StartNow
```

`-StartNow` を付けると、インストール後にその場でNotify Hub VRを非表示で起動します。次回以降はWindowsユーザーのログオン時にRun registryから非表示で自動起動します。

スクリプトは次の処理をします。

- 起動中の `NotifyHubVr.exe` を停止
- `dotnet publish` でNotify Hub VRをpublish
- `%LOCALAPPDATA%\NotifyHubVR\app` にアプリを配置
- SteamVRの `openvr_api.dll` をpublish先にコピー
- `%LOCALAPPDATA%\NotifyHubVR\config.openvr.json` を作成
- `%LOCALAPPDATA%\NotifyHubVR\start-notifyhub-hidden.vbs` を作成
- 現在ユーザーのRun registryに `Notify Hub VR` を登録
- ログを `%LOCALAPPDATA%\NotifyHubVR\logs` に出力

`%LOCALAPPDATA%\NotifyHubVR\config.openvr.json` がすでにある場合は上書きしません。

## 確認

Run registryに登録されているか確認します。

PowerShell:

```powershell
Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Notify Hub VR"
```

起動ランチャーが存在するか確認します。

```powershell
Test-Path "$env:LOCALAPPDATA\NotifyHubVR\start-notifyhub-hidden.vbs"
```

PowerShellウィンドウは表示されません。起動中かどうかはプロセスまたはログで確認します。ランチャーがログオン時に呼ばれたかは `startup-launch.log` で確認できます。

PowerShell:

```powershell
Get-Process NotifyHubVr -ErrorAction SilentlyContinue
```

cmd.exe:

```bat
tasklist /FI "IMAGENAME eq NotifyHubVr.exe"
```

手動起動が必要な場合は、非表示ランチャーを呼びます。

PowerShell:

```powershell
wscript.exe //B //Nologo "$env:LOCALAPPDATA\NotifyHubVR\start-notifyhub-hidden.vbs"
```

cmd.exe:

```bat
wscript.exe //B //Nologo "%LOCALAPPDATA%\NotifyHubVR\start-notifyhub-hidden.vbs"
```

停止:

PowerShell:

```powershell
Stop-Process -Name NotifyHubVr -ErrorAction SilentlyContinue
```

cmd.exe:

```bat
taskkill /IM NotifyHubVr.exe /F
```

ログ確認:

PowerShell:

```powershell
Get-ChildItem "$env:LOCALAPPDATA\NotifyHubVR\logs"
Get-Content -Tail 80 "$env:LOCALAPPDATA\NotifyHubVR\logs\notifyhub-*.log"
```

起動中にリアルタイムでログを見る場合:

```powershell
Get-Content -Tail 80 -Wait "$env:LOCALAPPDATA\NotifyHubVR\logs\notifyhub-*.log"
Get-Content -Tail 80 "$env:LOCALAPPDATA\NotifyHubVR\logs\startup-launch.log"
```

## 更新

repo更新後、もう一度install scriptを実行します。既存configは維持されます。スクリプトが起動中の `NotifyHubVr.exe` を止めてからpublishするため、手動で停止コマンドを打つ必要はありません。

PowerShell:

```powershell
cd C:\Users\YOUR_USER\notify_hub_VR
git pull
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\install-notifyhub-startup.ps1 -StartNow
```

cmd.exe:

```bat
cd /d C:\Users\YOUR_USER\notify_hub_VR
git pull
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\install-notifyhub-startup.ps1 -StartNow
```

## Task Schedulerを使いたい場合

通常は不要です。どうしてもTask Schedulerでログオン時起動したい場合だけ `-UseScheduledTask` を付けます。標準のRun registry登録で問題がある場合だけ検討してください。

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\install-notifyhub-startup.ps1 -StartNow -UseScheduledTask
```

`Register-ScheduledTask` がアクセス拒否された場合、スクリプトはRun registry方式へfallbackします。

## アンインストール

自動起動だけ削除:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\uninstall-notifyhub-startup.ps1
```

配置ファイルも削除:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\uninstall-notifyhub-startup.ps1 -RemoveFiles
```

## 注意

- Windowsにログオンしていない状態ではOpenVR overlayは期待通り動きません。
- SteamVRとHMDが未接続の場合、HTTP POSTは503になることがあります。
- この設定はNotify Hub VRを起動するだけです。SteamVRの起動やQuest/Virtual Desktop接続は別途必要です。
