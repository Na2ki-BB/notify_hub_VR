# ADR-0001: Windows Companion App Language Selection

## Status

Accepted

## Context

The Windows companion app has two responsibilities:

- Receive notification JSON over HTTP POST from a Raspberry Pi on the LAN.
- Render a lightweight SteamVR/OpenVR overlay that is visible inside VRChat.

The HTTP server is simple in many languages. The main technical risk is the OpenVR overlay path: creating an overlay, rendering readable text into a texture, updating it on notification arrival, positioning it relative to the headset, and packaging the app for Windows.

Valve's OpenVR SDK contains native C/C++ headers, samples including `helloworldoverlay`, and a generated C# API file. The official overlay documentation describes `IVROverlay` as the interface for drawing 2D images over the 3D scene. Python bindings exist on PyPI, but they are unofficial.

References:

- https://github.com/ValveSoftware/openvr
- https://github.com/ValveSoftware/openvr/wiki/IVROverlay_Overview
- https://github.com/ValveSoftware/openvr/tree/master/headers
- https://github.com/ValveSoftware/openvr/tree/master/samples
- https://pypi.org/project/openvr/

## Evaluation Criteria

- OpenVR overlay implementation risk.
- Ability to render text into an overlay texture.
- Windows packaging and startup simplicity.
- HTTP, JSON, config, logging, and optional sound support.
- Future path to a tray app or simple settings UI.
- Runtime overhead while VRChat is already running.
- Maintainability for a small personal tool.

## Options

### C#/.NET

Strengths:

- Good fit for Windows desktop companion apps.
- HTTP server, JSON handling, config files, logging, and sound playback are straightforward.
- Valve's OpenVR repository includes `openvr_api.cs`, so C# interop is a known path.
- Easier to build a small tray app or settings UI later than C++.
- Easier memory management and application code than C++.

Weaknesses:

- Overlay texture rendering may still require native graphics interop or careful bitmap upload code.
- Some OpenVR examples and community snippets are C++ first, so translation may be needed.

Assessment:

Best initial choice for this project. It balances Windows practicality, implementation speed, and maintainability.

### C++

Strengths:

- Closest to Valve's native OpenVR API and sample code.
- Highest confidence for direct overlay and graphics interop.
- Lowest abstraction mismatch if OpenVR behavior becomes subtle.

Weaknesses:

- More boilerplate for HTTP, JSON, config, logs, app lifecycle, and later UI.
- Higher maintenance cost.
- More opportunities for memory/resource lifetime bugs.

Assessment:

Best fallback if C# hits a binding or texture update blocker. Also a good choice for a tiny proof-of-concept based directly on `helloworldoverlay`, but less friendly for the full companion app.

### Rust

Strengths:

- Good native performance and memory safety.
- Produces standalone Windows binaries.
- HTTP, JSON, config, logging, and async runtime support are strong.
- Native FFI can call C APIs such as OpenVR's C API.

Weaknesses:

- OpenVR overlay implementation would likely depend on community crates or handwritten FFI.
- Graphics texture upload and Windows VR interop would take more setup than C# or C++.
- Developer iteration is slower if the team is not already comfortable with Rust FFI and graphics.

Assessment:

Technically viable, but not the fastest MVP route. A strong candidate only if Rust expertise is already present and a small OpenVR overlay proof-of-concept is validated early.

### Go

Strengths:

- Excellent for HTTP servers and JSON.
- Produces simple single-file Windows binaries.
- Good fit for a Raspberry Pi sender or a non-VR notification gateway.

Weaknesses:

- OpenVR overlay support is not a first-class path in Valve's SDK.
- Likely requires cgo or third-party bindings for OpenVR.
- Graphics texture upload and Windows VR runtime integration would carry more integration risk than C# or C++.

Assessment:

Good for sender/receiver infrastructure, not recommended for the first overlay renderer.

### Node.js / Electron

Strengths:

- Very fast for HTTP, JSON, config files, and building a settings UI.
- Electron can create a polished desktop UI quickly.
- Good developer ergonomics for notification formatting and future web-based settings.

Weaknesses:

- Electron is heavy for a tiny always-on VR utility.
- OpenVR overlay integration would still require a native addon or helper process.
- Native graphics and texture upload would likely move the hard part into C++ anyway.
- Higher idle memory footprint than needed for this project.

Assessment:

Reasonable for a future settings UI, but not recommended as the main overlay renderer. If used, it should wrap a native C++/C# overlay service rather than implement OpenVR directly.

