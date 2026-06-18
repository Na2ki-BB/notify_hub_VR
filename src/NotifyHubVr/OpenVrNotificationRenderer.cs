using System.ComponentModel;
using System.Runtime.InteropServices;

namespace NotifyHubVr;

public sealed class OpenVrNotificationRenderer : INotificationRenderer, IDisposable
{
    private readonly OpenVrSession _session;

    public OpenVrNotificationRenderer(AppConfig config)
    {
        _session = new OpenVrSession(OpenVrOverlaySettings.FromConfig(config));
    }

    public Task ShowAsync(NotificationMessage message, CancellationToken cancellationToken)
    {
        var status = _session.EnsureInitialized();
        _session.ShowNotification(message);

        Console.WriteLine("OpenVR renderer accepted notification.");
        Console.WriteLine($"SteamVR runtime installed: {status.RuntimeInstalled}");
        Console.WriteLine($"HMD present: {status.HmdPresent}");
        Console.WriteLine("A text OpenVR overlay should now be visible in the headset view.");
        if (!string.IsNullOrWhiteSpace(message.Title))
        {
            Console.WriteLine(message.Title);
        }

        Console.WriteLine(message.Body);

        return Task.CompletedTask;
    }

    public Task HideAsync(CancellationToken cancellationToken)
    {
        _session.HideOverlay();
        return Task.CompletedTask;
    }

    public void Dispose()
    {
        _session.Dispose();
    }
}

internal sealed class OpenVrSession : IDisposable
{
    private const string OverlayKey = "notify_hub_vr.notification";
    private const string OverlayName = "Notify Hub VR";

    private readonly OpenVrOverlaySettings _settings;
    private bool _initialized;
    private ulong _overlayHandle;
    private OpenVrProbeStatus? _lastStatus;

    public OpenVrSession(OpenVrOverlaySettings settings)
    {
        _settings = settings;
    }

    public OpenVrProbeStatus EnsureInitialized()
    {
        if (_initialized && _lastStatus is not null)
        {
            return _lastStatus;
        }

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException(
                "The OpenVR renderer requires Windows with SteamVR installed. Use renderer=console on Linux.");
        }

