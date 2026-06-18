using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace NotifyHubVr;

public static class NotificationRendererRegistration
{
    public static IServiceCollection AddNotificationRenderer(this IServiceCollection services, AppConfig config)
    {
        switch (config.Renderer.Trim().ToLowerInvariant())
        {
            case "console":
                services.TryAddSingleton<INotificationRenderer, ConsoleNotificationRenderer>();
                return services;

            case "openvr":
                services.TryAddSingleton<INotificationRenderer, OpenVrNotificationRenderer>();
                return services;

            default:
                throw new InvalidOperationException(
                    $"Unknown renderer '{config.Renderer}'. Supported renderers: console, openvr.");
        }
    }
}
