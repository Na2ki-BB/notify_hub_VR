# Implementation Notes

## Current Scope

The first implementation stage is a C#/.NET companion app with:

- HTTP `POST /notify` receiver.
- HTTP `GET /state` debug endpoint.
- LAN-friendly default bind address, `0.0.0.0`.
- Default port `17890`.
- JSON notification payload.
- Replace-current-notification behavior.
- Console preview renderer.
- SteamVR/OpenVR overlay renderer with Windows GDI text texture rendering.

## Windows Setup

Install the .NET 8 SDK on the Windows gaming laptop:

- https://dotnet.microsoft.com/download/dotnet/8.0

Then run:

```powershell
cd src\NotifyHubVr
copy config.example.json config.json
dotnet run -- config.json
```

The app listens on:

```text
http://0.0.0.0:17890
```

Windows Defender Firewall may ask for network access. Allow private-network access if the Raspberry Pi is on the same LAN.

## Test From The Windows Machine

```powershell
curl.exe -X POST http://localhost:17890/notify `
  -H "Content-Type: application/json" `
  -d "{\"body\":\"hello VR\"}"
```

## Test From Raspberry Pi

Replace `WINDOWS_PC_IP` with the Windows gaming laptop's LAN IP address.

```bash
curl -X POST http://WINDOWS_PC_IP:17890/notify \
  -H 'Content-Type: application/json' \
  -d '{"body":"hello VR"}'
```

Two short lines are supported:

```bash
curl -X POST http://WINDOWS_PC_IP:17890/notify \
  -H 'Content-Type: application/json' \
  -d '{"title":"Notify Hub","body":"line 1\nline 2","duration_ms":5000}'
```

## Debug State

```powershell
curl.exe http://localhost:17890/state
```

## Payload

Required:

- `body`

Optional:

- `title`
- `level`
- `duration_ms`
- `sound`

Example:

```json
{
  "title": "optional title",
  "body": "short message",
  "level": "info",
  "duration_ms": 5000,
  "sound": false
}
```

## Next Step

Tune the OpenVR overlay placement, size, and typography after headset testing. The current `openvr` renderer draws notification text into a Windows GDI bitmap and submits it with `SetOverlayRaw`.

## OpenVR Probe

`renderer` can be set to `openvr` on Windows to verify that the app can load `openvr_api.dll` and initialize OpenVR as an overlay application.

```powershell
cd src\NotifyHubVr
copy config.openvr.example.json config.openvr.json
dotnet run -- config.openvr.json
```

Then send a normal notification:

```powershell
$json = @{ body = "日本語テスト`n2行目"; title = "Notify Hub"; level = "info" } | ConvertTo-Json
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
Invoke-RestMethod -Uri "http://localhost:17890/notify" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes
```

When sending Japanese text from Windows PowerShell, pass UTF-8 bytes to `-Body`. Passing a .NET string directly can replace non-ASCII characters with `?` before the server receives the JSON.

Expected current behavior:

- On Linux, `renderer=openvr` fails with a clear platform error.
- On Windows without SteamVR/OpenVR available, it fails with a clear OpenVR runtime or DLL error.
- On Windows with SteamVR available and an HMD connected, it initializes OpenVR and displays the notification text in a head-locked overlay.

## Tests

```bash
dotnet build src/NotifyHubVr
dotnet run --project tests/NotifyHubVr.Tests
```

The current tests cover notification normalization, config loading, renderer selection, replacement behavior, auto-hide behavior, HTTP endpoint behavior, and renderer failure handling.