        try
        {
            var runtimeInstalled = OpenVrNative.IsRuntimeInstalled();
            if (!runtimeInstalled)
            {
                throw new InvalidOperationException("SteamVR runtime is not installed or is not visible to OpenVR.");
            }

            var hmdPresent = OpenVrNative.IsHmdPresent();
            var error = EVRInitError.None;
            _ = OpenVrNative.InitInternal(ref error, EVRApplicationType.Overlay);
            if (error != EVRInitError.None)
            {
                throw new InvalidOperationException(
                    $"OpenVR initialization failed: {OpenVrNative.GetErrorDescription(error)} ({error}).");
            }

            _initialized = true;
            try
            {
                EnsureOverlay();
            }
            catch
            {
                Dispose();
                throw;
            }

            _lastStatus = new OpenVrProbeStatus(runtimeInstalled, hmdPresent);
            return _lastStatus;
        }
        catch (DllNotFoundException ex)
        {
            throw new InvalidOperationException(
                "openvr_api.dll was not found. Install SteamVR and make openvr_api.dll available on PATH or next to the executable.",
                ex);
        }
        catch (EntryPointNotFoundException ex)
        {
            throw new InvalidOperationException(
                "The loaded openvr_api.dll does not expose the expected OpenVR C API entry points.",
                ex);
        }
    }

    public void ShowNotification(NotificationMessage message)
    {
        EnsureInitialized();
        UpdateNotificationTexture(message);
        ThrowIfOverlayError(GetOverlay().ShowOverlay(_overlayHandle), "ShowOverlay");
    }

    public void HideOverlay()
    {
        if (_overlayHandle == 0)
        {
            return;
        }

        _ = GetOverlay().HideOverlay(_overlayHandle);
    }

    public void Dispose()
    {
        if (_overlayHandle != 0)
        {
            _ = GetOverlay().HideOverlay(_overlayHandle);
            _ = GetOverlay().DestroyOverlay(_overlayHandle);
            _overlayHandle = 0;
        }

        if (!_initialized)
        {
            return;
        }

        OpenVrNative.ShutdownInternal();
        _initialized = false;
    }

    private void EnsureOverlay()
    {
        if (_overlayHandle != 0)
        {
            return;
        }

        var handle = 0UL;
        var findError = GetOverlay().FindOverlay(OverlayKey, ref handle);
        if (findError == Valve.VR.EVROverlayError.None)
        {
            _overlayHandle = handle;
        }
        else
        {
            var createError = GetOverlay().CreateOverlay(OverlayKey, OverlayName, ref handle);
            ThrowIfOverlayError(createError, "CreateOverlay");
            _overlayHandle = handle;
        }

        ThrowIfOverlayError(GetOverlay().SetOverlayWidthInMeters(_overlayHandle, 0.55f), "SetOverlayWidthInMeters");
        ThrowIfOverlayError(GetOverlay().SetOverlayAlpha(_overlayHandle, 0.92f), "SetOverlayAlpha");

        var transform = CreateHeadLockedTransform(_settings.Position);
        ThrowIfOverlayError(
            GetOverlay().SetOverlayTransformTrackedDeviceRelative(
                _overlayHandle,
                Valve.VR.OpenVR.k_unTrackedDeviceIndex_Hmd,
                ref transform),
            "SetOverlayTransformTrackedDeviceRelative");
    }

    private static Valve.VR.HmdMatrix34_t CreateHeadLockedTransform(string position)
    {
        var x = position.Contains("left", StringComparison.OrdinalIgnoreCase)
            ? -0.38f
            : position.Contains("right", StringComparison.OrdinalIgnoreCase) ? 0.38f : 0f;
        var y = position.Contains("lower", StringComparison.OrdinalIgnoreCase)
            || position.Contains("bottom", StringComparison.OrdinalIgnoreCase)
            ? -0.22f
            : position.Contains("upper", StringComparison.OrdinalIgnoreCase)
            || position.Contains("top", StringComparison.OrdinalIgnoreCase) ? 0.22f : 0f;

        return new Valve.VR.HmdMatrix34_t
        {
            m0 = 1, m1 = 0, m2 = 0, m3 = x,
            m4 = 0, m5 = 1, m6 = 0, m7 = y,
            m8 = 0, m9 = 0, m10 = 1, m11 = -1.15f,
        };
    }

    private void UpdateNotificationTexture(NotificationMessage message)
    {
        byte[] pixels;
        try
        {
            pixels = OpenVrTextTextureRenderer.Render(message, _settings);
        }
        catch (Win32Exception ex)
        {
            throw new InvalidOperationException($"OpenVR text renderer failed: {ex.Message}", ex);
        }

        var buffer = Marshal.AllocHGlobal(pixels.Length);

        try
        {
            Marshal.Copy(pixels, 0, buffer, pixels.Length);
            ThrowIfOverlayError(
                GetOverlay().SetOverlayRaw(
                    _overlayHandle,
                    buffer,
                    OpenVrTextTextureRenderer.Width,
                    OpenVrTextTextureRenderer.Height,
                    OpenVrTextTextureRenderer.BytesPerPixel),
                "SetOverlayRaw");
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private static void ThrowIfOverlayError(Valve.VR.EVROverlayError error, string operation)
    {
        if (error == Valve.VR.EVROverlayError.None)
        {
            return;
        }

        var errorName = GetOverlay().GetOverlayErrorNameFromEnum(error);
        throw new InvalidOperationException($"OpenVR overlay {operation} failed: {errorName} ({error}).");
    }

    private static Valve.VR.CVROverlay GetOverlay()
    {
        return Valve.VR.OpenVR.Overlay
            ?? throw new InvalidOperationException("OpenVR overlay interface is unavailable.");
    }
}

public sealed record OpenVrProbeStatus(bool RuntimeInstalled, bool HmdPresent);

internal enum EVRApplicationType
{
    Other = 0,
    Scene = 1,
    Overlay = 2,
    Background = 3,
    Utility = 4,
    VRMonitor = 5,
    SteamWatchdog = 6,
    Bootstrapper = 7,
    WebHelper = 8,
    OpenXRInstance = 9,
    OpenXRScene = 10,
    OpenXROverlay = 11,
}

internal enum EVRInitError
{
    None = 0,
}

internal static class OpenVrNative
{
    private const string DllName = "openvr_api";

    [DllImport(DllName, EntryPoint = "VR_IsRuntimeInstalled", CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    internal static extern bool IsRuntimeInstalled();

    [DllImport(DllName, EntryPoint = "VR_IsHmdPresent", CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    internal static extern bool IsHmdPresent();

    [DllImport(DllName, EntryPoint = "VR_InitInternal", CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint InitInternal(ref EVRInitError error, EVRApplicationType applicationType);

    [DllImport(DllName, EntryPoint = "VR_ShutdownInternal", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void ShutdownInternal();

    [DllImport(DllName, EntryPoint = "VR_GetStringForHmdError", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr GetStringForHmdError(EVRInitError error);

    internal static string GetErrorDescription(EVRInitError error)
    {
        var pointer = GetStringForHmdError(error);
        return Marshal.PtrToStringAnsi(pointer) ?? "unknown OpenVR error";
    }
}
