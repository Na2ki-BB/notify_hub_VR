# Windows Startup

Windows側のNotify Hub VRをログオン時に自動起動するための手順です。

SteamVR/OpenVR overlayはログイン中のデスクトップセッションで動かす必要があります。そのため、Windows Serviceではなく、Task Schedulerの「ログオン時に起動するタスク」として登録します。Task Schedulerへの登録がアクセス拒否された場合は、現在ユーザーのStartupフォルダに起動用 `.cmd` を置く方式へ自動でfallbackします。

## インストール

PowerShellでrepo rootへ移動して実行します。

```powershell
cd C:\Users\tpall\notify_hub_VR
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\install-notifyhub-startup.ps1
```

すぐ起動もしたい場合:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\install-notifyhub-startup.ps1 -StartNow
```

`Register-ScheduledTask` がアクセス拒否される環境では、最初からStartupフォルダ方式を指定できます。

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\install-notifyhub-startup.ps1 -StartNow -UseStartupFolder
```

スクリプトは次の処理をします。

- `dotnet publish` でNotify Hub VRをpublish
- `%LOCALAPPDATA%\NotifyHubVR\app` にアプリを配置
- SteamVRの `openvr_api.dll` をpublish先にコピー
- `%LOCALAPPDATA%\NotifyHubVR\config.openvr.json` を作成
- 通常は `Notify Hub VR` というScheduled Taskを登録
- `-UseStartupFolder` 指定時、またはScheduled Task登録に失敗した場合、Startupフォルダに `Notify Hub VR.cmd` を作成
- ログを `%LOCALAPPDATA%\NotifyHubVR\logs` に出力

`%LOCALAPPDATA%\NotifyHubVR\config.openvr.json` がすでにある場合は上書きしません。

## 確認

登録済みtask。Startupフォルダ方式を使った場合はtaskがないので、この確認は不要です。

```powershell
Get-ScheduledTask -TaskName "Notify Hub VR"
```

Startupフォルダfallbackを使っている場合:

```powershell
Get-ChildItem ([Environment]::GetFolderPath("Startup")) -Filter "Notify Hub VR.cmd"
```

手動起動。Startupフォルダ方式を使った場合は次の `run-notifyhub.ps1` を直接起動してください。

```powershell
Start-ScheduledTask -TaskName "Notify Hub VR"
```

Startupフォルダfallbackを使っていてScheduled Taskがない場合:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\NotifyHubVR\run-notifyhub.ps1"
```

停止:

```powershell
Stop-ScheduledTask -TaskName "Notify Hub VR"
Stop-Process -Name NotifyHubVr -ErrorAction SilentlyContinue
```

ログ確認:

```powershell
Get-ChildItem "$env:LOCALAPPDATA\NotifyHubVR\logs"
Get-Content -Tail 80 "$env:LOCALAPPDATA\NotifyHubVR\logs\notifyhub-*.log"
```

起動中にリアルタイムでログを見る場合:

```powershell
Get-Content -Tail 80 -Wait "$env:LOCALAPPDATA\NotifyHubVR\logs\notifyhub-*.log"
```

## 更新

repo更新後、もう一度install scriptを実行します。既存configは維持されます。

```powershell
git pull
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\install-notifyhub-startup.ps1 -StartNow
```

Startupフォルダ方式を使う環境では、更新時も同じオプションを付けてください。

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\windows\install-notifyhub-startup.ps1 -StartNow -UseStartupFolder
```

install scriptは既存taskが動いている場合、publish前に自動で停止します。既存taskの確認自体がアクセス拒否される場合でも、publishは続行します。

## アンインストール

Scheduled TaskとStartupフォルダfallbackだけ削除:

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
- Task自体はNotify Hub VRを起動するだけです。SteamVRの起動やQuest/Virtual Desktop接続は別途必要です。
