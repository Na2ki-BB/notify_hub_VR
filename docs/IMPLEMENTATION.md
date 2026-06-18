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

SteamVR/OpenVR overlay rendering is the next stage after the receiver is verified on Windows.

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

Add actual OpenVR overlay texture rendering to `OpenVrNotificationRenderer`. The current `openvr` renderer is a runtime initialization probe.

## OpenVR Probe

`renderer` can be set to `openvr` on Windows to verify that the app can load `openvr_api.dll` and initialize OpenVR as an overlay application.

```powershell
cd src\NotifyHubVr
copy config.openvr.example.json config.openvr.json
dotnet run -- config.openvr.json
```

Then send a normal notification:

```powershell
curl.exe -X POST http://localhost:17890/notify `
  -H "Content-Type: application/json" `
  -d "{\"body\":\"openvr probe\"}"
```

Expected current behavior:

- On Linux, `renderer=openvr` fails with a clear platform error.
- On Windows without SteamVR/OpenVR available, it fails with a clear OpenVR runtime or DLL error.
- On Windows with SteamVR available, it initializes OpenVR and logs that the notification reached the OpenVR renderer.

Actual VR overlay texture rendering is still the next implementation step.

## Tests

```bash
dotnet build src/NotifyHubVr
dotnet run --project tests/NotifyHubVr.Tests
```

The current tests cover notification normalization, config loading, renderer selection, replacement behavior, auto-hide behavior, HTTP endpoint behavior, and renderer failure handling.
