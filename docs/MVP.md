# MVP Plan

## MVP Target

Build the simplest working PCVR notification path:

- Windows companion app receives short JSON notifications.
- The app renders a small local-only SteamVR/OpenVR overlay.
- The overlay appears at the edge of the user's view while VRChat is running through Virtual Desktop and SteamVR.
- The overlay is head-locked so it stays in a fixed place in the user's view.
- Notifications auto-hide after 5 seconds by default.
- No VRChat modification and no VRChat process injection.

## MVP Features

- Local HTTP endpoint for notifications.
- HTTP endpoint must accept requests from the Raspberry Pi notification server over the LAN.
- Default HTTP port is `17890`, because common ports such as `8080` may already be in use.
- JSON payload with at least `body`.
- Small text overlay supporting one or two short lines.
- Configurable screen position. The initial default can be whichever corner is easiest to implement cleanly.
- Configurable display duration, defaulting to 5 seconds.
- Optional notification sound with an off switch.
- If a new notification arrives while one is visible, replace the current notification immediately. This is sufficient for low volume such as one notification every few minutes.
- Authentication is not included in the MVP; use it only on a trusted LAN and do not expose the HTTP port to the internet.
- File-based configuration for MVP. A desktop settings UI can be added later if needed.

## Suggested First Milestone

1. Confirm overlay visibility on the Windows gaming laptop:
   - Quest 3S starts Virtual Desktop.
   - VRChat launches through SteamVR.
   - A SteamVR/OpenVR overlay is visible in-headset while VRChat is active.

2. Create a minimal Windows OpenVR overlay sample:
   - Show static text in a small overlay.
   - Keep it visible while VRChat is active.
   - Measure subjective performance impact.

3. Add notification receiver:
   - `POST /notify` on configurable port `17890`.
   - Body: `{ "body": "hello VR" }`
   - Display the message for 5 seconds.

4. Add configuration:
   - Position.
   - Font size.
   - Duration.
   - Sound on/off.

5. Add fallback debug output:
   - Desktop preview window or console log.
   - Optional VRChat OSC Chatbox sender for testing only.

## Next Implementation Steps

1. Scaffold a C#/.NET Windows companion app.
2. Add configuration for bind address, port, duration, position, and sound.
3. Add an HTTP `POST /notify` receiver on port `17890`.
4. Add a desktop-visible preview mode so non-VR behavior can be tested on Linux/Windows where possible.
5. Add the first SteamVR/OpenVR overlay prototype and verify it on the Windows gaming laptop.
