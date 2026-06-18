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

Add an OpenVR renderer implementing `INotificationRenderer`, replacing `ConsoleNotificationRenderer` when `renderer` is set to `openvr`.
