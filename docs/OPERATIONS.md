# Operations

Notify Hub VRを運用するときに見るログと、よくある状態の切り分けです。

## Raspberry Pi forwarder

systemdで動かしている場合:

```bash
systemctl status notify-hub-vr-forwarder
journalctl -u notify-hub-vr-forwarder -f
```

直近100行だけ見る場合:

```bash
journalctl -u notify-hub-vr-forwarder -n 100 --no-pager
```

再起動:

```bash
sudo systemctl restart notify-hub-vr-forwarder
```

よく見るログ:

- `input change detected`: JSONファイル更新を検知しています。
- `notification sent`: Windows側への送信成功です。
- `context deadline exceeded`: Windows PCに届いていないか、応答がtimeoutしています。
- `503 Service Unavailable`: Windows側Notify Hub VRには届いていますが、OpenVR/HMD側がまだ通知を表示できない状態です。

## Windows Notify Hub VR

Scheduled Taskで動かしている場合:

```powershell
Get-ScheduledTask -TaskName "Notify Hub VR"
Get-ScheduledTaskInfo -TaskName "Notify Hub VR"
```

手動起動・停止:

```powershell
Start-ScheduledTask -TaskName "Notify Hub VR"
Stop-ScheduledTask -TaskName "Notify Hub VR"
```

ログ場所:

```powershell
$logDir = "$env:LOCALAPPDATA\NotifyHubVR\logs"
Get-ChildItem $logDir
Get-Content -Tail 100 (Get-ChildItem $logDir -Filter "notifyhub-*.log" | Sort-Object LastWriteTime | Select-Object -Last 1).FullName
```

リアルタイムで見る場合:

```powershell
$latest = (Get-ChildItem "$env:LOCALAPPDATA\NotifyHubVR\logs" -Filter "notifyhub-*.log" | Sort-Object LastWriteTime | Select-Object -Last 1).FullName
Get-Content -Tail 100 -Wait $latest
```

よく見るログ:

- `Now listening on: http://0.0.0.0:17890`: Windows側HTTP serverは起動しています。
- `OpenVR renderer accepted notification.`: OpenVR rendererまで通知が届いています。
- `OpenVR initialization failed: Hmd Not Found`: SteamVRがHMDを認識していません。Quest/Virtual Desktop/SteamVRの接続状態を確認してください。
- `openvr_api.dll was not found`: SteamVRの `openvr_api.dll` がpublish先にありません。install scriptを再実行するか、SteamVRのDLLをコピーしてください。

## 疎通確認

PiからWindows HTTP serverを見る:

```bash
curl -v http://WINDOWS_PC_IP:17890/
```

Piから直接通知する:

```bash
curl -X POST http://WINDOWS_PC_IP:17890/notify \
  -H 'Content-Type: application/json; charset=utf-8' \
  -d '{"body":"hello from raspberry pi"}'
```

Windows自身から通知する:

```powershell
$json = @{ body = "Windows local test" } | ConvertTo-Json
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
Invoke-RestMethod -Uri "http://localhost:17890/notify" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes
```

## 判断順

1. Piの `journalctl` に `input change detected` があるか。
2. Piの `curl -v http://WINDOWS_PC_IP:17890/` が200を返すか。
3. Windows logに `Now listening on` があるか。
4. Windows logにOpenVR/HMDエラーがないか。
5. HMDを装着し、Virtual DesktopとSteamVRがHMDを認識しているか。
