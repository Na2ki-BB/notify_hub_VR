# Notify Hub VR

VRChatプレイ中に、Raspberry Piなどの通知サーバから送られた短い通知をSteamVR/OpenVR overlayで表示するための実験プロジェクトです。

現在のMVPはC#/.NETのWindows companion appです。最初の段階ではHTTP `POST /notify` を受けてコンソールにプレビュー表示します。OpenVR rendererは固定色debug overlayの段階まで実装済みで、通知テキスト描画が次の実装ステップです。

## Docs

- [Specification](docs/SPEC.md)
- [MVP Plan](docs/MVP.md)
- [Implementation Notes](docs/IMPLEMENTATION.md)
- [Windows Setup](docs/WINDOWS_SETUP.md)
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
```
