# Notify Hub VR

VRChatプレイ中に、Raspberry Piなどの通知サーバから送られた短い通知をSteamVR/OpenVR overlayで表示するための実験プロジェクトです。

現在のMVPはC#/.NETのWindows companion appです。HTTP `POST /notify` を受け、console rendererではプレビュー表示し、OpenVR rendererではSteamVR overlay上に通知テキストを描画します。

## Docs

- [Specification](docs/SPEC.md)
- [MVP Plan](docs/MVP.md)
- [Implementation Notes](docs/IMPLEMENTATION.md)
- [Windows Setup](docs/WINDOWS_SETUP.md)
- [Raspberry Pi Forwarder](docs/RASPBERRY_PI_FORWARDER.md)
- [Language Selection ADR](docs/ADR-0001-windows-language-selection.md)

## Quick Start

Windows gaming laptopに .NET 8 SDK を入れてから実行します。

```powershell
cd src\NotifyHubVr
copy config.example.json config.json
dotnet run -- config.json
```

Raspberry PiなどLAN内の端末から:

```bash
curl -X POST http://WINDOWS_PC_IP:17890/notify \
  -H 'Content-Type: application/json' \
  -d '{"body":"hello VR"}'
```

## Test

```bash
dotnet build src/NotifyHubVr
dotnet run --project tests/NotifyHubVr.Tests
go test ./...
```
