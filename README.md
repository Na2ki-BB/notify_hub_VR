# Notify Hub VR

VRChatプレイ中に、Raspberry Piなどの通知サーバから送られた短い通知をSteamVR/OpenVR overlayで表示するための実験プロジェクトです。

現在のMVPはC#/.NETのWindows companion appです。HTTP `POST /notify` を受け、console rendererではプレビュー表示し、OpenVR rendererではSteamVR overlay上に通知テキストを描画します。

## Docs

- [Specification](docs/SPEC.md)
- [MVP Plan](docs/MVP.md)
- [Implementation Notes](docs/IMPLEMENTATION.md)
- [Windows Setup](docs/WINDOWS_SETUP.md)
- [Windows Startup](docs/WINDOWS_STARTUP.md)
- [Raspberry Pi Forwarder](docs/RASPBERRY_PI_FORWARDER.md)
- [Operations](docs/OPERATIONS.md)
- [Language Selection ADR](docs/ADR-0001-windows-language-selection.md)

## Public Repository Notes

This repository is intended to be safe to publish. Runtime config files are ignored; copy the `*.example.json` files and edit local copies for real IP addresses, file paths, and ports.

Notify Hub VR does not implement authentication for the MVP. Bind and firewall it for a trusted LAN only, and do not expose port `17890` to the internet.

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
