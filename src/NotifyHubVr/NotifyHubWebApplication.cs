using System.Text.Json;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace NotifyHubVr;

public static class NotifyHubWebApplication
{
    public static WebApplicationBuilder CreateBuilder(string[] args, AppConfig config)
    {
        var builder = WebApplication.CreateBuilder(args);
        ConfigureServices(builder.Services, config);
        return builder;
    }

    public static WebApplication Build(WebApplicationBuilder builder)
    {
        var app = builder.Build();
        MapEndpoints(app);
        return app;
    }

    private static void ConfigureServices(IServiceCollection services, AppConfig config)
    {
        services.ConfigureHttpJsonOptions(options =>
        {
            options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower;
            options.SerializerOptions.PropertyNameCaseInsensitive = true;
        });

        services.AddSingleton(config);
        services.TryAddSingleton<NotificationState>();
        services.AddNotificationRenderer(config);
        services.TryAddSingleton<NotificationDisplayService>();
    }

    private static void MapEndpoints(WebApplication app)
    {
        app.MapGet("/", (AppConfig config) => Results.Ok(new
        {
            service = "Notify Hub VR",
            endpoint = "/notify",
            config.BindAddress,
            config.Port,
            config.DefaultDurationMs,
            config.OverlayPosition,
            config.SoundEnabled,
        }));

        app.MapGet("/state", (NotificationState state) => Results.Ok(new
        {
            current = state.Current,
        }));

        app.MapPost("/notify", async (
            HttpContext httpContext,
            NotificationDisplayService display,
            AppConfig config,
            CancellationToken cancellationToken) =>
        {
            NotificationRequest? request;

            try
            {
                request = await httpContext.Request.ReadFromJsonAsync<NotificationRequest>(
                    cancellationToken: cancellationToken);
            }
            catch
            {
                return Results.BadRequest(new { error = "Request body must be valid JSON." });
            }

            if (request is null)
            {
                return Results.BadRequest(new { error = "Request body is required." });
            }

            var normalized = request.Normalize(config.DefaultDurationMs);
            if (string.IsNullOrWhiteSpace(normalized.Body))
            {
                return Results.BadRequest(new { error = "`body` is required." });
            }

            try
            {
                await display.ReplaceAsync(normalized, cancellationToken);
            }
            catch (PlatformNotSupportedException ex)
            {
                return Results.Problem(
                    title: "Notification renderer unavailable",
                    detail: ex.Message,
                    statusCode: StatusCodes.Status503ServiceUnavailable);
            }
            catch (InvalidOperationException ex) when (IsRendererUnavailable(ex))
            {
                return Results.Problem(
                    title: "Notification renderer unavailable",
                    detail: ex.Message,
                    statusCode: StatusCodes.Status503ServiceUnavailable);
            }

            return Results.Accepted(value: new
            {
                accepted = true,
                normalized.Title,
                normalized.Body,
                normalized.DurationMs,
                normalized.Sound,
            });
        });
    }

    private static bool IsRendererUnavailable(InvalidOperationException ex)
    {
        return ex.Message.Contains("OpenVR", StringComparison.OrdinalIgnoreCase)
            || ex.Message.Contains("SteamVR", StringComparison.OrdinalIgnoreCase)
            || ex.Message.Contains("openvr_api", StringComparison.OrdinalIgnoreCase)
            || ex.Message.Contains("renderer", StringComparison.OrdinalIgnoreCase);
    }
}
