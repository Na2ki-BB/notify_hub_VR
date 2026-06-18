using System.Runtime.InteropServices;

namespace NotifyHubVr;

public sealed class OpenVrNotificationRenderer : INotificationRenderer, IDisposable
{
    private readonly OpenVrSession _session = new();

    public Task ShowAsync(NotificationMessage message, CancellationToken cancellationToken)
    {
        var status = _session.EnsureInitialized();

        Console.WriteLine("OpenVR renderer accepted notification.");
        Console.WriteLine($"SteamVR runtime installed: {status.RuntimeInstalled}");
        Console.WriteLine($"HMD present: {status.HmdPresent}");
        Console.WriteLine("Overlay texture rendering is the next implementation step.");
        if (!string.IsNullOrWhiteSpace(message.Title))
        {
            Console.WriteLine(message.Title);
        }

        Console.WriteLine(message.Body);

        return Task.CompletedTask;
    }

    public Task HideAsync(CancellationToken cancellationToken)
    {
        return Task.CompletedTask;
    }

    public void Dispose()
    {
        _session.Dispose();
    }
}

internal sealed class OpenVrSession : IDisposable
{
    private bool _initialized;
    private OpenVrProbeStatus? _lastStatus;

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

    public void Dispose()
    {
        if (!_initialized)
        {
            return;
        }

        OpenVrNative.ShutdownInternal();
        _initialized = false;
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