### Python

Strengths:

- Fastest for local experiments.
- PyPI has an `openvr` package using ctypes.
- HTTP and JSON are trivial.

Weaknesses:

- The OpenVR binding is unofficial.
- Packaging a reliable Windows app with native dependencies is more fragile.
- Long-running tray/desktop companion behavior is less clean than C#.
- Debugging OpenVR plus graphics plus Python packaging would be a poor risk tradeoff for MVP.

Assessment:

Acceptable for experiments, not recommended for the main Windows overlay app.

### Unity / C#

Strengths:

- Unity has strong VR ecosystem familiarity.
- Rendering text and UI in a VR-like environment is easy.
- C# application logic remains approachable.

Weaknesses:

- This project does not need to render a full VR app; it needs a lightweight SteamVR overlay companion.
- Unity runtime is large for a small notification utility.
- Packaging and startup cost are heavier than a small .NET app.
- Running Unity alongside VRChat may add unnecessary GPU/CPU overhead.

Assessment:

Not recommended for MVP. Useful only if the product later becomes a rich VR dashboard or 3D tool, which is outside the current lightweight-notification goal.

### Unreal Engine / C++

Strengths:

- Excellent 3D/VR rendering engine.
- Native C++ access is available.

Weaknesses:

- Far too heavy for a tiny text notification overlay.
- Build size, startup time, and development complexity are poor fits.
- Like Unity, it solves a larger problem than this project has.

Assessment:

Not recommended.

### Java / Kotlin

Strengths:

- HTTP and JSON are mature.
- Kotlin/JVM can be productive for service-style code.

Weaknesses:

- OpenVR integration would require JNI/JNA or third-party bindings.
- Windows tray/UI integration is workable but not as native-feeling as .NET.
- Packaging a JVM runtime is heavier than needed.

Assessment:

Not recommended. It has no clear advantage for this Windows/OpenVR use case.

### Delphi / Object Pascal

Strengths:

- Can build native Windows desktop apps.
- Good Windows UI support if the developer already knows the ecosystem.

Weaknesses:

- OpenVR integration would require manual bindings or uncommon third-party work.
- Smaller ecosystem for modern VR interop.
- Less portable knowledge for future maintainers.

Assessment:

Not recommended unless there is strong existing Delphi expertise.

### AutoHotkey / PowerShell

Strengths:

- Useful for automation and quick local scripts.
- Can call HTTP endpoints or launch helper apps.

Weaknesses:

- Not suitable for implementing OpenVR overlays.
- Poor fit for long-running graphics/native interop work.

Assessment:

Not candidates for the main app. They may be useful for development automation only.

## Shortlist

| Rank | Option | Fit | Reason |
| --- | --- | --- | --- |
| 1 | C#/.NET | Best | Best balance of Windows app ergonomics and plausible OpenVR interop. |
| 2 | C++ | Strong fallback | Closest to official OpenVR samples and native graphics, but higher app complexity. |
| 3 | Rust | Possible | Good native app story, but OpenVR/graphics FFI raises MVP risk. |
| 4 | Go | Infrastructure only | Great for HTTP, weak for OpenVR overlay rendering. |
| 5 | Python | Experiment only | Fast to try, weak packaging/native interop story. |
| 6 | Node/Electron | UI only | Good settings UI, too heavy and still needs native overlay code. |
| 7 | Unity | Too heavy | Good VR engine, wrong size for a lightweight overlay utility. |
| 8 | Java/Kotlin | Poor fit | Adds JVM/JNI complexity without OpenVR advantage. |
| 9 | Unreal | Too heavy | Overkill for notification text. |

## Decision

Use C#/.NET for the first Windows companion app. The project owner is not expected to already know this stack; implementation should include clear setup notes, build commands, and operational instructions.

Fallback path:

- If C# OpenVR binding or texture upload blocks progress, build the overlay renderer in C++ and keep the HTTP/config layer in C# or move the whole MVP to C++.

Non-goal:

- Do not choose Go, Python, Node/Electron, Java/Kotlin, Unity, or Unreal for the first SteamVR overlay renderer unless a small proof-of-concept proves the overlay path is reliable and lightweight.

## Consequences

- The first implementation should be developed and tested on the Windows gaming laptop with SteamVR installed.
- The Linux machine can hold the repository, docs, and non-VR tests, but cannot fully validate the OpenVR overlay.
- Raspberry Pi integration remains language-neutral because it only needs to send HTTP POST JSON.
