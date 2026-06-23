# Notify Hub VR

Notify Hub VRは、VRChatプレイ中にSteamVR/OpenVR overlayへ短い通知を表示するためのLAN向け通知システムです。

Windows側のcompanion appがHTTP通知を受け取り、SteamVR overlayとして視界固定の通知を表示します。必要に応じて、Raspberry Pi側のforwarderが既存システムのJSONファイル更新を監視し、新しい通知だけをWindows側へ転送します。

## Status

現在のMVPは、信頼できる家庭内LANでの実運用を想定した状態です。

- C#/.NET 8製のWindows companion app
- HTTP `POST /notify` receiver
- SteamVR/OpenVR overlay renderer
- 日本語通知表示
- Windowsログオン時の自動起動
- Raspberry Pi向けGo forwarder
- `systemd` 常駐化
- 監視元JSONファイルを移動・削除しないfile watch
- リアルタイム用途向けの古い通知の破棄

## Architecture

```text
source JSON file
  -> Raspberry Pi notify-forwarder
  -> HTTP POST /notify over trusted LAN
  -> Windows Notify Hub VR
  -> SteamVR/OpenVR overlay
```

forwarderが読むJSONは次の形です。

```json
{
  "updated_at": "2024-01-01T12:34:56",
  "lines": ["line 1", "line 2", "main message", "line 4"]
}
```

`lines[0]`, `lines[1]`, `lines[3]` をtitleにまとめ、`lines[2]` をbodyとして表示します。

## Security Notes

MVPでは認証を実装していません。信頼できるLAN内だけで使い、port `17890` をインターネットへ公開しないでください。必要に応じてWindows Firewallやルータ側で制限してください。

実運用のconfigや秘密情報はGitに入れない前提です。`*.example.json` をコピーして、実IP・実パス・portなどはローカルconfigにだけ書いてください。

主なignore対象:

- `src/NotifyHubVr/config.json`
- `src/NotifyHubVr/config.openvr.json`
- `cmd/notify-forwarder/config.json`
- `.env*`
- private key/certificate files

## Requirements

Windows側:

- Windows 11
- Steam
- SteamVR
- .NET 8 SDK
- Git for Windows

Raspberry Pi側:

- Go 1.23以上
- `systemd` が使えるLinux環境
- Windows側 `notify_url` へ接続できるLAN環境

## Windows Quick Start

通常運用では、Notify Hub VRを現在ユーザーのStartupフォルダに登録します。Task Schedulerは標準では使わないため、管理者権限は不要です。PowerShellウィンドウは表示せず、裏で起動します。

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

以後は、Windowsログオン時にNotify Hub VRが非表示で自動起動します。

起動確認:

```powershell
Get-Process NotifyHubVr -ErrorAction SilentlyContinue
```

Windows自身から通知テスト:

```powershell
$body = @{ body = "hello from Windows" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:17890/notify" -Method Post -ContentType "application/json" -Body $body
```

Windows側の詳細手順は [Windows Setup](docs/WINDOWS_SETUP.md)、[Windows Startup](docs/WINDOWS_STARTUP.md)、[Operations](docs/OPERATIONS.md) を参照してください。

## Raspberry Pi Quick Start

forwarder configをコピーして編集します。

```bash
cp cmd/notify-forwarder/config.example.json cmd/notify-forwarder/config.json
```

最低限設定する値:

```json
{
  "input_path": "/home/YOUR_USER/path/to/status-panel/hub/data/vrchat.json",
  "notify_url": "http://WINDOWS_PC_IP:17890/notify",
  "state_path": "/var/lib/notify-hub-vr-forwarder/state.json"
}
```

開発中に手動実行する場合:

```bash
go run ./cmd/notify-forwarder --config cmd/notify-forwarder/config.json
```

Raspberry Piで `systemd` serviceとして入れる場合:

```bash
./scripts/install-forwarder-systemd.sh
sudo systemctl enable --now notify-hub-vr-forwarder
```

ログ確認:

```bash
journalctl -u notify-hub-vr-forwarder -f
```

forwarderの詳細な挙動と設定は [Raspberry Pi Forwarder](docs/RASPBERRY_PI_FORWARDER.md) を参照してください。

## HTTP API

`POST /notify` は次のJSONを受け付けます。

```json
{
  "title": "Notify Hub",
  "body": "hello VR",
  "level": "info",
  "duration_ms": 5000,
  "sound": false
}
```

必須項目は `body` だけです。

LAN内の別端末から送る例:

```bash
curl -X POST http://WINDOWS_PC_IP:17890/notify \
  -H 'Content-Type: application/json; charset=utf-8' \
  -d '{"body":"hello VR"}'
```

## Tests

```bash
dotnet build src/NotifyHubVr
dotnet run --project tests/NotifyHubVr.Tests
go test ./...
go build -o /tmp/notify-hub-vr-forwarder ./cmd/notify-forwarder
```

## Documentation

- [Specification](docs/SPEC.md)
- [MVP Plan](docs/MVP.md)
- [Implementation Notes](docs/IMPLEMENTATION.md)
- [Windows Setup](docs/WINDOWS_SETUP.md)
- [Windows Startup](docs/WINDOWS_STARTUP.md)
- [Raspberry Pi Forwarder](docs/RASPBERRY_PI_FORWARDER.md)
- [Operations](docs/OPERATIONS.md)
- [Language Selection ADR](docs/ADR-0001-windows-language-selection.md)

## Limitations

- SteamVR/OpenVR overlayの表示確認は、実際のWindows + SteamVR + HMD環境が必要です。
- Quest standalone modeには対応していません。
- MVPは信頼できるLAN内の短い低頻度通知を想定しています。
- forwarderは最新状態を優先します。単一JSONファイルが高速に上書きされる場合、中間状態は通知されないことがあります。
