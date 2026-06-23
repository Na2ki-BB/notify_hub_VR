# Notify Hub VR Specification

## Goal

VRChat playing in VR should show lightweight notifications in the user's view so the user can notice short messages without leaving VR.

## Current User Environment

- Headset: Meta Quest 3S.
- VR runtime path: Quest 3S connected to a Windows 11 gaming laptop through Virtual Desktop, using SteamVR.
- Target app: VRChat.
- Development machine for this repository: Linux.
- Expected notification source: a user-built notification delivery system that already sends notifications to Discord and JSON endpoints such as ESP32.
- Expected first sender: a notification server running on Raspberry Pi, sending HTTP POST requests to the Windows companion app over the LAN.

## Product Requirements

- Notifications must be visible only to the local user.
- Notifications should appear small at the edge of the view.
- Notifications should be head-locked, meaning they stay in a fixed position relative to the user's view.
- Notification body text should be displayed, but messages are expected to be short.
- No interaction is required for the first version. Display-only is acceptable.
- Optional lightweight sound is desirable, but it must be possible to disable it.
- The default display duration should be 5 seconds and easy to change later.
- Incoming notification volume is expected to be low, usually once every few minutes.
- Urgent notifications do not need a special visual style for MVP.
- Notification text may contain up to two short lines.
- Avoid approaches that modify the VRChat client, inject into the VRChat process, or otherwise create Terms of Service or account risk.
- Prefer the easiest route that can reach a working implementation quickly.
- Keep CPU, GPU, headset, and network overhead low.

## Candidate Display Paths

### SteamVR/OpenVR Overlay

This is the preferred first implementation path for PCVR.

Valve's OpenVR `IVROverlay` API can draw 2D images over the 3D scene regardless of which VR application is running. For this project, a small non-interactive overlay can be rendered by a companion app on the Windows PC.

Pros:

- Local-user only.
- Does not require VRChat modification.
- Can work while VRChat is running.
- Good fit for display-only notifications.
- Can be fed by local HTTP POST from the user's notification system.

Open points:

- Confirm whether Virtual Desktop exposes the SteamVR overlay as expected in this setup.
- Choose implementation language and overlay rendering stack for Windows.

Reference:

- https://github.com/ValveSoftware/openvr/wiki/IVROverlay_Overview

### VRChat OSC Chatbox

VRChat supports OSC input for the Chatbox. This can show text inside VRChat, but it is not ideal for private notifications because chatbox text can be visible to others depending on VRChat behavior and context.

Known constraints:

- Chatbox text is limited to 144 characters.
- A maximum of 9 lines is displayed.
- `/chatbox/input` can send text immediately or populate the keyboard.

Use this as a fallback or debug path, not the first private notification path.

Reference:

- https://docs.vrchat.com/docs/osc-as-input-controller

### VRChat OSC Avatar Parameters

VRChat OSC can drive avatar parameters. This could support avatar-based indicators, but it depends on avatar setup and is not the simplest route for readable private text.

Reference:

- https://docs.vrchat.com/docs/osc-avatar-parameters

### Quest Standalone Overlay

Quest standalone VRChat is not the first target. Third-party app overlays over another running immersive app are constrained on Quest/Horizon OS, and Meta removed the previous phone notification feature in Quest v60. Standalone Quest support should be treated as future research unless a supported display path is confirmed.

Reference:

- https://www.lifewire.com/meta-quest-update-v60-8410656

## Proposed Architecture

```text
Notification source(s)
        |
        v
Notify Hub receiver on Windows
        |
        v
Notification queue, filtering, formatting
        |
        v
SteamVR/OpenVR overlay renderer
        |
        v
Small local-only VR notification
```

## Initial Interface Contract

The first receiver should accept a simple JSON notification payload through HTTP POST. It must be reachable from the Raspberry Pi on the LAN, not only from `localhost`.

Default endpoint:

- Bind address: configurable, initially `0.0.0.0`.
- Port: configurable, initially `17890`.
- Path: `/notify`.

```json
{
  "title": "optional short title",
  "body": "short notification text",
  "level": "info",
  "duration_ms": 5000,
  "sound": false
}
```

Required field:

- `body`

Optional fields:

- `title`
- `level`: `info`, `warning`, `urgent`; accepted for future use, but no special visual style is required in MVP.
- `duration_ms`
- `sound`

## Initial Configuration

MVP configuration can be file-based. A desktop settings UI is not required yet.

Configurable values:

- HTTP bind address and port.
- Overlay position.
- Font size.
- Default display duration, initially `5000`.
- Sound on/off.
- Notification behavior while one is visible: replace the current notification immediately.
- LAN authentication: not included in the MVP. The HTTP endpoint must be used only on a trusted LAN and must not be exposed to the internet.

## Implementation Stack Notes

Use C#/.NET for the first Windows companion app. The HTTP receiver alone would be easy in Go or Python, but the harder and riskier part is SteamVR/OpenVR overlay rendering on Windows. C# has a practical OpenVR path while still keeping Windows app development, config, logging, JSON, and later UI work simpler than C++.

Detailed decision record: `docs/ADR-0001-windows-language-selection.md`.

## Non-Goals For MVP

- Replying to notifications.
- Marking external services as read.
- VRChat client modification.
- Public VRChat chat notification by default.
- Quest standalone support.
- Mobile phone notification mirroring.

## Risks

- The target play session uses SteamVR. Overlay support still must be verified on the actual Windows + Virtual Desktop setup.
- OpenVR overlay development and testing must happen on Windows with SteamVR available. The Linux development machine can hold shared code and documentation, but cannot fully verify VR overlay behavior alone.
- Rendering text into an overlay needs a lightweight implementation choice that works reliably on Windows.
