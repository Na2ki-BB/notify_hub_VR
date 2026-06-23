# Windows Startup

Windows側のNotify Hub VRをログオン時に自動起動するための手順です。

標準では、現在ユーザーのStartupフォルダに起動用 `.cmd` を作成します。これは管理者権限なしで動き、WindowsにログオンしたときにNotify Hub VRを自動起動します。毎回コマンドを打つ必要はありません。

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

`-StartNow` を付けると、インストール後にその場でNotify Hub VRを起動します。次回以降はWindowsログオン時にStartupフォルダから自動起動します。

スクリプトは次の処理をします。

- 起動中の `NotifyHubVr.exe` を停止
- `dotnet publish` でNotify Hub VRをpublish
- `%LOCALAPPDATA%\NotifyHubVR\app` にアプリを配置
- SteamVRの `openvr_api.dll` をpublish先にコピー
- `%LOCALAPPDATA%\NotifyHubVR\config.openvr.json` を作成
- Startupフォルダに `Notify Hub VR.cmd` を作成
- ログを `%LOCALAPPDATA%\NotifyHubVR\logs` に出力

`%LOCALAPPDATA%\NotifyHubVR\config.openvr.json` がすでにある場合は上書きしません。

## 確認

Startupフォルダに登録されているか確認します。

PowerShell:

```powershell
Get-ChildItem ([Environment]::GetFolderPath("Startup")) -Filter "Notify Hub VR.cmd"
```

cmd.exe:

```bat
dir "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Notify Hub VR.cmd"
```

起動中か確認します。

PowerShell:

```powershell
Get-Process NotifyHubVr -ErrorAction SilentlyContinue
```

cmd.exe:

```bat
tasklist /FI "IMAGENAME eq NotifyHubVr.exe"
```

手動起動が必要な場合:

PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\NotifyHubVR\run-notifyhub.ps1"
```

cmd.exe:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\NotifyHubVR\run-notifyhub.ps1"
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

通常は不要です。どうしてもTask Schedulerでログオン時起動したい場合だけ `-UseScheduledTask` を付けます。

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\install-notifyhub-startup.ps1 -StartNow -UseScheduledTask
```

`Register-ScheduledTask` がアクセス拒否された場合、スクリプトはStartupフォルダ方式へfallbackします。

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
